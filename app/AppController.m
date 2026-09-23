#import "AppController.h"
#import "UIHelpers.h"

@implementation AppController

- (id)init
{
    self = [super init];
    if (!self) return nil;
    sessions = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    [sessions release];
    [super dealloc];
}

/* ---------------------------------------------------------------- */
/* menus                                                            */

- (void)addItem:(NSString *)title action:(SEL)action key:(NSString *)key
         target:(id)target toMenu:(NSMenu *)menu
{
    id item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    if (target) [item setTarget:target];
}

- (NSMenu *)submenuNamed:(NSString *)title inMenu:(NSMenu *)parent
{
    NSMenu *sub = [[NSMenu alloc] initWithTitle:title];
    id item = [parent addItemWithTitle:title action:NULL keyEquivalent:@""];
    [parent setSubmenu:sub forItem:item];
    return [sub autorelease];
}

- (void)buildMenu
{
    NSMenu *main = [[[NSMenu alloc] initWithTitle:@"StepTTY"] autorelease];
    NSMenu *m;

    m = [self submenuNamed:@"Shell" inMenu:main];
    [self addItem:@"New Window" action:@selector(newWindow:) key:@"n" target:self toMenu:m];
    [self addItem:@"Close Window" action:@selector(performClose:) key:@"w" target:nil toMenu:m];

    m = [self submenuNamed:@"Edit" inMenu:main];
    [self addItem:@"Copy" action:@selector(copy:) key:@"c" target:nil toMenu:m];
    [self addItem:@"Paste" action:@selector(paste:) key:@"v" target:nil toMenu:m];
    [self addItem:@"Select All" action:@selector(selectAll:) key:@"a" target:nil toMenu:m];
    [self addItem:@"Clear Scrollback" action:@selector(clearScrollback:) key:@"k" target:nil toMenu:m];

    m = [self submenuNamed:@"Windows" inMenu:main];
    [self addItem:@"Arrange in Front" action:@selector(arrangeInFront:) key:@"" target:nil toMenu:m];
    [self addItem:@"Miniaturize Window" action:@selector(performMiniaturize:) key:@"m" target:nil toMenu:m];
    [NSApp setWindowsMenu:m];

    m = [self submenuNamed:@"Services" inMenu:main];
    [NSApp setServicesMenu:m];

    [self addItem:@"Hide" action:@selector(hide:) key:@"h" target:NSApp toMenu:main];
    [self addItem:@"Quit" action:@selector(terminate:) key:@"q" target:NSApp toMenu:main];

    [NSApp setMainMenu:main];
}

/* ---------------------------------------------------------------- */
/* startup                                                          */

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSLog(@"StepTTY: applicationDidFinishLaunching");
    SSTrace("applicationDidFinishLaunching");
    [self newWindow:nil];
}

/* ---------------------------------------------------------------- */
/* sessions                                                         */

- (void)newWindow:(id)sender
{
    PTYSession *s = [[PTYSession alloc] initWithOwner:self];
    if (![s start]) {
        NSRunAlertPanel(@"New Window", @"Could not open a pty (no free device, or fork failed).",
                        @"OK", nil, nil);
        [s release];
        return;
    }
    [sessions addObject:s];
    [s release];
}

- (void)sessionDidEnd:(PTYSession *)session
{
    [[session retain] autorelease];                     /* it is still on the stack in windowWillClose: */
    [sessions removeObject:session];
}

@end
