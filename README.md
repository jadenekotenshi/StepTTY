# StepTTY for OPENSTEP 4.2

A native local terminal emulator for OPENSTEP 4.2, in C89/Objective-C. Sibling project to
[StepSSH](https://github.com/jadenekotenshi/StepSSH), an SSH-2 client for the same platform --
StepTTY reuses StepSSH's VT100/xterm terminal emulation core (`term/vt.c`, confirmed on real
OPENSTEP 4.2 hardware there) rather than writing one from scratch, and mirrors its architecture
closely (one class owns its window, its terminal view, and the underlying connection -- a pty and
a forked shell here, a network socket and the SSH protocol there).

## What it does

Opens a window running a real login shell (`$SHELL`, or `/bin/csh` if that's unset) over a
pseudo-terminal, the traditional `Terminal.app` role. "New Window" (Cmd-N) opens another; each
window is independent. There is no in-window tab UI yet -- multiple windows is where this starts.

`install`/`pkg`/`dist` and their fat (i386+m68k+sparc) equivalents are all in `Makefile.openstep`
now, built directly on the lessons StepSSH's own packaging saga worked out the hard way (see its
README/Makefile.openstep for that whole story).

## What was verified, and what was not

**Verified on the development Mac**:
- `make test` -- 259 checks, StepSSH's own `term/vt.c` test suite, copied over unmodified (no
  StepSSH-specific coupling in the terminal emulator itself).
- `make pty-smoke` -- drives a *real* `PTYSession` (real pty, real `fork()`/`exec()` of a real
  shell) against real Cocoa on the host: a typed command actually runs and its output reaches the
  screen, a 2000-line burst is received, the pty's winsize is pushed at startup *and* on later
  resize (`TIOCSWINSZ`, `stty size` confirms both), exit is detected via pty EOF/EIO, the exit
  status is read back correctly, and the window/owner-notification lifecycle behaves as designed
  (stays open after the shell exits, notifies the owner exactly once, whenever the window
  actually closes).
- `make check-objc`, `make lint`.

**Confirmed on real OPENSTEP 4.2 hardware**: the app builds, links, launches from both `open` and a
Workspace double-click, and runs a fully usable interactive shell (typing, `ls`, `vi`, `emacs`,
arrow keys, all confirmed). Getting there took several rounds of real-hardware-only fixes, none of
which host testing alone could have caught (the host uses entirely different pty/process-management
APIs, and stubs out the actual PostScript text-drawing calls -- see below):

- Classic BSD pty allocation (`/dev/pty<letter><hexdigit>` master + matching
  `/dev/tty<letter><hexdigit>` slave) works as `open_master_pty()`'s `#ifdef OPENSTEP` branch
  expects.
- `setsid()`, `waitpid()`, `tcgetattr()`/`tcsetattr()`, and `putenv()` are all declared by the
  headers but **not actually linkable symbols** on this system -- genuinely absent, not just
  undeclared, real POSIX.1-1988-and-later additions this BSD-4.3-heritage system predates
  implementing. Replaced with what it actually has instead: `setpgrp(pid, pgrp)` (old 2-arg form) +
  `TIOCNOTTY` on `/dev/tty` instead of `setsid()`; `wait3()` (which, unlike `waitpid()`, can only
  reap "the next available child" -- handled with a shared reap-cache in `app/PTYSession.m` so
  multiple simultaneous windows each get their own child's exit status correctly) instead of
  `waitpid()`; the older BSD `sgtty` ioctl interface (`TIOCGETP`/`TIOCSETP`, `struct sgttyb`,
  `CRMOD`) instead of termios; and extending the `environ` global directly, by hand, instead of
  `putenv()`.
- The pty's winsize must be pushed explicitly at startup (from the child, on the slave fd, before
  `exec`) -- it is not implicitly correct from a window built at the "default" size, since nothing
  had ever changed to trigger the resize path. Without this, anything sizing its output off
  `TIOCGWINSZ` (`ls`'s multi-column layout, most visibly) came out garbled.
- The pty's `CRMOD` flag (sgtty's combined equivalent of termios's `ICRNL`/`ONLCR`) must also be
  set explicitly, for the same reason -- without it, `vt.c`'s spec-correct VT100 handling of a bare
  LF (moves the cursor down a row, but not to column 0; only CR does that) meant output looked
  readable but "staggered," each line starting one column further right than the last.
- Workspace Manager (both `open` and a double-click) silently refuses to launch an app bundle that
  lacks a `__ICON` Mach-O segment -- the exact same failure StepSSH hit before it got its own icon
  (see StepSSH's own history). Fixed the same way: `app/StepTTY.iconheader` + `app/StepTTY.tiff`,
  linked in via `Makefile.openstep`'s `ICONFLAGS`.
- `$TERM` must be set explicitly (the child otherwise just inherits Workspace Manager's own,
  essentially empty, environment) -- and specifically to `vt100`, not `xterm`. `xterm` is what
  StepSSH's own SSH `pty-req` correctly uses for *remote* sessions (a modern remote server's
  terminfo database is basically guaranteed complete), but OPENSTEP's own, much older, *local*
  termcap database turned out not to have a working `xterm` entry for cursor keys specifically --
  confirmed by comparison against OPENSTEP's own native Terminal.app, which already works and uses
  `vt100`, the universal baseline every Unix termcap has had correctly since the 1980s.

`pkg`, `dist`, and their fat (i386+m68k+sparc) equivalents `install-fat`/`pkg-fat`/`dist-fat` are
all confirmed working on real hardware, built on the same `Installer.app/package` mechanics
StepSSH's own packaging saga worked out.

## Building

```sh
make test              # FIRST: the terminal emulator core, on the dev host
make pty-smoke          # a real pty/shell session, end to end, on the dev host
make lint check-objc     # style/portability checks
```

```sh
make -f Makefile.openstep test         # FIRST: the C core on the real compiler
make -f Makefile.openstep              # builds StepTTY.app
make -f Makefile.openstep install      # into /LocalApps
make -f Makefile.openstep pkg          # StepTTY.pkg for Installer.app
make -f Makefile.openstep dist         # StepTTY.pkg, gzipped as StepTTY-<VERSION>-<letter>.tar.gz
make -f Makefile.openstep fat          # StepTTY.app as an i386+m68k+sparc fat binary
make -f Makefile.openstep install-fat  # fat app into /LocalApps
make -f Makefile.openstep pkg-fat      # StepTTY.pkg with the fat build
make -f Makefile.openstep dist-fat     # fat StepTTY.pkg, gzipped as StepTTY-<VERSION>-NIS.tar.gz
```

See `Makefile.openstep`'s own comments for exactly what each one assumes and why, carried over
directly from what StepSSH's own packaging saga established (the real `Installer.app/package`
tool, the plain-text `.info` format, `LongFileNames NO`, `chgrp nogroup`, the `N`/`I`/`S`/`NIS`
`dist` naming) rather than re-derived from nothing.

## Architecture notes

- `term/vt.c`/`term/nsenc.c` -- copied from StepSSH unmodified in spirit (only descriptive
  comments touched, e.g. "SSH channel" -> "pty"): a pure C89, no-I/O VT100/xterm-subset terminal
  emulator core, and NeXTSTEP-charset<->Unicode conversion. Already has 259 passing tests and real
  OPENSTEP 4.2 hardware confirmation from StepSSH's own history.
- `app/TerminalView.m`/`.h` -- copied from StepSSH, with the one StepSSH-specific thing removed
  (feeding keystroke timing into StepSSH's SSH entropy pool, which StepTTY has no use for: no
  crypto here at all).
- `app/UIHelpers.m`/`.h` -- copied from StepSSH, trimmed to the generic widget-factory/string/
  trace helpers; dropped the SFTP-listing-specific formatters (`ui_format_size`/`_time`/`_mode`).
- `app/PTYSession.m`/`.h` -- new. Mirrors `SSHSession` closely on purpose: one class owns its
  window, its `TerminalView`, the underlying connection (a pty + forked shell here), and is the
  window's own close delegate; the same 20&nbsp;ms `NSTimer` poll-loop model StepSSH uses for its
  socket, chosen for the same reason -- proven reliable on real OPENSTEP hardware, where async
  `NSFileHandle` read notifications are not.
- `app/AppController.m`/`.h` -- new, much simpler than StepSSH's (no connection dialog, no key
  generation, no RNG/entropy machinery -- there is no cryptography anywhere in this app). Just
  owns the list of open `PTYSession`s and answers "New Window".

## Startup diagnostics

Workspace throws a launched application's stderr away. `touch ~/.StepTTY.trace` before launching
(from Workspace or `open`) to get the same startup narration `main.m`'s `NSLog` calls print, in a
file instead.
