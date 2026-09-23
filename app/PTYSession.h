#import "Compat.h"
#import "TerminalView.h"
#include <stddef.h>

/* A growable byte queue, just big enough for PTYSession's own pending-write buffer -- not the
 * general sbuf StepSSH's protocol code needs (SSH wire-format framing), so not copied over. */
typedef struct { unsigned char *p; size_t len, cap; } pty_pending;

enum { PTY_RUNNING = 1, PTY_ENDED };

/* One local shell window: the window and its TerminalView, a pty pair, a forked child running
 * the user's shell on the slave side, and a 20ms poll loop reading the master side into the
 * view -- mirrors StepSSH's SSHSession closely on purpose (one class owns its window, its
 * terminal view, the session logic, and is the window's own close delegate), including the
 * poll-loop model, proven reliable on real OPENSTEP hardware where async NSFileHandle
 * notifications are not. */
@interface PTYSession : NSObject
{
    int            masterFD;
    int            childPID;
    int            state;
    int            exitStatus;
    NSTimer       *timer;
    id             owner;
    pty_pending    pending;            /* bytes not yet accepted by a non-blocking write() */

    NSWindow      *window;
    TerminalView  *termView;
    NSScroller    *scroller;
}
- (id)initWithOwner:(id)anOwner;
/* Builds the window, opens a pty, forks the shell named by $SHELL (falling back to /bin/csh),
 * and starts polling. NO on failure (no free pty, or fork itself failed) -- no window is left
 * open in that case, and the caller reports the failure directly. */
- (BOOL)start;
- (BOOL)isRunning;
- (int)exitStatus;                 /* -1 while still running or if it couldn't be determined */
- (NSWindow *)window;
/* SIGHUPs the child if still running and stops polling; safe to call more than once. */
- (void)shutdown;
@end

/* Informal protocol implemented by whoever creates a PTYSession (AppController). */
@interface NSObject (PTYSessionOwner)
- (void)sessionDidEnd:(PTYSession *)session;
@end
