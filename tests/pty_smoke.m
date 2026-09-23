/*
 * pty_smoke.m -- drives a real PTYSession (window, pty, fork, exec a shell) on the host.
 * usage: pty_smoke
 */
#import "Compat.h"
#import "PTYSession.h"
#import "TerminalView.h"
#include <stdio.h>

void PSmoveto(float x, float y) { }
void PSshow(const char *s) { }
@implementation NSFont (OpenStepHostStub)
- (float)widthOfString:(NSString *)s { return [self maximumAdvancement].width; }
@end

@interface Owner : NSObject { int ended; } - (int)ended; @end
@implementation Owner
- (void)sessionDidEnd:(PTYSession *)s { ended = 1; }
- (int)ended { return ended; }
@end

static TerminalView *find_terminal(NSWindow *w)
{
    NSEnumerator *e = [[[w contentView] subviews] objectEnumerator];
    id v;
    while ((v = [e nextObject])) if ([v isKindOfClass:[TerminalView class]]) return v;
    return nil;
}

static NSString *screen_text(TerminalView *tv)
{
    [tv selectAll:nil];
    return [tv selectedText];
}

static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static int wait_for(TerminalView *tv, NSString *needle, double timeout)
{
    double waited = 0;
    while (waited < timeout) {
        if ([screen_text(tv) rangeOfString:needle].length > 0) return 1;
        spin(0.05);
        waited += 0.05;
    }
    return 0;
}

static int pass, fail;
#define EXPECT(cond, what) do { if (cond) { pass++; printf("  ok   %s\n", what); } else { fail++; printf("  FAIL %s\n", what); } } while (0)

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Owner *owner = [[Owner alloc] init];
    PTYSession *s = [[PTYSession alloc] initWithOwner:owner];
    TerminalView *tv;

    [NSApplication sharedApplication];
    EXPECT([s start], "starting a session opens a pty and forks the shell");
    EXPECT([s isRunning], "the session reports running right after start");
    EXPECT([s window] != nil, "start built a window");

    tv = find_terminal([s window]);
    EXPECT(tv != nil, "the window has a terminal view");
    if (!tv) return 1;

    /* the pty's winsize must be pushed at startup, not just on a later resize -- otherwise it sits
     * at 0x0 until the user manually resizes the window, which is what made `ls` and anything else
     * that sizes its output off TIOCGWINSZ come out garbled */
    [s terminalView:tv sendBytes:(const unsigned char *)"stty size\r" length:10];
    {
        vt *t = [tv terminal];
        char want[32];
        sprintf(want, "%d %d", t->rows, t->cols);
        EXPECT(wait_for(tv, [NSString stringWithCString:want], 10), "pty winsize is set at startup, before any manual resize");
    }

    [s terminalView:tv sendBytes:(const unsigned char *)"echo SMOKE_$((3*4))\r" length:20];
    EXPECT(wait_for(tv, @"SMOKE_12", 10), "a typed command runs in the real shell and its output reaches the screen");

    /* a burst bigger than one pty read/write, to exercise the pending-write path a little */
    [s terminalView:tv sendBytes:(const unsigned char *)"seq 1 2000\r" length:11];
    EXPECT(wait_for(tv, @"2000", 15), "a burst of output (2000 lines) is received");

    /* resize is forwarded to the pty (TIOCSWINSZ) */
    [[s window] setContentSize:NSMakeSize(700, 300)];
    spin(0.5);
    [s terminalView:tv sendBytes:(const unsigned char *)"stty size\r" length:10];
    {
        vt *t = [tv terminal];
        char want[32];
        sprintf(want, "%d %d", t->rows, t->cols);
        EXPECT(wait_for(tv, [NSString stringWithCString:want], 10), "window resize reaches the pty (stty size matches)");
    }

    [s terminalView:tv sendBytes:(const unsigned char *)"exit\r" length:5];
    { double w = 0; while ([s isRunning] && w < 10) { spin(0.05); w += 0.05; } }
    EXPECT(![s isRunning], "exiting the shell is noticed (pty EOF/EIO detected)");
    EXPECT([s exitStatus] == 0, "the shell's own exit status (0, for plain `exit`) is reported correctly");
    EXPECT(![owner ended], "the owner is not notified yet -- the window stays open to show final output");

    [[s window] close];
    spin(0.2);
    EXPECT([owner ended], "closing the window (even after the shell already exited) notifies the owner exactly then");

    printf("pty smoke: %d passed, %d failed\n", pass, fail);
    [pool release];
    return fail ? 1 : 0;
}
