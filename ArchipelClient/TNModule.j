/*
 * TNModule.j
 *
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import <StropheCappuccino/StropheCappuccino.j>

/*! @global
    @group TNModule
    the namespace of Archipel Push Notification stanzas.
*/
TNArchipelPushNotificationNamespace = @"archipel:push";


/*! @ingroup archipelcore
    This is the root class of every module.
    All modules must inherit from TNModule.

    If the child class must perform custom operations on module events (see below),
    it *MUST* call the super method or the module can make all archipel unstable.

    Modules events are the following :
     - <b>willLoad</b>: This message is sent when module will be called by changing selection in roster.
        This assert than the module has its roster and entity properties sets.
     - <b>willUnload</b>: This message is sent when user change roster selection. It can be reloaded instant later,
        with another roster and entity.
     - <b>willShow</b>: This message is sent when user will display the GUI of the module.
     - <b>willHide</b>: This message is sent when user displays other module.

    A module can perform background task only if it is loaded. Loaded doesn't mean displayed on the screen. For example
    a statistique module can start collecting data on willLoad message in background. When message willShow is sent,
    module can perform operation to display the collected data in background and update this display. When willHide
    message is sent, module can stop to update the UI, but will continue to collect data. On willUnload message, the
    module *MUST* stop anything.

    The root class willUnload will remove all TNStropheConnection handler, and remove the module from any subscription
    to CPNotification and all Archipel Push Notifications.

    You can use SampleTabModule and SampleToolbarModule to get example of module implémentation.

*/
@implementation TNModule : CPViewController
{
    @outlet CPView          viewPreferences         @accessors;

    BOOL                    _isActive               @accessors(property=isActive, readonly);
    BOOL                    _isVisible              @accessors(property=isVisible, readonly);
    BOOL                    _toolbarItemOnly        @accessors(getter=isToolbarItemOnly, setter=setToolbarItemOnly:);
    CPArray                 _supportedEntityTypes   @accessors(property=supportedEntityTypes);
    CPBundle                _bundle                 @accessors(property=bundle);
    CPMenu                  _menu                   @accessors(property=menu);
    CPMenuItem              _menuItem               @accessors(property=menuItem);
    CPString                _label                  @accessors(property=label);
    CPString                _name                   @accessors(property=name);
    id                      _entity                 @accessors(property=entity);
    int                     _animationDuration      @accessors(property=animationDuration);
    int                     _index                  @accessors(property=index);
    TNStropheConnection     _connection             @accessors(property=connection);
    TNStropheGroup          _group                  @accessors(property=group);
    TNStropheRoster         _roster                 @accessors(property=roster);

    CPArray                 _registredSelectors;
    CPArray                 _pubsubRegistrar;
}

- (id)init
{
    if (self = [super init])
    {
        _isActive           = NO;
        _isVisible          = NO;
        _pubsubRegistrar    = [CPArray array];

    }

    return self;
}
/*! this method set the roster, the TNStropheConnection and the contact that module will be allow to access.
    YOU MUST NOT CALL THIS METHOD BY YOURSELF. TNModuleLoader will do the job for you.

    @param anEntity : TNStropheContact concerned by the module
    @param aConnection : TNStropheConnection general connection
    @param aRoster : TNStropheRoster general roster
*/
- (void)initializeWithEntity:(id)anEntity connection:(TNStropheConnection)aConnection andRoster:(TNStropheRoster)aRoster
{
    _entity     = anEntity;
    _roster     = aRoster;
    _connection = aConnection;
}

/*! this method register the module for pubsub events
*/
- (void)registerToPubSubEvents
{
    var params = [[CPDictionary alloc] init];

    [params setValue:@"message" forKey:@"name"];
    [params setValue:@"headline" forKey:@"type"];
    [params setValue:{"matchBare": YES} forKey:@"options"];
    [params setValue:"http://jabber.org/protocol/pubsub#event" forKey:@"namespace"];
    // <message from="pubsub.virt-hyperviseur" type="headline" to="controller@virt-hyperviseur" >
    // <event xmlns="http://jabber.org/protocol/pubsub#event">
    // <items node="/archipel/09c206aa-8829-11df-aa46-0016d4e6adab@virt-hyperviseur/events" >
    // <item id="4FEA5748C038E" >
    // <push xmlns="archipel:push:disk" date="2010-07-09 14:15:04.749484" change="created" />
    // </item>
    // </items>
    // </event>
    // <headers xmlns="http://jabber.org/protocol/shim">
    // <header name="Collection" >/archipel/09c206aa-8829-11df-aa46-0016d4e6adab@virt-hyperviseur/events</header>
    // </headers>
    // </message>

    [_registredSelectors addObject:[_connection registerSelector:@selector(onPubSubEvents:) ofObject:self withDict:params]];
}

- (void)onPubSubEvents:(TNStropheStanza)aStanza
{
    CPLog.trace("Raw (not filtered) pubsub event received from " + [aStanza from]);

    var nodeOwner   = [[aStanza firstChildWithName:@"items"] valueForAttribute:@"node"].split("/")[1],
        pushType    = [[aStanza firstChildWithName:@"push"] valueForAttribute:@"xmlns"],
        pushDate    = [[aStanza firstChildWithName:@"push"] valueForAttribute:@"date"],
        pushChange  = [[aStanza firstChildWithName:@"push"] valueForAttribute:@"change"],
        infoDict    = [CPDictionary dictionaryWithObjectsAndKeys:   nodeOwner,  @"owner",
                                                                    pushType,   @"type",
                                                                    pushDate,   @"date",
                                                                    pushChange, @"change"];

    for (var i = 0; i < [_pubsubRegistrar count]; i++)
    {
        var item = [_pubsubRegistrar objectAtIndex:i];

        if (pushType == [item objectForKey:@"type"])
        {
            [self performSelector:[item objectForKey:@"selector"] withObject:infoDict]
        }
    }

    return YES;
}


/*! This method allow the module to register itself to Archipel Push notification (archipel:push namespace)
    @param aSelector: Selector to perform on recieve of archipel:push with given type
    @param aPushType: CPString of the push type that will trigger the selector.
*/
- (void)registerSelector:(SEL)aSelector forPushNotificationType:(CPString)aPushType
{
    if ([_entity class] == TNStropheContact)
    {
        var registrarItem = [CPDictionary dictionary];

        CPLog.info([self class] + @" is registring for push notification of type : " + aPushType);
        [registrarItem setValue:aSelector forKey:@"selector"];
        [registrarItem setValue:aPushType forKey:@"type"];

        [_pubsubRegistrar addObject:registrarItem];
    }
}

/*! This message is sent when module is loaded. It will
    reinitialize the _registredSelectors dictionnary
*/
- (void)willLoad
{
    _animationDuration  = [[CPBundle mainBundle] objectForInfoDictionaryKey:@"TNArchipelAnimationsDuration"]; // if I put this in init, it won't work.
    _registredSelectors = [CPArray array];
    _pubsubRegistrar    = [CPArray array];
    _isActive           = YES;

    [self registerToPubSubEvents];
    [_menuItem setEnabled:YES];
}

/*! This message is sent when module is unloaded. It will remove all push registration,
    all TNStropheConnection registration and all CPNotification subscription
*/
- (void)willUnload
{
    // unregister all selectors
    for (var i = 0; i < [_registredSelectors count]; i++)
    {
        var selector = [_registredSelectors objectAtIndex:i];

        [_connection deleteRegisteredSelector:selector];
    }

    [_pubsubRegistrar removeAllObjects];

    [_menuItem setEnabled:NO];

    // remove all notification observers
    var center  = [CPNotificationCenter defaultCenter];
    [center removeObserver:self];

    _isActive = NO;
}

/*! This message is sent when module will be displayed
*/
- (void)willShow
{
    var defaults = [TNUserDefaults standardUserDefaults];

    if ([defaults boolForKey:@"TNArchipelUseAnimations"])
    {
        var animView    = [CPDictionary dictionaryWithObjectsAndKeys:[self view], CPViewAnimationTargetKey, CPViewAnimationFadeInEffect, CPViewAnimationEffectKey],
            anim        = [[CPViewAnimation alloc] initWithViewAnimations:[animView]];

        [anim setDuration:_animationDuration];
        [anim startAnimation];
    }
    _isVisible = YES;
}

/*! this message is sent when user click on another module.
*/
- (void)willHide
{
    _isVisible = NO;
}

- (void)menuReady
{
    // executed when menu is ready
}

/*! this message simplify the sending and the post-management of TNStropheStanza to the contact
    @param aStanza: TNStropheStanza to send to the contact
    @param aSelector: Selector to perform when contact send answer
*/
- (void)sendStanza:(TNStropheStanza)aStanza andRegisterSelector:(SEL)aSelector
{
    var selectorID = [_entity sendStanza:aStanza andRegisterSelector:aSelector ofObject:self];
    [_registredSelectors addObject:selectorID];
}

/*! this message simplify the sending and the post-management of TNStropheStanza to the contact
    if also allow to define the XMPP uid of the stanza. This is useless in the most of case.
    @param aStanza: TNStropheStanza to send to the contact
    @param aSelector: Selector to perform when contact send answer
    @param anUid: CPString containing the XMPP uid to use.
*/
- (void)sendStanza:(TNStropheStanza)aStanza andRegisterSelector:(SEL)aSelector withSpecificID:(CPString)anUid
{
    var selectorID = [_entity sendStanza:aStanza andRegisterSelector:aSelector ofObject:self withSpecificID:anUid];
    [_registredSelectors addObject:selectorID];
}

/*! this method is called when the user changes the preferences. Implement this method to store
    datas from your eventual viewPreferences
*/
- (void)savePreferences
{
    // executed when use saves preferences
}

/*! this method is called when Archipel displays the preferences window.
    implement this in order to refresh your eventual viewPreferences
*/
- (void)loadPreferences
{
    // executed when archipel displays preferences panel
}


/*! This message allow to display an error when stanza type is error
*/

- (void)handleIqErrorFromStanza:(TNStropheStanza)aStanza
{
    var growl   = [TNGrowlCenter defaultCenter],
        code    = [[aStanza firstChildWithName:@"error"] valueForAttribute:@"code"],
        type    = [[aStanza firstChildWithName:@"error"] valueForAttribute:@"type"];

    if ([aStanza firstChildWithName:@"text"])
    {
        var msg     = [[aStanza firstChildWithName:@"text"] text];

        [growl pushNotificationWithTitle:@"Error (" + code + " / " + type + ")" message:msg icon:TNGrowlIconError];
        CPLog.error(msg);
    }
    else
        CPLog.error(@"Error " + code + " / " + type + ". No message. If 503, it should be allright");

}

- (IBAction)toolbarItemClicked:(id)sender
{

}

@end