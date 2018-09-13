/* -*- mode:C c-basic-offset:4 -*- */

#define PERL_NO_GET_CONTEXT     /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#define InputStream PerlIO *

/*******************************************************************

 Copyright (C) 1994,1995,1996,1997 Kenneth Albanowski. Unlimited
 distribution and/or modification is allowed as long as this copyright
 notice remains intact.

 Written by Kenneth Albanowski on Thu Oct  6 11:42:20 EDT 1994
 Contact at kjahds@kjahds.com or CIS:70705,126

 Maintained by Jonathan Stowe <jns@gellyfish.co.uk>
 and now Reini Urban for cperl

*******************************************************************/

/***

 Things to do:

	Make sure the GetSpeed function is doing it's best to separate ispeed
	from ospeed.
	
	Separate the stty stuff from ReadMode, so that stty -a can be easily
	used, among other things.

***/

#include "config.h"

/* 5.6.2 has it already */
#ifndef StructCopy
#  define StructCopy(s,d,t) Copy(s,d,1,t)
#endif

/* Fix up the disappearance of the '_' macro in Perl 5.7.2 */

#ifndef _
#  ifdef CAN_PROTOTYPE
#    define _(args) args
#  else
#    define _(args) ()
#  endif
#endif

#define DisableFlush (1) /* Should flushing mode changes be enabled?
		            I think not for now. */
#define STDIN PerlIO_stdin()

#include "cchars.h"

STATIC int GetTermSizeVIO _((pTHX_ PerlIO * file,
                             int * width, int * height, 
                             int * xpix, int * ypix));

STATIC int GetTermSizeGWINSZ _((pTHX_ PerlIO * file,
                                int * width, int * height, 
                                int * xpix, int * ypix));

STATIC int GetTermSizeGSIZE _((pTHX_ PerlIO * file,
                               int * width, int * height, 
                               int * xpix, int * ypix));

STATIC int GetTermSizeWin32 _((pTHX_ PerlIO * file,
                               int * width, int * height,
                               int * xpix, int * ypix));

STATIC int SetTerminalSize _((pTHX_ PerlIO * file,
                              int width, int height, 
                              int xpix, int ypix));

STATIC void ReadMode _((pTHX_ PerlIO * file,int mode));

STATIC int pollfile _((pTHX_ PerlIO * file, double delay));

STATIC int setnodelay _((pTHX_ PerlIO * file, int mode));

STATIC int selectfile _((pTHX_ PerlIO * file, double delay));

#ifdef WIN32
STATIC int Win32PeekChar _((pTHX_ PerlIO * file, U32 delay, char * key));
#endif

STATIC int getspeed _((pTHX_ PerlIO * file, I32 *in, I32 * out ));


int GetTermSizeVIO(pTHX_ PerlIO *file,int *width,int *height,int *xpix,int *ypix)
{
#ifdef VIOMODE
/* _scrsize better than VioGetMode: Solaris, OS/2 */
# if 0
    int handle = PerlIO_fileno(file);

    static VIOMODEINFO *modeinfo = NULL;

    if (modeinfo == NULL)
        modeinfo = (VIOMODEINFO *)malloc(sizeof(VIOMODEINFO));

    VioGetMode(modeinfo,0);
    *height = modeinfo->row ? modeinfo->row : 25;
    *width  = modeinfo->col ? modeinfo->col : 80;
# else
    int buf[2];
    PERL_UNUSED_ARG(file);

    _scrsize(&buf[0]);

    *width  = buf[0];
    *height = buf[1];
# endif
    *xpix = *ypix = 0;
    return 0;
#else /* VIOMODE */
    PERL_UNUSED_ARG(file);
    PERL_UNUSED_ARG(width);
    PERL_UNUSED_ARG(height);
    PERL_UNUSED_ARG(xpix);
    PERL_UNUSED_ARG(ypix);
    croak("TermSizeVIO is not implemented on this architecture");
    return 0;
#endif
}

int GetTermSizeGWINSZ(pTHX_ PerlIO *file,int *width,int *height,int *xpix,int *ypix)
{
#if defined(TIOCGWINSZ) && !defined(DONT_USE_GWINSZ)
    int handle = PerlIO_fileno(file);
    struct winsize w;
    
    if (ioctl (handle, TIOCGWINSZ, &w) == 0) {
        *width  = w.ws_col;
        *height = w.ws_row; 
        *xpix = w.ws_xpixel;
        *ypix = w.ws_ypixel;
        return 0;
    }
    else {
        return -1; /* failure */
    }
#else
    PERL_UNUSED_ARG(file);
    PERL_UNUSED_ARG(width);
    PERL_UNUSED_ARG(height);
    PERL_UNUSED_ARG(xpix);
    PERL_UNUSED_ARG(ypix);
    croak("TermSizeGWINSZ is not implemented on this architecture");
    return 0;
#endif
}

int GetTermSizeGSIZE(pTHX_ PerlIO *file,int *width,int *height,int *xpix,int *ypix)
{
#if (!defined(TIOCGWINSZ) || defined(DONT_USE_GWINSZ)) && (defined(TIOCGSIZE) && !defined(DONT_USE_GSIZE))
    int handle = PerlIO_fileno(file);

    struct ttysize w;
        
    if (ioctl (handle, TIOCGSIZE, &w) == 0) {
        *width  = w.ts_cols;
        *height = w.ts_lines; 
        *xpix = 0/*w.ts_xxx*/;
        *ypix = 0/*w.ts_yyy*/;
        return 0;
    }
    else {
        return -1; /* failure */
    }
#else
    PERL_UNUSED_ARG(file);
    PERL_UNUSED_ARG(width);
    PERL_UNUSED_ARG(height);
    PERL_UNUSED_ARG(xpix);
    PERL_UNUSED_ARG(ypix);
    croak("TermSizeGSIZE is not implemented on this architecture");
    return 0;
#endif
}

int GetTermSizeWin32(pTHX_ PerlIO *file,int *width,int *height,int *xpix,int *ypix)
{
#ifdef USE_WIN32
    int handle = PerlIO_fileno(file);
    HANDLE whnd = (HANDLE)_get_osfhandle(handle);
    CONSOLE_SCREEN_BUFFER_INFO info;

    if (GetConsoleScreenBufferInfo(whnd, &info)) {
        /* Logic: return maximum possible screen width, but return
           only currently selected height */
        if (width)
            *width = info.dwMaximumWindowSize.X; 
        /*info.srWindow.Right - info.srWindow.Left;*/
        if (height)
            *height = info.srWindow.Bottom - info.srWindow.Top;
        if (xpix)
            *xpix = 0;
        if (ypix)
            *ypix = 0;
        return 0;
    } else
        return -1;
#else
    PERL_UNUSED_ARG(file);
    PERL_UNUSED_ARG(width);
    PERL_UNUSED_ARG(height);
    PERL_UNUSED_ARG(xpix);
    PERL_UNUSED_ARG(ypix);
    croak("TermSizeWin32 is not implemented on this architecture");
    return 0;
#endif /* USE_WIN32 */
}


STATIC int termsizeoptions() {
    return	0
#ifdef VIOMODE
		| 1
#endif
#if defined(TIOCGWINSZ) && !defined(DONT_USE_GWINSZ)
		| 2
#endif
#if defined(TIOCGSIZE) && !defined(DONT_USE_GSIZE)
		| 4
#endif
#if defined(USE_WIN32)
		| 8
#endif
		;
}


int SetTerminalSize(pTHX_ PerlIO *file,int width,int height,int xpix,int ypix)
{
#ifdef VIOMODE
    return -1;
#else
    int handle = PerlIO_fileno(file);

# if defined(TIOCSWINSZ) && !defined(DONT_USE_SWINSZ)
    char buffer[10];
    struct winsize w;

    w.ws_col = width;
    w.ws_row = height;
    w.ws_xpixel = xpix;
    w.ws_ypixel = ypix;
    if (ioctl (handle, TIOCSWINSZ, &w) == 0) {
        sprintf(buffer,"%d",width); /* Be polite to our children */
        my_setenv("COLUMNS",buffer);
        sprintf(buffer,"%d",height);
        my_setenv("LINES",buffer);
        return 0;
    }
    else {
        croak("TIOCSWINSZ ioctl call to set terminal size failed: %s",Strerror(errno));
        return -1;
    }
# else
#  if defined(TIOCSSIZE) && !defined(DONT_USE_SSIZE)
    char buffer[10];
    struct ttysize w;

    w.ts_lines = height;
    w.ts_cols = width;
    w.ts_xxx = xpix;
    w.ts_yyy = ypix;
    if (ioctl (handle, TIOCSSIZE, &w) == 0) {
        sprintf(buffer,"%d",width);
        my_setenv("COLUMNS",buffer);
        sprintf(buffer,"%d",height);
        my_setenv("LINES",buffer);
        return 0;
    }
    else {
        croak("TIOCSSIZE ioctl call to set terminal size failed: %s",Strerror(errno));
        return -1;
    }
#  else
    /* Should we could do this and then said we succeeded?
       sprintf(buffer,"%d",width)   
       my_setenv("COLUMNS",buffer)   
       sprintf(buffer,"%d",height);
       my_setenv("LINES",buffer); */

    return -1; /* Fail */
#  endif
# endif
# endif
}

STATIC const I32 terminal_speeds[] = {
#ifdef B50
	50, B50,
#endif
#ifdef B75
	75, B75,
#endif
#ifdef B110
	110, B110,
#endif
#ifdef B134
	134, B134,
#endif
#ifdef B150
	150, B150,
#endif
#ifdef B200
	200, B200,
#endif
#ifdef B300
	300, B300,
#endif
#ifdef B600
	600, B600,
#endif
#ifdef B1200
	1200, B1200,
#endif
#ifdef B1800
	1800, B1800,
#endif
#ifdef B2400
	2400, B2400,
#endif
#ifdef B4800
	4800, B4800,
#endif
#ifdef B9600
	9600, B9600,
#endif
#ifdef B19200
	19200, B19200,
#endif
#ifdef B38400
	38400, B38400,
#endif
#ifdef B57600
	57600, B57600,
#endif
#ifdef B115200
	115200, B115200,
#endif
#ifdef EXTA
	19200, EXTA,
#endif
#ifdef EXTB
	38400, EXTB,
#endif
#ifdef B0
	0,  B0,
#endif
	-1,-1
};

int getspeed(pTHX_ PerlIO *file, I32 *in, I32 *out)
{
    int handle = PerlIO_fileno(file);
#if defined(I_TERMIOS) || defined(I_TERMIO) || defined(I_SGTTY)
    int i;
#endif
#ifdef I_TERMIOS
    /* Posixy stuff */

    struct termios buf;
    tcgetattr(handle,&buf);

    *in = *out = -1;
    *in = cfgetispeed(&buf);
    *out = cfgetospeed(&buf);
    
    for (i=0; terminal_speeds[i] !=- 1; i+=2) {
        if (*in == terminal_speeds[i+1]) {
            *in = terminal_speeds[i];
            break;
        }
    }
    for (i=0; terminal_speeds[i] != -1; i+=2) {
        if (*out == terminal_speeds[i+1]) {
            *out = terminal_speeds[i];
            break;
        }
    }
    return 0;	 	

#elif defined I_TERMIO
    /* SysV stuff */
    struct termio buf;

    ioctl(handle,TCGETA,&buf);

    *in=*out=-1;
    for (i=0; terminal_speeds[i] != -1; i+=2) {
        if ((buf.c_cflag & CBAUD) == terminal_speeds[i+1]) {
            *in = *out = terminal_speeds[i];
            break;
        }
    }
    return 0;	 	
    
#elif defined I_SGTTY
    /* BSD stuff */
    struct sgttyb buf;

    ioctl(handle,TIOCGETP,&buf);

    *in = *out = -1;

    for (i=0; terminal_speeds[i] != -1; i+=2) {
        if (buf.sg_ospeed == terminal_speeds[i+1]) {
            *out = terminal_speeds[i];
            break;
        }
    }
    
    for (i=0; terminal_speeds[i] != -1; i+=2) {
        if (buf.sg_ispeed == terminal_speeds[i+1]) {
            *in = terminal_speeds[i];
            break;
        }
    }
    
    return 0;	 	

#else

    /* No termio, termios or sgtty. I suppose we can try stty,
       but it would be nice if you could get a better OS */

    return -1;

#endif
}

#ifdef WIN32
struct tbuffer { DWORD Mode; };

#elif defined I_TERMIOS
# define USE_TERMIOS
# define tbuffer termios

#elif defined I_TERMIO
# define USE_TERMIO
# define tbuffer termio

#elif defined I_SGTTY
# define USE_SGTTY
struct tbuffer {
    struct sgttyb buf;
# if defined(TIOCGETC)
    struct tchars tchar;
# endif
# if defined(TIOCGLTC)
    struct ltchars ltchar;
# endif
# if defined(TIOCLGET)
    int local;
# endif
};

#else
#define USE_STTY
struct tbuffer {
    int dummy;
};
#endif

static HV * filehash; /* Used to store the original terminal settings for each handle*/
static HV * modehash; /* Used to record the current terminal "mode" for each handle*/

void ReadMode(pTHX_ PerlIO *file, int mode)
{
    dTHR;
    int handle;
    int firsttime;
    int oldmode;
    struct tbuffer work;
    struct tbuffer savebuf;
	
    handle = PerlIO_fileno(file);
	
    firsttime=!hv_exists(filehash, (char*)&handle, sizeof(int));

#ifdef WIN32
    if (!GetConsoleMode((HANDLE)_get_osfhandle(handle), &work.Mode))
        croak("GetConsoleMode failed, LastError=|%d|",GetLastError());
#elif defined USE_TERMIOS
    /* Posixy stuff */
    tcgetattr(handle,&work);
#elif defined USE_TERMIO
    /* SysV stuff */
    ioctl(handle,TCGETA,&work);
#elif defined USE_SGTTY
    /* BSD stuff */
    ioctl(handle,TIOCGETP,&work.buf);
#  if defined(TIOCGETC)
    ioctl(handle,TIOCGETC,&work.tchar);
#  endif
#  if defined(TIOCLGET)
    ioctl(handle,TIOCLGET,&work.local);
#  endif
#  if defined(TIOCGLTC)
    ioctl(handle,TIOCGLTC,&work.ltchar);
#  endif

#endif

    if (firsttime) {
        firsttime=0; 
        StructCopy(&work,&savebuf,struct tbuffer);
        if (!hv_store(filehash,(char*)&handle,sizeof(int),
                      newSVpv((char*)&savebuf,sizeof(struct tbuffer)),0))
            croak("Unable to stash terminal settings.\n");
        if (!hv_store(modehash,(char*)&handle,sizeof(int),newSViv(0),0))
            croak("Unable to stash terminal mode.\n");
    } else {
        SV ** temp;
        if (!(temp=hv_fetch(filehash,(char*)&handle,sizeof(int),0))) 
            croak("Unable to retrieve stashed terminal settings.\n");
        StructCopy(SvPV(*temp,PL_na),&savebuf,struct tbuffer);
        if (!(temp=hv_fetch(modehash,(char*)&handle,sizeof(int),0))) 
            croak("Unable to retrieve stashed terminal mode.\n");
        oldmode=SvIV(*temp);
    }

#ifdef WIN32

    switch (mode) {
    case 5:
        /* Should 5 disable ENABLE_WRAP_AT_EOL_OUTPUT? */
    case 4:
        work.Mode &= ~(ENABLE_ECHO_INPUT|ENABLE_PROCESSED_INPUT|ENABLE_LINE_INPUT|ENABLE_PROCESSED_OUTPUT);
        work.Mode |= 0;
        break;
    case 3:
        work.Mode &= ~(ENABLE_LINE_INPUT|ENABLE_ECHO_INPUT);
        work.Mode |= ENABLE_PROCESSED_INPUT|ENABLE_PROCESSED_OUTPUT;
        break;
    case 2:
        work.Mode &= ~(ENABLE_ECHO_INPUT);
        work.Mode |= ENABLE_LINE_INPUT|ENABLE_PROCESSED_INPUT|ENABLE_PROCESSED_OUTPUT;
        break;
    case 1:
        work.Mode &= ~(0);
        work.Mode |= ENABLE_ECHO_INPUT|ENABLE_LINE_INPUT|ENABLE_PROCESSED_INPUT|ENABLE_PROCESSED_OUTPUT;
        break;
    case 0:
        work = savebuf;
        firsttime = 1;
        break;
    }

    if (!SetConsoleMode((HANDLE)_get_osfhandle(handle), work.Mode))
        croak("SetConsoleMode failed, LastError=|%d|",GetLastError());

#endif /* WIN32 */


#ifdef USE_TERMIOS
/* What, me worry about standards? */
#       if !defined (VMIN)
#		define VMIN VEOF
#       endif
#	if !defined (VTIME)
#		define VTIME VEOL
#	endif
#	if !defined (IXANY)
#		define IXANY (0)
#	endif

#ifndef IEXTEN
# ifdef IDEFAULT
#  define IEXTEN IDEFAULT
# endif
#endif

/* XXX Is ONLCR in POSIX?.  The value of '4' seems to be the same for
   both SysV and Sun, so it's probably rather general, and I'm not
   aware of a POSIX way to do this otherwise.
*/
#ifndef ONLCR
# define ONLCR 4
#endif

#ifndef IMAXBEL
#define IMAXBEL 0
#endif
#ifndef ECHOE
#define ECHOE 0
#endif
#ifndef ECHOK
#define ECHOK 0
#endif
#ifndef ECHONL
#define ECHONL 0
#endif 
#ifndef ECHOPRT
#define ECHOPRT 0
#endif
#ifndef FLUSHO
#define FLUSHO 0
#endif
#ifndef PENDIN
#define PENDIN 0
#endif
#ifndef ECHOKE
#define ECHOKE 0
#endif
#ifndef ONLCR
#define ONLCR 0
#endif
#ifndef OCRNL
#define OCRNL 0
#endif
#ifndef ONLRET
#define ONLRET 0
#endif
#ifndef IUCLC
#define IUCLC 0
#endif
#ifndef OPOST
#define OPOST 0
#endif
#ifndef OLCUC
#define OLCUC 0
#endif
#ifndef ECHOCTL
#define ECHOCTL 0
#endif
#ifndef XCASE
#define XCASE 0
#endif
#ifndef BRKINT
#define BRKINT 0
#endif

    if (mode==5) {
        /*
         *  Disable everything except parity if needed.
         */
        
        /* Hopefully, this should put the tty into unbuffered mode
           with signals and control characters (both posixy and normal)
           disabled, along with flow control. Echo should be off.
           CR/LF is not translated, along with 8-bit/parity */

        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag &= ~(ICANON|ISIG|IEXTEN );
        work.c_lflag &= ~(ECHO|ECHOE|ECHOK|ECHONL|ECHOCTL);
        work.c_lflag &= ~(ECHOPRT|ECHOKE|FLUSHO|PENDIN|XCASE);
        work.c_lflag |= NOFLSH;
        work.c_iflag &= ~(IXOFF|IXON|IXANY|ICRNL|IMAXBEL|BRKINT);

        if (((work.c_iflag & INPCK) != INPCK) ||
            ((work.c_cflag & PARENB) != PARENB)) {
            work.c_iflag &= ~ISTRIP;
            work.c_iflag |= IGNPAR;
            work.c_iflag &= ~PARMRK;
        } 
        work.c_oflag &= ~(OPOST |ONLCR|OCRNL|ONLRET);
        
        work.c_cc[VTIME] = 0;
        work.c_cc[VMIN] = 1;
    }
    else if (mode==4) {
        /* Hopefully, this should put the tty into unbuffered mode
           with signals and control characters (both posixy and normal)
           disabled, along with flow control. Echo should be off.
           About the only thing left unchanged is 8-bit/parity */
        
        StructCopy(&savebuf,&work,struct tbuffer);

        /*work.c_iflag = savebuf.c_iflag;*/
        work.c_lflag &= ~(ICANON | ISIG | IEXTEN | ECHO);
        work.c_lflag &= ~(ECHOE | ECHOK | ECHONL|ECHOCTL|ECHOPRT|ECHOKE);
        work.c_iflag &= ~(IXON | IXANY | BRKINT);
        /* Coverity CID #180980 Uninitialized scalar variable */
        /*work.c_oflag = savebuf.c_oflag; */
        work.c_cc[VTIME] = 0;
        work.c_cc[VMIN] = 1;
    }
    else if (mode==3) {
        /* This should be an unbuffered mode with signals and control	
           characters enabled, as should be flow control. Echo should
           still be off */

        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag &= ~(ICANON | ECHO);
        work.c_lflag &= ~(ECHOE | ECHOK | ECHONL|ECHOCTL|ECHOPRT|ECHOKE);
        work.c_lflag |= ISIG | IEXTEN;
        /*work.c_iflag &= ~(IXON | IXOFF | IXANY);
          work.c_iflag |= savebuf.c_iflag & (IXON|IXOFF|IXANY);*/
        work.c_cc[VTIME] = 0;
        work.c_cc[VMIN] = 1;
    }
    else if (mode==2) {
        /* This should be an unbuffered mode with signals and control	
           characters enabled, as should be flow control. Echo should
           still be off */

        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag |= ICANON|ISIG|IEXTEN;
        work.c_lflag &= ~ECHO;
        work.c_lflag &= ~(ECHOE | ECHOK | ECHONL|ECHOCTL|ECHOPRT|ECHOKE);
        /*work.c_iflag &= ~(IXON |IXOFF|IXANY);
          work.c_iflag |= savebuf.c_iflag & (IXON|IXOFF|IXANY);*/
    }
    else if (mode==1) {
        /* This should be an unbuffered mode with signals and control	
           characters enabled, as should be flow control. Echo should
           still be off */

        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag |= ICANON|ECHO|ISIG|IEXTEN;
        /*work.c_iflag &= ~(IXON |IXOFF|IXANY);
          work.c_iflag |= savebuf.c_iflag & (IXON|IXOFF|IXANY);*/
    }
    else if (mode==0) {
        /*work.c_lflag &= ~BITMASK; 
          work.c_lflag |= savebuf.c_lflag & BITMASK;
          work.c_iflag &= ~(IXON|IXOFF|IXANY);
          work.c_iflag |= savebuf.c_iflag & (IXON|IXOFF|IXANY);*/
        StructCopy(&savebuf,&work,struct tbuffer);
        
        firsttime=1;
    }	
    else {
        croak("ReadMode %d is not implemented on this architecture.",mode);
        return;		
    }

    /* If switching from a "lower power" mode to a higher one, keep the
       data that may be in the queue, as it can easily be type-ahead. On
       switching to a lower mode from a higher one, however, flush the queue
       so that raw keystrokes won't hit an unexpecting program */
	
    if (DisableFlush || oldmode<=mode)
        tcsetattr(handle,TCSANOW,&work);
    else
        tcsetattr(handle,TCSAFLUSH,&work);

    /*tcsetattr(handle,TCSANOW,&work);*/ /* It might be better to FLUSH
					   when changing gears to a lower mode,
					   and only use NOW for higher modes. 
                                         */

#endif
#ifdef USE_TERMIO

/* What, me worry about standards? */

#	 if !defined (IXANY)
#                define IXANY (0)
#        endif

#ifndef ECHOE
#define ECHOE 0
#endif
#ifndef ECHOK
#define ECHOK 0
#endif
#ifndef ECHONL
#define ECHONL 0
#endif
#ifndef XCASE
#define XCASE 0
#endif
#ifndef BRKINT
#define BRKINT 0
#endif

    if (mode==5) {
        /* This mode should be echo disabled, signals disabled,
           flow control disabled, and unbuffered. CR/LF translation 
           is off, and 8 bits if possible */

        StructCopy(&savebuf,&work,struct tbuffer);
        
        work.c_lflag &= ~(ECHO | ISIG | ICANON | XCASE);
        work.c_lflag &= ~(ECHOE | ECHOK | ECHONL | TRK_IDEFAULT);
        work.c_iflag &= ~(IXON | IXOFF | IXANY | ICRNL | BRKINT);
        if ((work.c_cflag | PARENB)!=PARENB ) {
            work.c_iflag &= ~(ISTRIP|INPCK);
            work.c_iflag |= IGNPAR;
        } 
        work.c_oflag &= ~(OPOST|ONLCR);
        work.c_cc[VMIN] = 1;
        work.c_cc[VTIME] = 1;
    } 
    else if (mode==4) {
        /* This mode should be echo disabled, signals disabled,
           flow control disabled, and unbuffered. Parity is not
           touched. */
        
        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag &= ~(ECHO | ISIG | ICANON);
        work.c_lflag &= ~(ECHOE | ECHOK | ECHONL TRK_IDEFAULT);
        work.c_iflag &= ~(IXON | IXOFF | IXANY | BRKINT);
        work.c_cc[VMIN] = 1;
        work.c_cc[VTIME] = 1;
    } 
    else if (mode==3) {
        /* This mode tries to have echo off, signals enabled,
           flow control as per the original setting, and unbuffered. */

        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag &= ~(ECHO | ICANON);
        work.c_lflag &= ~(ECHOE | ECHOK | ECHONL | TRK_IDEFAULT);
        work.c_lflag |= ISIG;
        work.c_iflag &= ~(IXON | IXOFF | IXANY);
        work.c_iflag |= savebuf.c_iflag & (IXON|IXOFF|IXANY);
        work.c_cc[VMIN] = 1;
        work.c_cc[VTIME] = 1;
    }
    else if (mode==2) {
        /* This mode tries to set echo on, signals on, and buffering
           on, with flow control set to whatever it was originally. */

        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag |= (ISIG | ICANON);
        work.c_lflag &= ~ECHO;
        work.c_lflag &= ~(ECHOE | ECHOK | ECHONL | TRK_IDEFAULT);
        work.c_iflag &= ~(IXON | IXOFF | IXANY);
        work.c_iflag |= savebuf.c_iflag & (IXON|IXOFF|IXANY);
		
        /* This assumes turning ECHO and ICANON back on is
           sufficient to re-enable cooked mode. If this is a 
           problem, complain to me */
    } 
    else if (mode==1) {
        /* This mode tries to set echo on, signals on, and buffering
           on, with flow control set to whatever it was originally. */

        StructCopy(&savebuf,&work,struct tbuffer);

        work.c_lflag |= (ECHO | ISIG | ICANON);
        work.c_iflag &= ~TRK_IDEFAULT;
        work.c_iflag &= ~(IXON | IXOFF | IXANY);
        work.c_iflag |= savebuf.c_iflag & (IXON|IXOFF|IXANY);
		
        /* This assumes turning ECHO and ICANON back on is
           sufficient to re-enable cooked mode. If this is a 
           problem, complain to me */
    }		
    else if (mode==0) {
        /* Put things back the way they were */

        StructCopy(&savebuf,&work,struct tbuffer);
        firsttime=1;
    }
    else {
        croak("ReadMode %d is not implemented on this architecture.",mode);
        return;		
    }
    
    if (DisableFlush || oldmode<=mode) 
        ioctl(handle,TCSETA,&work);
    else
        ioctl(handle,TCSETAF,&work);

#endif

#ifdef USE_SGTTY

    if (mode==5) {
        /* Unbuffered, echo off, signals off, flow control off */
        /* CR-CR/LF mode off too, and 8-bit path enabled. */
# if defined(TIOCLGET) && defined(LPASS8)
        if ((work.buf.sg_flags & (EVENP|ODDP))==0 ||
            (work.buf.sg_flags & (EVENP|ODDP))==(EVENP|ODDP))
            work.local |= LPASS8; /* If parity isn't being used, use 8 bits */
# endif
        work.buf.sg_flags &= ~(ECHO|CRMOD);
        work.buf.sg_flags |= (RAW|CBREAK);
# if defined(TIOCGETC)
        work.tchar.t_intrc = -1;
        work.tchar.t_quitc = -1;
        work.tchar.t_startc= -1;
        work.tchar.t_stopc = -1;
        work.tchar.t_eofc  = -1;
        work.tchar.t_brkc  = -1;
# endif
# if defined(TIOCGLTC)
        work.ltchar.t_suspc= -1;
        work.ltchar.t_dsuspc= -1;
        work.ltchar.t_rprntc= -1;
        work.ltchar.t_flushc= -1;
        work.ltchar.t_werasc= -1;
        work.ltchar.t_lnextc= -1;
# endif
    }
    else if (mode==4) {
        /* Unbuffered, echo off, signals off, flow control off */
        work.buf.sg_flags &= ~(ECHO|RAW);
        work.buf.sg_flags |= (CBREAK|CRMOD);
# if defined(TIOCLGET)
        work.local=savebuf.local;
# endif
# if defined(TIOCGETC)
        work.tchar.t_intrc = -1;
        work.tchar.t_quitc = -1;
        work.tchar.t_startc= -1;
        work.tchar.t_stopc = -1;
        work.tchar.t_eofc  = -1;
        work.tchar.t_brkc  = -1;
# endif
# if defined(TIOCGLTC)
        work.ltchar.t_suspc= -1;
        work.ltchar.t_dsuspc= -1;
        work.ltchar.t_rprntc= -1;
        work.ltchar.t_flushc= -1;
        work.ltchar.t_werasc= -1;
        work.ltchar.t_lnextc= -1;
# endif
    }
    else if (mode==3) {
        /* Unbuffered, echo off, signals on, flow control on */
        work.buf.sg_flags &= ~(RAW|ECHO);
        work.buf.sg_flags |= CBREAK|CRMOD;
# if defined(TIOCLGET)
        work.local=savebuf.local;
# endif
# if defined(TIOCGLTC)
        work.tchar = savebuf.tchar;
# endif
# if defined(TIOCGLTC)
        work.ltchar = savebuf.ltchar;
# endif
    }
    else if (mode==2) {
        /* Buffered, echo on, signals on, flow control on */
        work.buf.sg_flags &= ~(RAW|CBREAK);
        work.buf.sg_flags |= CRMOD;
        work.buf.sg_flags &= ~ECHO;
# if defined(TIOCLGET)
        work.local=savebuf.local;
# endif
# if defined(TIOCGLTC)
        work.tchar = savebuf.tchar;
# endif
# if defined(TIOCGLTC)
        work.ltchar = savebuf.ltchar;
# endif
    }
    else if (mode==1) {
        /* Buffered, echo on, signals on, flow control on */
        work.buf.sg_flags &= ~(RAW|CBREAK);
        work.buf.sg_flags |= ECHO|CRMOD;
# if defined(TIOCLGET)
        work.local=savebuf.local;
# endif
# if defined(TIOCGLTC)
        work.tchar = savebuf.tchar;
# endif
# if defined(TIOCGLTC)
        work.ltchar = savebuf.ltchar;
# endif
    }
    else if (mode==0){
        /* Original settings */
#if 0
        work.buf.sg_flags &= ~(RAW|CBREAK|ECHO|CRMOD);
        work.buf.sg_flags |= savebuf.sg_flags & (RAW|CBREAK|ECHO|CRMOD);
#endif
        StructCopy(&savebuf,&work,struct tbuffer);
        firsttime = 1;
    }
    else {
        croak("ReadMode %d is not implemented on this architecture.",mode);
        return;		
    }
# if defined(TIOCLSET)
    ioctl(handle,TIOCLSET,&work.local);
# endif
# if defined(TIOCSETC)
    ioctl(handle,TIOCSETC,&work.tchar);
# endif
# if defined(TIOCGLTC)
    ioctl(handle,TIOCSLTC,&work.ltchar);
# endif
    if (DisableFlush || oldmode<=mode)
        ioctl(handle,TIOCSETN,&work.buf);
    else
        ioctl(handle,TIOCSETP,&work.buf);
#endif

#ifdef USE_STTY

    /* No termio, termios or sgtty. I suppose we can try stty,
       but it would be nice if you could get a better OS */

    if (mode==5)
        system("/bin/stty  raw -cbreak -isig -echo -ixon -onlcr -icrnl -brkint");
    else if (mode==4)
        system("/bin/stty -raw  cbreak -isig -echo -ixon  onlcr  icrnl -brkint");
    else if (mode==3)
        system("/bin/stty -raw  cbreak  isig -echo  ixon  onlcr  icrnl  brkint");
    else if (mode==2) 
        system("/bin/stty -raw -cbreak  isig  echo  ixon  onlcr  icrnl  brkint");
    else if (mode==1)
        system("/bin/stty -raw -cbreak  isig -echo  ixon  onlcr  icrnl  brkint");
    else if (mode==0)
        system("/bin/stty -raw -cbreak  isig  echo  ixon  onlcr  icrnl  brkint");

    /* Those probably won't work, but they couldn't hurt 
       at this point */

#endif

	/*warn("Mode set to %d.\n",mode);*/

    if (firsttime) {
        (void)hv_delete(filehash,(char*)&handle,sizeof(int),0);
        (void)hv_delete(modehash,(char*)&handle,sizeof(int),0);
    } else {
        if (!hv_store(modehash,(char*)&handle,sizeof(int),
                      newSViv(mode),0))
            croak("Unable to stash terminal settings.\n");
    }
    
}

#ifdef USE_PERLIO

/* Make use of a recent addition to Perl, if possible */
# define FCOUNT(f) PerlIO_get_cnt(f)
#else

 /* Make use of a recent addition to Configure, if possible */
# ifdef USE_STDIO_PTR
#  define FCOUNT(f) PerlIO_get_cnt(f)
# else
  /* This bit borrowed from pp_sys.c. Complain to Larry if it's broken. */
  /* If any of this works PerlIO_get_cnt() will too ... NI-S */
#  if defined(USE_STD_STDIO) || defined(atarist) /* this will work with atariST */
#   define FBASE(f) ((f)->_base)
#   define FSIZE(f) ((f)->_cnt + ((f)->_ptr - (f)->_base))
#   define FPTR(f) ((f)->_ptr)
#   define FCOUNT(f) ((f)->_cnt)
#  else
#   if defined(USE_LINUX_STDIO)
#     define FBASE(f) ((f)->_IO_read_base)
#     define FSIZE(f) ((f)->_IO_read_end - FBASE(f))
#     define FPTR(f) ((f)->_IO_read_ptr)
#     define FCOUNT(f) ((f)->_IO_read_end - FPTR(f))
#   endif
#  endif
# endif
#endif

/* This is for the best, I'm afraid. */
#if !defined(FCOUNT)
# ifdef Have_select
#  undef Have_select
# endif
# ifdef Have_poll
#  undef Have_poll
# endif
#endif

/* Note! If your machine has a bolixed up select() call that doesn't
understand this syntax, either fix the checkwaiting call below, or define
DONT_USE_SELECT. */

int selectfile(pTHX_ PerlIO *file,double delay)
{
#ifdef Have_select
    struct timeval t;
    int handle = PerlIO_fileno(file);

    /*char buf[32];    
      Select_fd_set_t fd=(Select_fd_set_t)&buf[0];*/
    
    fd_set fd;
    if (handle < 0 || (PerlIO_fast_gets(file) && PerlIO_get_cnt(file) > 0))
        return 1;
    
    /*t.tv_sec=t.tv_usec=0;*/

    if (delay < 0.0) delay = 0.0;
    t.tv_sec = (long)delay;
    delay -= (double)t.tv_sec;
    t.tv_usec = (long)(delay * 1000000.0);

    FD_ZERO(&fd);
    FD_SET(handle,&fd);
    if (select(handle+1,(Select_fd_set_t)&fd,
               (Select_fd_set_t)0,
               (Select_fd_set_t)&fd, &t)) return -1; 
    else return 0;
#else
    croak("select is not supported on this architecture");
    return 0;
#endif
}

int setnodelay(pTHX_ PerlIO *file, int mode)
{
#ifdef Have_nodelay
    int handle = PerlIO_fileno(file);
    int flags;
    flags=fcntl(handle,F_GETFL,0);
    if (mode)
        flags|=O_NODELAY;
    else
        flags&=~O_NODELAY;
    fcntl(handle,F_SETFL,flags);
    return 0;
#else
    croak("setnodelay is not supported on this architecture");
    return 0;
#endif
}

int pollfile(pTHX_ PerlIO *file, double delay)
{
#ifdef Have_poll
    int handle = PerlIO_fileno(file);
    struct pollfd fds;
    if (handle < 0 || (PerlIO_fast_gets(file) && PerlIO_get_cnt(file) > 0))
        return 1;
    if (delay < 0.0) delay = 0.0;
    fds.fd = handle;
    fds.events = POLLIN;
    fds.revents = 0;
    return (poll(&fds,1,(long)(delay * 1000.0))>0);
#else
    PERL_UNUSED_ARG(file);
    PERL_UNUSED_ARG(delay);
    croak("pollfile is not supported on this architecture");
    return 0;
#endif
}

#ifdef WIN32

/*

 This portion of the Win32 code is partially borrowed from a version of PDCurses.

*/

typedef struct {
    int repeatCount;
    int vKey;
    int vScan;
    int ascii;
    int control;
} win32_key_event_t;

#define KEY_PUSH(I, K) { events[I].repeatCount = 1; events[I].ascii = K; }
#define KEY_PUSH3(K1, K2, K3) \
    do { \
             eventCount = 0;            \
             KEY_PUSH(2, K1);           \
             KEY_PUSH(1, K2);           \
             KEY_PUSH(0, K3);           \
             eventCount = 3;            \
             goto again;                \
    } while (0)

#define KEY_PUSH4(K1, K2, K3, K4) \
    do { \
             eventCount = 0;            \
             KEY_PUSH(3, K1);           \
             KEY_PUSH(2, K2);           \
             KEY_PUSH(1, K3);           \
             KEY_PUSH(0, K4);           \
             eventCount = 4;            \
             goto again;                \
    } while (0)

int Win32PeekChar(pTHX_ PerlIO *file,U32 delay,char *key)
{
  int handle;
  HANDLE whnd;
  INPUT_RECORD record;
  DWORD readRecords;

#if 0
  static int keyCount = 0;
  static char lastKey = 0;
#endif

#define MAX_EVENTS 4
    static int eventCount = 0;
    static win32_key_event_t events[MAX_EVENTS];
    int keyCount;

    file = STDIN;

    handle = PerlIO_fileno(file);
    whnd = /*GetStdHandle(STD_INPUT_HANDLE)*/(HANDLE)_get_osfhandle(handle);


again:
#if 0
    if (keyCount > 0) {
      keyCount--;
      *key = lastKey;
      return TRUE;
    }
#endif

    /* printf("eventCount: %d\n", eventCount); */
    if (eventCount) {
        /* printf("key %d; repeatCount %d\n", *key, events[eventCount - 1].repeatCount); */
        *key = events[eventCount - 1].ascii;
        events[eventCount - 1].repeatCount--;
        if (events[eventCount - 1].repeatCount <= 0) {
            eventCount--;
        }
        return TRUE;
    }

    if (delay > 0) {
      if (WaitForSingleObject(whnd, delay * 1000) != WAIT_OBJECT_0) {
          return FALSE;
      }
    }

    if (delay != 0) {
      PeekConsoleInput(whnd, &record, 1, &readRecords);
      if (readRecords == 0) {
        return(FALSE);
      }
    }

    ReadConsoleInput(whnd, &record, 1, &readRecords);
    switch(record.EventType)
      {
      case KEY_EVENT:
        /* printf("\nkeyDown = %d, repeat = %d, vKey = %d, vScan = %d, ASCII = %d, Control = %d\n",
           record.Event.KeyEvent.bKeyDown,
           record.Event.KeyEvent.wRepeatCount,
           record.Event.KeyEvent.wVirtualKeyCode,
           record.Event.KeyEvent.wVirtualScanCode,
           record.Event.KeyEvent.uChar.AsciiChar,
           record.Event.KeyEvent.dwControlKeyState); */

        if (record.Event.KeyEvent.bKeyDown == FALSE)
          goto again;                        /* throw away KeyUp events */

        if (record.Event.KeyEvent.wVirtualKeyCode == 38) { /* up */
          KEY_PUSH3(27, 91, 65);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 40) { /* down */
          KEY_PUSH3(27, 91, 66);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 39) { /* right */
          KEY_PUSH3(27, 91, 67);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 37) { /* left */
          KEY_PUSH3(27, 91, 68);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 33) { /* page up */
          KEY_PUSH3(27, 79, 121);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 34) { /* page down */
          KEY_PUSH3(27, 79, 115);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 36) { /* home */
          KEY_PUSH4(27, 91, 49, 126);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 35) { /* end */
          KEY_PUSH4(27, 91, 52, 126);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 45) { /* insert */
          KEY_PUSH4(27, 91, 50, 126);
        }
        if (record.Event.KeyEvent.wVirtualKeyCode == 46) { /* delete */
          KEY_PUSH4(27, 91, 51, 126);
        }

        if (record.Event.KeyEvent.wVirtualKeyCode == 16
            ||  record.Event.KeyEvent.wVirtualKeyCode == 17
            ||  record.Event.KeyEvent.wVirtualKeyCode == 18
            ||  record.Event.KeyEvent.wVirtualKeyCode == 20
            ||  record.Event.KeyEvent.wVirtualKeyCode == 144
            ||  record.Event.KeyEvent.wVirtualKeyCode == 145)
          goto again;  /* throw away shift/alt/ctrl key only key events */
        keyCount = record.Event.KeyEvent.wRepeatCount;
        break;
      default:
        keyCount = 0;
        goto again;
        break;
      }

    *key = record.Event.KeyEvent.uChar.AsciiChar; 
    keyCount--;

    if (keyCount) {
      events[0].repeatCount = keyCount;
      events[0].ascii = *key;
      eventCount = 1;
    }
 
    return(TRUE);

    /* again:
       return (FALSE);
    */
}
#endif


STATIC int blockoptions() {
  return 0
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

STATIC int termoptions() {
    int i=0;
#ifdef USE_TERMIOS
    i=1;		
#endif
#ifdef USE_TERMIO
    i=2;
#endif
#ifdef USE_SGTTY
    i=3;
#endif
#ifdef USE_STTY
    i=4;
#endif
#ifdef USE_WIN32
    i=5;
#endif
    return i;
}


MODULE = Term::ReadKey		PACKAGE = Term::ReadKey

int
selectfile(file, delay)
	InputStream	file
	double	delay
CODE:
        RETVAL = selectfile(aTHX_ file, delay);
OUTPUT:
        RETVAL

# Clever, eh?
void
SetReadMode(mode, file=STDIN)
	int	mode
	InputStream	file
CODE:
	ReadMode(aTHX_ file, mode);

int
setnodelay(file, mode)
	InputStream	file
	int	mode
CODE:
	RETVAL = setnodelay(aTHX_ file, mode);
OUTPUT:
        RETVAL

int
pollfile(file, delay)
	InputStream	file
	double	delay
CODE:
        RETVAL = pollfile(aTHX_ file, delay);
OUTPUT:
        RETVAL


#ifdef WIN32

SV *
Win32PeekChar(file, delay)
	InputStream	file
	U32	delay
CODE:
	char key;
        if (Win32PeekChar(aTHX_ file, delay, &key))
            RETVAL = newSVpv(&key, 1);
        else
            RETVAL = newSVsv(&PL_sv_undef);
OUTPUT:
	RETVAL

#endif

int
blockoptions()

int
termoptions()

int
termsizeoptions()

void
GetTermSizeWin32(file=STDIN)
	InputStream	file
PREINIT:
	int x,y,xpix,ypix;
PPCODE:
	if ( GetTermSizeWin32(aTHX_ file,&x,&y,&xpix,&ypix) == 0) {
            EXTEND(sp, 4);
            PUSHs(sv_2mortal(newSViv((IV)x)));
            PUSHs(sv_2mortal(newSViv((IV)y)));
            PUSHs(sv_2mortal(newSViv((IV)xpix)));
            PUSHs(sv_2mortal(newSViv((IV)ypix)));
	}
	else {
            ST(0) = sv_newmortal();
	}

void
GetTermSizeVIO(file=STDIN)
	InputStream	file
PREINIT:
	int x,y,xpix,ypix;
PPCODE:
	if ( GetTermSizeVIO(aTHX_ file,&x,&y,&xpix,&ypix)==0) {
            EXTEND(sp, 4);
            PUSHs(sv_2mortal(newSViv((IV)x)));
            PUSHs(sv_2mortal(newSViv((IV)y)));
            PUSHs(sv_2mortal(newSViv((IV)xpix)));
            PUSHs(sv_2mortal(newSViv((IV)ypix)));
	}
	else {
            ST(0) = sv_newmortal();
	}

void
GetTermSizeGWINSZ(file=STDIN)
	InputStream	file
PREINIT:
	int x,y,xpix,ypix;
PPCODE:
	if ( GetTermSizeGWINSZ(aTHX_ file,&x,&y,&xpix,&ypix)==0) {
            EXTEND(sp, 4);
            PUSHs(sv_2mortal(newSViv((IV)x)));
            PUSHs(sv_2mortal(newSViv((IV)y)));
            PUSHs(sv_2mortal(newSViv((IV)xpix)));
            PUSHs(sv_2mortal(newSViv((IV)ypix)));
	}
	else {
            ST(0) = sv_newmortal();
	}

void
GetTermSizeGSIZE(file=STDIN)
	InputStream	file
PREINIT:
	int x,y,xpix,ypix;
PPCODE:
	if ( GetTermSizeGSIZE(aTHX_ file,&x,&y,&xpix,&ypix)==0) {
            EXTEND(sp, 4);
            PUSHs(sv_2mortal(newSViv((IV)x)));
            PUSHs(sv_2mortal(newSViv((IV)y)));
            PUSHs(sv_2mortal(newSViv((IV)xpix)));
            PUSHs(sv_2mortal(newSViv((IV)ypix)));
	}
	else {
            ST(0) = sv_newmortal();
	}

int
SetTerminalSize(width,height,xpix,ypix,file=STDIN)
	int	width
	int	height
	int	xpix
	int	ypix
	InputStream	file
CODE:
	RETVAL = SetTerminalSize(aTHX_ file,width,height,xpix,ypix);
OUTPUT:
	RETVAL

void
GetSpeed(file=STDIN)
	InputStream	file
PREINIT:
	I32 in,out;
PPCODE:
	if (getspeed(aTHX_ file,&in,&out)) {
            /* Failure */
            ST( 0) = sv_newmortal();
	} else {
            EXTEND(SP, 2);
            PUSHs(sv_2mortal(newSViv((IV)in)));
            PUSHs(sv_2mortal(newSViv((IV)out)));
	}

BOOT: 
	newXS("Term::ReadKey::GetControlChars", XS_Term__ReadKey_GetControlChars, file);
	newXS("Term::ReadKey::SetControlChars", XS_Term__ReadKey_SetControlChars, file);
	filehash = newHV();
	modehash = newHV();
