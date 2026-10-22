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

/* collects what a view sends to its host */
@interface Sink : NSObject { int total; } - (int)total; @end
@implementation Sink
- (void)terminalView:(id)tv sendBytes:(const unsigned char *)bytes length:(int)n { total += n; }
- (void)terminalView:(id)tv resizedToCols:(int)c rows:(int)r { }
- (int)total { return total; }
@end

static void put(TerminalView *tv, const char *s) { [tv writeBytes:(const unsigned char *)s length:(int)strlen(s)]; }

/* pixels of a rectangle of the view, drawn on their own, equal those of the same area of the whole view drawn at once */
static int partial_matches_full(TerminalView *tv, NSRect part)
{
    NSBitmapImageRep *full = [tv bitmapImageRepForCachingDisplayInRect:[tv bounds]];
    NSBitmapImageRep *piece = [tv bitmapImageRepForCachingDisplayInRect:part];
    int x, y, ox, oy;

    [tv cacheDisplayInRect:[tv bounds] toBitmapImageRep:full];
    [tv cacheDisplayInRect:part toBitmapImageRep:piece];
    if ([piece pixelsWide] != (int)part.size.width || [full pixelsWide] != (int)[tv bounds].size.width) return 1;   /* (scaled screen: skip) */
    ox = (int)part.origin.x;
    oy = (int)([tv bounds].size.height - NSMaxY(part));
    for (y = 0; y < [piece pixelsHigh]; y++) {
        for (x = 0; x < [piece pixelsWide]; x++) {
            NSColor *a = [[piece colorAtX:x y:y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
            NSColor *b = [[full colorAtX:ox + x y:oy + y] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

            if (fabs([a redComponent] - [b redComponent]) + fabs([a greenComponent] - [b greenComponent]) +
                fabs([a blueComponent] - [b blueComponent]) > 0.02) return 0;
        }
    }
    return 1;
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

    /* ---- the redraw frame cap, dirty columns and the paste confirmation, on a view of its own ---- */
    {
        TerminalView *v = [[TerminalView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)];
        Sink *sink = [[Sink alloc] init];
        int before, i;
        float full, small;
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400) styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered defer:NO];

        [[w contentView] addSubview:v];
        [v setDelegate:sink];
        [v setMaxFPS:10.0];                                         /* a frame every 100 ms */
        EXPECT([v maxFPS] > 9.9 && [v maxFPS] < 10.1, "the frame cap is settable");
        put(v, "a");
        EXPECT([v flushCount] == 1, "the first output after quiet redraws at once");
        before = [v flushCount];
        for (i = 0; i < 200; i++) put(v, "x");
        [v flushDisplayIfDue];
        EXPECT([v flushCount] == before, "a burst of output inside one frame interval is not redrawn per write");
        spin(0.15);
        [v flushDisplayIfDue];
        EXPECT([v flushCount] == before + 1, "...but once the interval has passed the pending output is redrawn, once");
        [v flushDisplayIfDue];
        EXPECT([v flushCount] == before + 1, "nothing pending, nothing redrawn");
        /* a deferred redraw happens on its own, with nobody ticking */
        put(v, "q");
        put(v, "r");
        before = [v flushCount];
        spin(0.25);
        EXPECT([v flushCount] == before + 1, "output deferred by the cap is redrawn by the view's own timer, without any tick");
        [v setMaxFPS:0.0];
        before = [v flushCount];
        for (i = 0; i < 5; i++) put(v, "y");
        EXPECT([v flushCount] == before + 5, "with the cap off every write redraws");
        [v setMaxFPS:10.0];
        spin(0.15);

        /* dirty columns: one character changing redraws a few cells, not the row */
        put(v, "\033[2J\033[1;1H");
        spin(0.15);
        put(v, "0123456789012345678901234567890123456789012345678901234567890123456789");
        [v flushDisplay];
        full = [v lastFlushArea];
        spin(0.15);
        put(v, "\033[1;40Hz");
        [v flushDisplay];
        small = [v lastFlushArea];
        EXPECT(small > 0.0 && small * 4.0 < full, "one changed character asks AppKit to redraw a few cells, not the whole row");
        put(v, "\033[2J");
        [v flushDisplay];
        EXPECT([v lastFlushArea] >= [v bounds].size.width * [v bounds].size.height * 0.5, "clearing the screen redraws all of it");

        /* a column-limited redraw paints exactly what the full one does (coloured cells, so there is something to compare) */
        put(v, "\033[2J\033[1;1H");
        for (i = 0; i < 6; i++) put(v, "\033[41m  \033[42m  \033[44m  \033[46m  \033[0m AB \033[1;45mCD\033[0m  \n");
        [v flushDisplay];
        {
            NSRect b = [v bounds];
            NSRect piece = NSMakeRect(60.0, b.size.height - 90.0, 130.0, 40.0);

            EXPECT(partial_matches_full(v, piece), "a redraw limited to some columns paints the same pixels as a full redraw there");
            piece = NSMakeRect(3.0, b.size.height - 40.0, 40.0, 30.0);
            EXPECT(partial_matches_full(v, piece), "...also at the left edge");
        }

        /* pasting several lines asks first (unless the shell takes bracketed paste); one line never does */
        {
            NSPasteboard *pb = [NSPasteboard generalPasteboard];

            [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
            [pb setString:@"ls\npwd\n" forType:NSStringPboardType];
            [v setPasteAnswer:0];
            before = [sink total];
            [v paste:nil];
            EXPECT([sink total] == before, "pasting two lines and answering Cancel sends nothing");
            [v setPasteAnswer:1];
            [v paste:nil];
            EXPECT([sink total] > before, "...and answering Paste sends it");
            [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
            [pb setString:@"ls\n" forType:NSStringPboardType];
            [v setPasteAnswer:0];
            before = [sink total];
            [v paste:nil];
            EXPECT([sink total] > before, "a single line (even with its newline) is pasted without asking");
            [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
            [pb setString:@"a\r\nb\r\nc" forType:NSStringPboardType];
            before = [sink total];
            [v paste:nil];
            EXPECT([sink total] == before, "CRLF lines count as lines");
            [v setConfirmsMultilinePaste:NO];
            [v paste:nil];
            EXPECT([sink total] > before, "the confirmation can be switched off");
            [v setConfirmsMultilinePaste:YES];
            [v terminal]->bracketed_paste = 1;
            before = [sink total];
            [v paste:nil];
            EXPECT([sink total] > before, "with bracketed paste on the shell holds the paste back itself, so nothing is asked");
        }
        [w release];
        [sink release];
        [v release];
    }

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

    /* $TERM must reach the shell: "xterm" by default (it was "vt100" until the terminal learned what the ncurses xterm
     * entry relies on; vt100 has no colours).  Arrow keys in OPENSTEP's own vi/emacs, which use its old termcap xterm
     * entry, are the thing to watch on real hardware; the TerminalTERM default switches back. */
    [s terminalView:tv sendBytes:(const unsigned char *)"echo TERM_IS_$TERM\r" length:19];
    EXPECT(wait_for(tv, @"TERM_IS_xterm", 10), "TERM=xterm reaches the shell environment");

    /* A bare LF (no CR) written by the child must still land at column 0 of the next row -- the
     * pty's own line discipline (ONLCR) is responsible for that translation, not vt.c (which
     * treats LF and CR as independent, correct VT100 behaviour), so this only works if the pty was
     * actually configured for it rather than relying on whatever the OS defaults a fresh slave to.
     * -selectedText preserves each row's leading columns verbatim (only trailing blanks are
     * trimmed), so a staggered ALIGN_B (landing at some column > 0 instead of 0) would show up as
     * leading spaces before it rather than immediately after the '\n' -- catching the bug through
     * plain string matching without needing to poke at vt's cursor state directly (which the
     * shell's own next prompt, printed right after, would contaminate anyway). */
    [s terminalView:tv sendBytes:(const unsigned char *)"printf 'ALIGN_A\\nALIGN_B\\nALIGN_C\\n'\r" length:38];
    EXPECT(wait_for(tv, @"ALIGN_C", 10), "bare-LF output reaches the screen");
    EXPECT([screen_text(tv) rangeOfString:@"\nALIGN_B"].length > 0,
           "bare LF from the child returns the cursor to column 0 (ONLCR), not just down a row");

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

    /* the TerminalTERM default overrides it */
    {
        Owner *owner2 = [[[Owner alloc] init] autorelease];
        PTYSession *s2;
        TerminalView *tv2;

        [[NSUserDefaults standardUserDefaults] setObject:@"vt100" forKey:@"TerminalTERM"];
        s2 = [[PTYSession alloc] initWithOwner:owner2];
        EXPECT([s2 start], "a second session starts");
        tv2 = find_terminal([s2 window]);
        [s2 terminalView:tv2 sendBytes:(const unsigned char *)"echo TERM_IS_$TERM\r" length:19];
        EXPECT(wait_for(tv2, @"TERM_IS_vt100", 10), "the TerminalTERM default changes the shell's TERM");
        [s2 shutdown];
        [[s2 window] close];
        [s2 release];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TerminalTERM"];
    }

    printf("pty smoke: %d passed, %d failed\n", pass, fail);
    [pool release];
    return fail ? 1 : 0;
}
