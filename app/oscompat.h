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
#endif

#endif
