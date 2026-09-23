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
 * build, same as StepSSH's own oscompat.h does for this exact class of gap. waitpid() is NOT
 * declared here yet -- see this header's own note further down about why. */
extern int open();                                  /* varying arg count (2 or 3, with O_CREAT) */
extern int fork(void);
extern int close(int fd);
extern int setsid(void);
extern int dup2(int oldfd, int newfd);
extern int execl();                                  /* NULL-terminated varargs */
extern int fcntl();                                  /* third arg's type varies by cmd */
extern int read(int fd, void *buf, int n);
extern int kill(int pid, int sig);
extern int write(int fd, const void *buf, int n);
extern int ioctl();                                  /* third arg's type varies by request */

/* waitpid()/WIFEXITED()/WIFSIGNALED() itself: real hardware shows WIFEXITED/WIFSIGNALED already
 * exist as macros here, but ones that access member fields (seen: "w_S"/"w_T") on their argument
 * -- the classic pre-POSIX BSD `union wait` convention, not a plain int, and unlike everything
 * above, guessing the exact member layout wrong here would not just be noisy but actually wrong.
 * Not fixed yet: waiting on the real <sys/wait.h> before declaring anything, the same discipline
 * StepSSH's own oscompat.h used for every gap like this (read the real header, don't guess a
 * struct/union's internal shape). */
#endif

#endif
