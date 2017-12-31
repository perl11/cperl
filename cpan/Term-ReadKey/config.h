/* Using these defines, you can elide anything you know 
   won't work properly */

/* Methods of doing non-blocking reads */

/*#define DONT_USE_SELECT*/
/*#define DONT_USE_POLL*/
/*#define DONT_USE_NODELAY*/


/* Terminal I/O packages */

/*#define DONT_USE_TERMIOS*/
/*#define DONT_USE_TERMIO*/
/*#define DONT_USE_SGTTY*/

/* IOCTLs that can be used for GetTerminalSize */

/*#define DONT_USE_GWINSZ*/
/*#define DONT_USE_GSIZE*/

/* IOCTLs that can be used for SetTerminalSize */

/*#define DONT_USE_SWINSZ*/
/*#define DONT_USE_SSIZE*/

/* This bit is for OS/2 */

#ifdef OS2
#       define I_FCNTL
#       define HAS_FCNTL

#       define O_NODELAY O_NDELAY

#       define DONT_USE_SELECT
#       define DONT_USE_POLL

#       define DONT_USE_TERMIOS
#       define DONT_USE_SGTTY
#       define I_TERMIO
#       define CC_TERMIO

/* This flag should be off in the lflags when we enable termio mode */
#      define TRK_IDEFAULT     IDEFAULT

#       define INCL_SUB
#       define INCL_DOS

#       include <os2.h>
#	include <stdlib.h>

#       define VIOMODE
#else
        /* no os2 */
#endif

/* This bit is for Windows 95/NT */

#ifdef WIN32
#		define DONT_USE_TERMIO
#		define DONT_USE_TERMIOS
#		define DONT_USE_SGTTY
#		define DONT_USE_POLL
#		define DONT_USE_SELECT
#		define DONT_USE_NODELAY
#		define USE_WIN32
#		include <io.h>
#		if defined(_get_osfhandle) && (PERL_VERSION == 4) && (PERL_SUBVERSION < 5)
#			undef _get_osfhandle
#			if defined(_MSC_VER)
#				define level _cnt
#			endif
#		endif
#endif

/* This bit for NeXT */

#ifdef _NEXT_SOURCE
  /* fcntl with O_NDELAY (FNDELAY, actually) is broken on NeXT */
# define DONT_USE_NODELAY
#endif

#if !defined(DONT_USE_NODELAY)
# ifdef HAS_FCNTL
#  define Have_nodelay
#  ifdef I_FCNTL
#   include <fcntl.h>
#  endif
#  ifdef I_SYS_FILE
#   include <sys/file.h>
#  endif
#  ifdef I_UNISTD
#   include <unistd.h>
#  endif

/* If any other headers are needed for fcntl or O_NODELAY, they need to get
   included right here */

#  if !defined(O_NODELAY)
#   if !defined(FNDELAY)
#    undef Have_nodelay
#   else
#    define O_NODELAY FNDELAY
#   endif
#  else
#   define O_NODELAY O_NDELAY
#  endif
# endif
#endif

#if !defined(DONT_USE_SELECT)
# ifdef HAS_SELECT
#  ifdef I_SYS_SELECT
#   include <sys/select.h>
#  endif

/* If any other headers are likely to be needed for select, they need to be
   included right here */

#  define Have_select
# endif
#endif

#if !defined(DONT_USE_POLL)
# ifdef HAS_POLL
#  ifdef HAVE_POLL_H
#   include <poll.h>
#   define Have_poll
#  endif
#  ifdef HAVE_SYS_POLL_H
#   include <sys/poll.h>
#   define Have_poll
#  endif
# endif
#endif

#ifdef DONT_USE_TERMIOS
# ifdef I_TERMIOS
#  undef I_TERMIOS
# endif
#endif
#ifdef DONT_USE_TERMIO
# ifdef I_TERMIO
#  undef I_TERMIO
# endif
#endif
#ifdef DONT_USE_SGTTY
# ifdef I_SGTTY
#  undef I_SGTTY
# endif
#endif

/* Pre-POSIX SVR3 systems sometimes define struct winsize in
   sys/ptem.h.  However, sys/ptem.h needs a type mblk_t (?) which
   is defined in <sys/stream.h>.
   No, Configure (dist3.051) doesn't know how to check for this.
*/
#ifdef I_SYS_STREAM
# include <sys/stream.h>
#endif
#ifdef I_SYS_PTEM
# include <sys/ptem.h>
#endif

#ifdef I_TERMIOS
# include <termios.h>
#else
# ifdef I_TERMIO
#  include <termio.h>
# else
#  ifdef I_SGTTY
#   include <sgtty.h>
#  endif
# endif
#endif

#ifdef I_TERMIOS
# define CC_TERMIOS
#else
# ifdef I_TERMIO
#  define CC_TERMIO
# else
#  ifdef I_SGTTY
#   define CC_SGTTY
#  endif
# endif
#endif

#ifndef TRK_IDEFAULT
/* This flag should be off in the lflags when we enable termio mode */
#      define TRK_IDEFAULT     0
#endif


/* needed for cperl cross-compilation when in CORE */
#ifdef PROBE_MAIN
#include <stdio.h>

static int blockoptions() {
	return	0
#ifdef Have_nodelay
		| 1
#endif
#ifdef Have_poll
		| 2
#endif
#ifdef Have_select
		| 4
#endif
#ifdef USE_WIN32
		| 8
#endif
		;
}

int main () {
  printf("%d", blockoptions());
}
#endif
