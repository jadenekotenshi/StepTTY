#import "PTYSession.h"
#include <string.h>
#include <stdlib.h>              /* posix_openpt/grantpt/unlockpt/ptsname on the host build */
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
/* OPENSTEP 4.2's <sys/wait.h> is dual-mode, gated by _POSIX_SOURCE (confirmed by reading the real
 * header, not guessed): without it, WIFEXITED/WIFSIGNALED are defined against a `union wait`, not
 * a plain int, and WEXITSTATUS/WTERMSIG/waitpid() aren't declared at all -- only the union-based
 * wait()/wait3() are. With it, everything is the familiar plain-int POSIX form this file already
 * assumes. Defined only around this one include, matching stepscp.c's own established pattern for
 * the exact same kind of gate on <dirent.h>, since a feature-test macro can in principle change
 * what other headers expose too. */
#define _POSIX_SOURCE 1
#include <sys/wait.h>
#undef _POSIX_SOURCE
#include <sys/ioctl.h>
#include "oscompat.h"

#ifndef O_NONBLOCK
#define O_NONBLOCK O_NDELAY
#endif
#ifndef EWOULDBLOCK
#define EWOULDBLOCK EAGAIN
#endif

#define TICK_SECONDS 0.02

/* gcc 2.7.2 does not look ahead within an @implementation, so anything called
 * before its definition must be declared here. */
@interface PTYSession (Private)
- (void)buildWindow;
- (void)tick:(NSTimer *)t;
- (void)childEnded;
- (void)flushPending;
@end

#ifdef OPENSTEP
/* Classic BSD pty device pairs: /dev/pty<letter><hexdigit> (master), /dev/tty<letter><hexdigit>
 * (matching slave) -- the manual scheme every 4.3BSD-heritage system has supported since long
 * before openpty()/posix_openpt() existed, so the one most likely to actually be present on
 * OPENSTEP 4.2 itself. UNVERIFIED on real OPENSTEP hardware: the device nodes are still visible
 * on a modern Mac (`ls /dev/pty*`), but opening any of them now fails there unconditionally with
 * EAGAIN -- confirmed directly, not guessed -- so that could only be checked here for "does the
 * file exist", not "does open() actually work", which is why the host build below uses a
 * different mechanism instead of standing in for this one. If OPENSTEP doesn't have these
 * devices, or open() fails there too, report back exactly what happened. */
static int open_master_pty(char *slave_out)
{
    static const char letters[] = "pqrstuvw";
    static const char digits[] = "0123456789abcdef";
    int li, di;

    for (li = 0; letters[li]; li++) {
        for (di = 0; digits[di]; di++) {
            char master[32];
            int fd;
            sprintf(master, "/dev/pty%c%c", letters[li], digits[di]);
            fd = open(master, O_RDWR);
            if (fd >= 0) {
                sprintf(slave_out, "/dev/tty%c%c", letters[li], digits[di]);
                return fd;
            }
        }
    }
    return -1;
}
#else
/* Host testing only -- NOT what Makefile.openstep builds; see the #ifdef OPENSTEP branch above
 * for that. Modern macOS/Linux want /dev/ptmx + posix_openpt()/grantpt()/unlockpt()/ptsname()
 * instead: confirmed directly that the classic /dev/ptyXX nodes above are only cosmetically
 * present here (open() on any of them fails with EAGAIN, unconditionally), so they cannot stand
 * in for the real thing in a host test -- this lets the rest of PTYSession (fork/exec, the poll
 * loop, backpressure, EOF/exit-status handling) still be genuinely exercised against a real
 * forked shell on the dev machine, even though the actual pty-opening mechanism differs. */
static int open_master_pty(char *slave_out)
{
    int fd = posix_openpt(O_RDWR | O_NOCTTY);
    char *name;
    if (fd < 0) return -1;
    if (grantpt(fd) != 0 || unlockpt(fd) != 0) { close(fd); return -1; }
    name = ptsname(fd);
    if (!name) { close(fd); return -1; }
    strcpy(slave_out, name);
    return fd;
}
#endif

@implementation PTYSession

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (!self) return nil;
    owner = anOwner;
    masterFD = -1;
    exitStatus = -1;
    return self;
}

- (void)dealloc
{
    [self shutdown];
    if (pending.p) free(pending.p);
    [window release]; [termView release]; [scroller release];
    [super dealloc];
}

- (NSWindow *)window { return window; }
- (BOOL)isRunning { return state == PTY_RUNNING; }
- (int)exitStatus { return exitStatus; }

/* ---------------------------------------------------------------- */
/* window (mirrors SSHSession's buildWindow closely)                */

- (void)buildWindow
{
    static float offset = 0.0;
    NSSize cs;
    float sw = [NSScroller scrollerWidth];
    NSRect content;
    NSView *container;
    NSRect scr = [[NSScreen mainScreen] frame];

    termView = [[TerminalView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    cs = [termView contentSizeForCols:80 rows:24];
    content = NSMakeRect(0, 0, cs.width + sw, cs.height);

    window = [[NSWindow alloc] initWithContentRect:content
                                         styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                                                    NSMiniaturizableWindowMask | NSResizableWindowMask)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id)self];
    [window setMinSize:NSMakeSize(200, 100)];
    if ([window respondsToSelector:@selector(setResizeIncrements:)])      /* snap to whole cells */
        [window setResizeIncrements:NSMakeSize(1, 1)];

    container = [[NSView alloc] initWithFrame:content];
    [termView setFrame:NSMakeRect(0, 0, cs.width, cs.height)];
    [termView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    scroller = [[NSScroller alloc] initWithFrame:NSMakeRect(cs.width, 0, sw, cs.height)];
    [scroller setAutoresizingMask:(NSViewHeightSizable | NSViewMinXMargin)];
    [container addSubview:termView];
    [container addSubview:scroller];
    [window setContentView:container];
    [container release];

    [termView setDelegate:self];
    [termView setScroller:scroller];
    [window setTitle:@"Shell"];
    [window setFrameTopLeftPoint:NSMakePoint(scr.origin.x + 60 + offset, NSMaxY(scr) - 40 - offset)];
    offset += 24.0;
    if (offset > 240.0) offset = 0.0;
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:termView];
}

- (void)refreshTitle
{
    vt *t = [termView terminal];
    if (t->title_changed) {
        t->title_changed = 0;
        [window setTitle:[NSString stringWithCString:t->title]];
    }
}

/* ---------------------------------------------------------------- */
/* starting the shell                                                */

- (BOOL)start
{
    char slaveName[64];
    const char *shell;
    int flags;
    pid_t pid;

    [self buildWindow];

    masterFD = open_master_pty(slaveName);
    if (masterFD < 0) { [window close]; return NO; }

    pid = fork();
    if (pid < 0) { close(masterFD); masterFD = -1; [window close]; return NO; }

    if (pid == 0) {
        /* ---- child: becomes the shell, on the slave side of the pty ---- */
        int slaveFD;
        const char *base;
        char arg0[64];

        setsid();
        slaveFD = open(slaveName, O_RDWR);
        if (slaveFD < 0) _exit(127);
#ifdef TIOCSCTTY
        ioctl(slaveFD, TIOCSCTTY, 0);       /* [V] acquire it as our controlling tty, if this ioctl exists here */
#endif
        close(masterFD);
        dup2(slaveFD, 0); dup2(slaveFD, 1); dup2(slaveFD, 2);
        if (slaveFD > 2) close(slaveFD);

        shell = getenv("SHELL");
        if (!shell || !*shell) shell = "/bin/csh";           /* OPENSTEP's traditional default shell */
        base = strrchr(shell, '/');
        base = base ? base + 1 : shell;
        arg0[0] = '-';                                        /* leading '-': a login shell, like a real */
        strncpy(arg0 + 1, base, sizeof(arg0) - 2);            /* terminal, so .login/.profile get sourced */
        arg0[sizeof(arg0) - 1] = '\0';
        execl(shell, arg0, (char *)NULL);
        _exit(127);                                            /* exec failed */
    }

    /* ---- parent ---- */
    childPID = pid;
    flags = fcntl(masterFD, F_GETFL, 0);
    fcntl(masterFD, F_SETFL, flags | O_NONBLOCK);
    state = PTY_RUNNING;
    timer = [[NSTimer scheduledTimerWithTimeInterval:TICK_SECONDS target:self
                                            selector:@selector(tick:) userInfo:nil repeats:YES] retain];
    return YES;
}

- (void)tick:(NSTimer *)t
{
    unsigned char buf[16384];
    int n;

    if (state != PTY_RUNNING) return;
    [self flushPending];
    n = read(masterFD, buf, sizeof(buf));
    if (n > 0) {
        [termView writeBytes:buf length:n];
        [self refreshTitle];
    } else if (n == 0 || (n < 0 && errno == EIO)) {           /* EIO: the classic "far end hung up" for a pty */
        [self childEnded];
    } else if (n < 0 && errno != EWOULDBLOCK && errno != EAGAIN && errno != EINTR) {
        [self childEnded];
    }
}

- (void)childEnded
{
    int status = -1, wpid;
    if (state != PTY_RUNNING) return;
    state = PTY_ENDED;
    [timer invalidate];
    [timer release];
    timer = nil;
    wpid = waitpid(childPID, &status, 0);
    if (wpid == childPID) {
        exitStatus = WIFEXITED(status) ? WEXITSTATUS(status)
                   : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
    }
    if (masterFD >= 0) { close(masterFD); masterFD = -1; }
    /* The window stays open (showing final scrollback) until the user closes it themselves --
     * windowWillClose: is the only place that notifies owner, so it happens exactly once whether
     * the shell exited first or the user just closed a still-running one. */
    [window setTitle:[NSString stringWithFormat:@"Shell (exit status %d)", exitStatus]];
}

- (void)shutdown
{
    if (state != PTY_RUNNING) return;
    state = PTY_ENDED;
    [timer invalidate];
    [timer release];
    timer = nil;
    if (childPID > 0) kill(childPID, SIGHUP);
    if (masterFD >= 0) { close(masterFD); masterFD = -1; }
}

/* ---------------------------------------------------------------- */
/* pending writes: a non-blocking pty write can come back short (or EWOULDBLOCK) for a large
 * paste; queued here and retried each tick rather than silently dropped.                     */

- (void)flushPending
{
    int w;
    if (pending.len == 0 || masterFD < 0) return;
    w = write(masterFD, pending.p, pending.len);
    if (w > 0) {
        memmove(pending.p, pending.p + w, pending.len - (size_t)w);
        pending.len -= (size_t)w;
    }
}

- (void)queueBytes:(const unsigned char *)bytes length:(int)n
{
    size_t need = pending.len + (size_t)n;
    if (need > pending.cap) {
        size_t newcap = pending.cap ? pending.cap * 2 : 4096;
        unsigned char *np;
        while (newcap < need) newcap *= 2;
        np = (unsigned char *)realloc(pending.p, newcap);
        if (!np) return;                                       /* out of memory: drop rather than crash */
        pending.p = np;
        pending.cap = newcap;
    }
    memcpy(pending.p + pending.len, bytes, (size_t)n);
    pending.len += (size_t)n;
}

/* ---------------------------------------------------------------- */
/* TerminalView delegate                                            */

- (void)terminalView:(id)tv sendBytes:(const unsigned char *)bytes length:(int)n
{
    if (state != PTY_RUNNING) return;
    if (pending.len) { [self queueBytes:bytes length:n]; return; }
    {
        int w = write(masterFD, bytes, (size_t)n);
        if (w < 0) w = 0;
        if (w < n) [self queueBytes:bytes + w length:n - w];
    }
}

- (void)terminalView:(id)tv resizedToCols:(int)cols rows:(int)rows
{
    struct winsize ws;
    if (state != PTY_RUNNING) return;
    memset(&ws, 0, sizeof(ws));
    ws.ws_col = (unsigned short)cols;
    ws.ws_row = (unsigned short)rows;
    ioctl(masterFD, TIOCSWINSZ, &ws);                          /* [V] confirm this ioctl exists on OPENSTEP */
}

/* ---------------------------------------------------------------- */
/* window delegate                                                  */

- (void)windowWillClose:(NSNotification *)notification
{
    [self shutdown];
    [window setDelegate:nil];
    [owner sessionDidEnd:self];
}

- (void)windowDidResize:(NSNotification *)notification
{
    [termView fitToFrame];
}

@end
