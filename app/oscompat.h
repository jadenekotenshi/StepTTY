/*
 * oscompat.h -- prototypes (and a couple of missing types) that OPENSTEP 4.2's system headers
 * leave out. Same idea, same reasoning, as StepSSH's own core/oscompat.h -- only entries actually
 * reported by the real compiler are listed here: redeclaring one the headers DO declare could
 * cause a "conflicting types" error.
 *
 * Include this AFTER every system header in a file. It is empty unless the OPENSTEP build
 * (-DOPENSTEP) is in effect, so host builds are unaffected.
 */
#ifndef TTY_OSCOMPAT_H
#define TTY_OSCOMPAT_H

#ifdef OPENSTEP
#include <sys/types.h>
/* No pid_t at all despite <sys/types.h>: POSIX.1-1990 has it, but OPENSTEP 4.2 predates even that
 * catching up in its own headers (the exact same class of gap as ssize_t in StepSSH's own
 * oscompat.h). int matches fork()/getpid()'s actual i386 ABI return width here. */
typedef int pid_t;

/* Real hardware: <fcntl.h>/<unistd.h>/<signal.h> here don't declare these either, despite being
 * included -- all genuinely int-returning (or, for open/execl/fcntl/ioctl, taking a varying
 * argument list old-style unprototyped declarations sidestep rather than getting wrong), so the
 * usual implicit-int assumption these warnings describe is harmless; declared anyway for a clean
 * build, same as StepSSH's own oscompat.h does for this exact class of gap. */
extern int open();                                  /* varying arg count (2 or 3, with O_CREAT) */
extern int fork(void);
extern int close(int fd);
extern int getpid(void);
extern int dup2(int oldfd, int newfd);
extern int execl();                                  /* NULL-terminated varargs */
extern int fcntl();                                  /* third arg's type varies by cmd */
extern int read(int fd, void *buf, int n);
extern int kill(int pid, int sig);
extern int write(int fd, const void *buf, int n);
extern int ioctl();                                  /* third arg's type varies by request */

/* setsid()/waitpid() *declared* fine (once pid_t existed -- see above) but real hardware's own
 * linker reports both as undefined symbols: genuinely absent, not just undeclared, on this old a
 * BSD-heritage system -- POSIX.1-1988 additions OPENSTEP 4.2 predates actually implementing, even
 * though its headers preemptively declare them. The older BSD equivalents this system does have
 * (confirmed absent from a real /usr/shlib/*.shlib symbol search for the POSIX names first, not
 * guessed): setpgrp()+TIOCNOTTY instead of setsid() (see PTYSession.m's own use of both), and
 * wait3() instead of waitpid() (see PTYSession.m's reap_pending()/reap_specific_child() -- not
 * declared here since its signature needs `union wait`, from the SAME _NEXT_SOURCE-gated part of
 * <sys/wait.h> as wait3() itself, not something this general header should also pull in). */
extern int setpgrp(int pid, int pgrp);
#endif

#endif
