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

**Not yet built:** an application icon, `.pkg` packaging, a `make install`-friendly release
workflow, anything StepSSH's own packaging saga worked out (see its README/Makefile.openstep for
that whole story) -- StepTTY hasn't needed any of it yet, being this early.

## What was verified, and what was not

**Verified on the development Mac**:
- `make test` -- 259 checks, StepSSH's own `term/vt.c` test suite, copied over unmodified (no
  StepSSH-specific coupling in the terminal emulator itself).
- `make pty-smoke` -- drives a *real* `PTYSession` (real pty, real `fork()`/`exec()` of a real
  shell) against real Cocoa on the host: a typed command actually runs and its output reaches the
  screen, a 2000-line burst is received, window resize reaches the pty (`TIOCSWINSZ`,
  `stty size` confirms it), exit is detected via pty EOF/EIO, the exit status is read back
  correctly via `waitpid()`, and the window/owner-notification lifecycle behaves as designed
  (stays open after the shell exits, notifies the owner exactly once, whenever the window
  actually closes).
- `make check-objc`, `make lint`.

**Confirmed on OPENSTEP 4.2**: nothing yet -- this is a brand new project.

### The one real platform gap already found

Classic BSD pty allocation (`/dev/pty<letter><hexdigit>` master + matching `/dev/tty<letter><hexdigit>`
slave -- the manual scheme every 4.3BSD-heritage system has supported since long before
`openpty()`/`posix_openpt()` existed) is `app/PTYSession.m`'s plan for OPENSTEP itself, chosen
because OPENSTEP's BSD heritage makes it far more likely to work there than the modern
`/dev/ptmx`-based mechanism. It could not be verified end-to-end on this Mac: the classic device
nodes are still visible (`ls /dev/pty*`), but `open()` on any of them now fails unconditionally
with `EAGAIN` -- a confirmed, not guessed, modern-macOS-specific deprecation. `app/PTYSession.m`
uses `#ifdef OPENSTEP` to keep the classic scheme for the real target while the host build (and
`make pty-smoke`) uses `/dev/ptmx` instead, so the rest of the session logic (fork/exec, the poll
loop, backpressure, EOF/exit-status handling) still gets genuinely exercised even though the
actual pty-opening mechanism necessarily differs. **This is the first thing to check when this
gets built on real hardware**: does `open_master_pty()`'s `#ifdef OPENSTEP` branch actually find a
device that opens? If not, report back exactly what `ls /dev/pty*` and the resulting error show.

Also marked `[V]` in `app/PTYSession.m` (verify on OPENSTEP): whether `TIOCSCTTY` exists there for
the child to acquire a controlling terminal, and whether `TIOCSWINSZ` (window resize) exists as
the same ioctl BSD systems have had since long before OPENSTEP too, but not directly confirmed.

## Building

```sh
make test              # FIRST: the terminal emulator core, on the dev host
make pty-smoke          # a real pty/shell session, end to end, on the dev host
make lint check-objc     # style/portability checks
```

```sh
make -f Makefile.openstep test     # FIRST: the C core on the real compiler
make -f Makefile.openstep          # builds StepTTY.app
make -f Makefile.openstep install  # into /LocalApps (see Makefile.openstep; UNVERIFIED)
```

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
