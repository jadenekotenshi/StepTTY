#import "Compat.h"
#import "PTYSession.h"

/* Owns every open terminal window. One PTYSession (one forked shell) per window for now --
 * "New Window" (Cmd-N) opens another; there is no in-window-tab UI yet. */
@interface AppController : NSObject
{
    NSMutableArray *sessions;          /* PTYSession* */
}
- (void)buildMenu;
- (void)newWindow:(id)sender;
- (void)sessionDidEnd:(PTYSession *)session;
@end
