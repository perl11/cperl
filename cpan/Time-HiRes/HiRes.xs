/*
 * 
 * Copyright (c) 1996-2002 Douglas E. Wegscheid.  All rights reserved.
 * 
 * Copyright (c) 2002-2010 Jarkko Hietaniemi.
 * All rights reserved.
 *
 * Copyright (C) 2011, 2012, 2013 Andrew Main (Zefram) <zefram@fysh.org>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the same terms as Perl itself.
 */

#ifdef __cplusplus
extern "C" {
#endif
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#if defined(__CYGWIN__) && defined(HAS_W32API_WINDOWS_H)
# include <w32api/windows.h>
# define CYGWIN_WITH_W32API
#endif
#ifdef WIN32
# include <time.h>
#else
# include <sys/time.h>
#endif
#ifdef HAS_SELECT
# ifdef I_SYS_SELECT
#  include <sys/select.h>
# endif
#endif
#if defined(TIME_HIRES_CLOCK_GETTIME_SYSCALL) || defined(TIME_HIRES_CLOCK_GETRES_SYSCALL)
#include <syscall.h>
#endif
#ifdef __cplusplus
}
#endif

#define PERL_VERSION_DECIMAL(r,v,s) (r*1000000 + v*1000 + s)
#define PERL_DECIMAL_VERSION \
	PERL_VERSION_DECIMAL(PERL_REVISION,PERL_VERSION,PERL_SUBVERSION)
#define PERL_VERSION_GE(r,v,s) \
	(PERL_DECIMAL_VERSION >= PERL_VERSION_DECIMAL(r,v,s))

/* At least ppport.h 3.13 gets this wrong: one really cannot
 * have NVgf as anything else than "g" under Perl 5.6.x. */
#if PERL_REVISION == 5 && PERL_VERSION == 6
# undef NVgf
# define NVgf "g"
#endif

#if PERL_VERSION_GE(5,7,3) && !PERL_VERSION_GE(5,10,1)
# undef SAVEOP
# define SAVEOP() SAVEVPTR(PL_op)
#endif

#define IV_1E6 1000000
#define IV_1E7 10000000
#define IV_1E9 1000000000

#define NV_1E6 1000000.0
#define NV_1E7 10000000.0
#define NV_1E9 1000000000.0

#ifndef PerlProc_pause
#   define PerlProc_pause() Pause()
#endif

#ifdef HAS_PAUSE
#   define Pause   pause
#else
#   undef Pause /* In case perl.h did it already. */
#   define Pause() sleep(~0) /* Zzz for a long time. */
#endif

/* Though the cpp define ITIMER_VIRTUAL is available the functionality
 * is not supported in Cygwin as of August 2004, ditto for Win32.
 * Neither are ITIMER_PROF or ITIMER_REALPROF implemented.  --jhi
 */
#if defined(__CYGWIN__) || defined(WIN32)
#   undef ITIMER_VIRTUAL
#   undef ITIMER_PROF
#   undef ITIMER_REALPROF
#endif

#if defined(TIME_HIRES_CLOCK_GETTIME) && defined(_STRUCT_ITIMERSPEC)

/* HP-UX has CLOCK_XXX values but as enums, not as defines.
 * The only way to detect these would be to test compile for each. */
# ifdef __hpux
/* However, it seems that at least in HP-UX 11.31 ia64 there *are*
 * defines for these, so let's try detecting them. */
#  ifndef CLOCK_REALTIME
#    define CLOCK_REALTIME CLOCK_REALTIME
#    define CLOCK_VIRTUAL  CLOCK_VIRTUAL
#    define CLOCK_PROFILE  CLOCK_PROFILE
#  endif
# endif /* # ifdef __hpux */

#endif /* #if defined(TIME_HIRES_CLOCK_GETTIME) && defined(_STRUCT_ITIMERSPEC) */

#if defined(WIN32) || defined(CYGWIN_WITH_W32API)

#ifndef HAS_GETTIMEOFDAY
#   define HAS_GETTIMEOFDAY
#endif

/* shows up in winsock.h?
struct timeval {
 long tv_sec;
 long tv_usec;
}
*/

typedef union {
    unsigned __int64	ft_i64;
    FILETIME		ft_val;
} FT_t;

#define MY_CXT_KEY "Time::HiRes_" XS_VERSION

typedef struct {
    unsigned long run_count;
    unsigned __int64 base_ticks;
    unsigned __int64 tick_frequency;
    FT_t base_systime_as_filetime;
    unsigned __int64 reset_time;
} my_cxt_t;

START_MY_CXT

/* Number of 100 nanosecond units from 1/1/1601 to 1/1/1970 */
#ifdef __GNUC__
# define Const64(x) x##LL
#else
# define Const64(x) x##i64
#endif
#define EPOCH_BIAS  Const64(116444736000000000)

#ifdef Const64
# ifdef __GNUC__
#  define IV_1E6LL  1000000LL /* Needed because of Const64() ##-appends LL (or i64). */
#  define IV_1E7LL  10000000LL
#  define IV_1E9LL  1000000000LL
# else
#  define IV_1E6i64 1000000i64
#  define IV_1E7i64 10000000i64
#  define IV_1E9i64 1000000000i64
# endif
#endif

/* NOTE: This does not compute the timezone info (doing so can be expensive,
 * and appears to be unsupported even by glibc) */

/* dMY_CXT needs a Perl context and we don't want to call PERL_GET_CONTEXT
   for performance reasons */

#undef gettimeofday
#define gettimeofday(tp, not_used) _gettimeofday(aTHX_ tp, not_used)

/* If the performance counter delta drifts more than 0.5 seconds from the
 * system time then we recalibrate to the system time.  This means we may
 * move *backwards* in time! */
#define MAX_PERF_COUNTER_SKEW Const64(5000000) /* 0.5 seconds */

/* Reset reading from the performance counter every five minutes.
 * Many PC clocks just seem to be so bad. */
#define MAX_PERF_COUNTER_TICKS Const64(300000000) /* 300 seconds */

static int
_gettimeofday(pTHX_ struct timeval *tp, void *not_used)
{
    dMY_CXT;

    unsigned __int64 ticks;
    FT_t ft;

    if (MY_CXT.run_count++ == 0 ||
	MY_CXT.base_systime_as_filetime.ft_i64 > MY_CXT.reset_time) {
        QueryPerformanceFrequency((LARGE_INTEGER*)&MY_CXT.tick_frequency);
        QueryPerformanceCounter((LARGE_INTEGER*)&MY_CXT.base_ticks);
        GetSystemTimeAsFileTime(&MY_CXT.base_systime_as_filetime.ft_val);
        ft.ft_i64 = MY_CXT.base_systime_as_filetime.ft_i64;
	MY_CXT.reset_time = ft.ft_i64 + MAX_PERF_COUNTER_TICKS;
    }
    else {
	__int64 diff;
        QueryPerformanceCounter((LARGE_INTEGER*)&ticks);
        ticks -= MY_CXT.base_ticks;
        ft.ft_i64 = MY_CXT.base_systime_as_filetime.ft_i64
                    + Const64(IV_1E7) * (ticks / MY_CXT.tick_frequency)
                    +(Const64(IV_1E7) * (ticks % MY_CXT.tick_frequency)) / MY_CXT.tick_frequency;
	diff = ft.ft_i64 - MY_CXT.base_systime_as_filetime.ft_i64;
	if (diff < -MAX_PERF_COUNTER_SKEW || diff > MAX_PERF_COUNTER_SKEW) {
	    MY_CXT.base_ticks += ticks;
            GetSystemTimeAsFileTime(&MY_CXT.base_systime_as_filetime.ft_val);
            ft.ft_i64 = MY_CXT.base_systime_as_filetime.ft_i64;
	}
    }

    /* seconds since epoch */
    tp->tv_sec = (long)((ft.ft_i64 - EPOCH_BIAS) / Const64(IV_1E7));

    /* microseconds remaining */
    tp->tv_usec = (long)((ft.ft_i64 / Const64(10)) % Const64(IV_1E6));

    return 0;
}
#endif

#if defined(WIN32) && !defined(ATLEASTFIVEOHOHFIVE)
static unsigned int
sleep(unsigned int t)
{
    Sleep(t*1000);
    return 0;
}
#endif

#if !defined(HAS_GETTIMEOFDAY) && defined(VMS)
#define HAS_GETTIMEOFDAY

#include <lnmdef.h>
#include <time.h> /* gettimeofday */
#include <stdlib.h> /* qdiv */
#include <starlet.h> /* sys$gettim */
#include <descrip.h>
#ifdef __VAX
#include <lib$routines.h> /* lib$ediv() */
#endif

/*
        VMS binary time is expressed in 100 nano-seconds since
        system base time which is 17-NOV-1858 00:00:00.00
*/

#define DIV_100NS_TO_SECS  10000000L
#define DIV_100NS_TO_USECS 10L

/* 
        gettimeofday is supposed to return times since the epoch
        so need to determine this in terms of VMS base time
*/
static $DESCRIPTOR(dscepoch,"01-JAN-1970 00:00:00.00");

#ifdef __VAX
static long base_adjust[2]={0L,0L};
#else
static __int64 base_adjust=0;
#endif

/* 

   If we don't have gettimeofday, then likely we are on a VMS machine that
   operates on local time rather than UTC...so we have to zone-adjust.
   This code gleefully swiped from VMS.C 

*/
/* method used to handle UTC conversions:
 *   1 == CRTL gmtime();  2 == SYS$TIMEZONE_DIFFERENTIAL;  3 == no correction
 */
static int gmtime_emulation_type;
/* number of secs to add to UTC POSIX-style time to get local time */
static long int utc_offset_secs;
static struct dsc$descriptor_s fildevdsc = 
  { 12, DSC$K_DTYPE_T, DSC$K_CLASS_S, "LNM$FILE_DEV" };
static struct dsc$descriptor_s *fildev[] = { &fildevdsc, NULL };

static time_t toutc_dst(time_t loc) {
  struct tm *rsltmp;

  if ((rsltmp = localtime(&loc)) == NULL) return -1;
  loc -= utc_offset_secs;
  if (rsltmp->tm_isdst) loc -= 3600;
  return loc;
}

static time_t toloc_dst(time_t utc) {
  struct tm *rsltmp;

  utc += utc_offset_secs;
  if ((rsltmp = localtime(&utc)) == NULL) return -1;
  if (rsltmp->tm_isdst) utc += 3600;
  return utc;
}

#define _toutc(secs)  ((secs) == (time_t) -1 ? (time_t) -1 : \
       ((gmtime_emulation_type || timezone_setup()), \
       (gmtime_emulation_type == 1 ? toutc_dst(secs) : \
       ((secs) - utc_offset_secs))))

#define _toloc(secs)  ((secs) == (time_t) -1 ? (time_t) -1 : \
       ((gmtime_emulation_type || timezone_setup()), \
       (gmtime_emulation_type == 1 ? toloc_dst(secs) : \
       ((secs) + utc_offset_secs))))

static int
timezone_setup(void) 
{
  struct tm *tm_p;

  if (gmtime_emulation_type == 0) {
    int dstnow;
    time_t base = 15 * 86400; /* 15jan71; to avoid month/year ends between    */
                              /* results of calls to gmtime() and localtime() */
                              /* for same &base */

    gmtime_emulation_type++;
    if ((tm_p = gmtime(&base)) == NULL) { /* CRTL gmtime() is a fake */
      char off[LNM$C_NAMLENGTH+1];;

      gmtime_emulation_type++;
      if (!Perl_vmstrnenv("SYS$TIMEZONE_DIFFERENTIAL",off,0,fildev,0)) {
        gmtime_emulation_type++;
        utc_offset_secs = 0;
        Perl_warn(aTHX_ "no UTC offset information; assuming local time is UTC");
      }
      else { utc_offset_secs = atol(off); }
    }
    else { /* We've got a working gmtime() */
      struct tm gmt, local;

      gmt = *tm_p;
      tm_p = localtime(&base);
      local = *tm_p;
      utc_offset_secs  = (local.tm_mday - gmt.tm_mday) * 86400;
      utc_offset_secs += (local.tm_hour - gmt.tm_hour) * 3600;
      utc_offset_secs += (local.tm_min  - gmt.tm_min)  * 60;
      utc_offset_secs += (local.tm_sec  - gmt.tm_sec);
    }
  }
  return 1;
}


int
gettimeofday (struct timeval *tp, void *tpz)
{
 long ret;
#ifdef __VAX
 long quad[2];
 long quad1[2];
 long div_100ns_to_secs;
 long div_100ns_to_usecs;
 long quo,rem;
 long quo1,rem1;
#else
 __int64 quad;
 __qdiv_t ans1,ans2;
#endif
/*
        In case of error, tv_usec = 0 and tv_sec = VMS condition code.
        The return from function is also set to -1.
        This is not exactly as per the manual page.
*/

 tp->tv_usec = 0;

#ifdef __VAX
 if (base_adjust[0]==0 && base_adjust[1]==0) {
#else
 if (base_adjust==0) { /* Need to determine epoch adjustment */
#endif
        ret=sys$bintim(&dscepoch,&base_adjust);
        if (1 != (ret &&1)) {
                tp->tv_sec = ret;
                return -1;
        }
 }

 ret=sys$gettim(&quad); /* Get VMS system time */
 if ((1 && ret) == 1) {
#ifdef __VAX
        quad[0] -= base_adjust[0]; /* convert to epoch offset */
        quad[1] -= base_adjust[1]; /* convert 2nd half of quadword */
        div_100ns_to_secs = DIV_100NS_TO_SECS;
        div_100ns_to_usecs = DIV_100NS_TO_USECS;
        lib$ediv(&div_100ns_to_secs,&quad,&quo,&rem);
        quad1[0] = rem;
        quad1[1] = 0L;
        lib$ediv(&div_100ns_to_usecs,&quad1,&quo1,&rem1);
        tp->tv_sec = quo; /* Whole seconds */
        tp->tv_usec = quo1; /* Micro-seconds */
#else
        quad -= base_adjust; /* convert to epoch offset */
        ans1=qdiv(quad,DIV_100NS_TO_SECS);
        ans2=qdiv(ans1.rem,DIV_100NS_TO_USECS);
        tp->tv_sec = ans1.quot; /* Whole seconds */
        tp->tv_usec = ans2.quot; /* Micro-seconds */
#endif
 } else {
        tp->tv_sec = ret;
        return -1;
 }
# ifdef VMSISH_TIME
# ifdef RTL_USES_UTC
  if (VMSISH_TIME) tp->tv_sec = _toloc(tp->tv_sec);
# else
  if (!VMSISH_TIME) tp->tv_sec = _toutc(tp->tv_sec);
# endif
# endif
 return 0;
}
#endif


 /* Do not use H A S _ N A N O S L E E P
  * so that Perl Configure doesn't scan for it (and pull in -lrt and
  * the like which are not usually good ideas for the default Perl).
  * (We are part of the core perl now.)
  * The TIME_HIRES_NANOSLEEP is set by Makefile.PL. */
#if !defined(HAS_USLEEP) && defined(TIME_HIRES_NANOSLEEP)
#define HAS_USLEEP
#define usleep hrt_usleep  /* could conflict with ncurses for static build */

void
hrt_usleep(unsigned long usec) /* This is used to emulate usleep. */
{
    struct timespec res;
    res.tv_sec = usec / IV_1E6;
    res.tv_nsec = ( usec - res.tv_sec * IV_1E6 ) * 1000;
    nanosleep(&res, NULL);
}

#endif /* #if !defined(HAS_USLEEP) && defined(TIME_HIRES_NANOSLEEP) */

#if !defined(HAS_USLEEP) && defined(HAS_SELECT)
#ifndef SELECT_IS_BROKEN
#define HAS_USLEEP
#define usleep hrt_usleep  /* could conflict with ncurses for static build */

void
hrt_usleep(unsigned long usec)
{
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = usec;
    select(0, (Select_fd_set_t)NULL, (Select_fd_set_t)NULL,
		(Select_fd_set_t)NULL, &tv);
}
#endif
#endif /* #if !defined(HAS_USLEEP) && defined(HAS_SELECT) */

#if !defined(HAS_USLEEP) && defined(WIN32)
#define HAS_USLEEP
#define usleep hrt_usleep  /* could conflict with ncurses for static build */

void
hrt_usleep(unsigned long usec)
{
    long msec;
    msec = usec / 1000;
    Sleep (msec);
}
#endif /* #if !defined(HAS_USLEEP) && defined(WIN32) */

#if !defined(HAS_USLEEP) && defined(HAS_POLL)
#define HAS_USLEEP
#define usleep hrt_usleep  /* could conflict with ncurses for static build */

void
hrt_usleep(unsigned long usec)
{
    int msec = usec / 1000;
    poll(0, 0, msec);
}

#endif /* #if !defined(HAS_USLEEP) && defined(HAS_POLL) */

#if defined(HAS_SETITIMER) && defined(ITIMER_REAL)

static int
hrt_ualarm_itimero(struct itimerval *oitv, int usec, int uinterval)
{
   struct itimerval itv;
   itv.it_value.tv_sec = usec / IV_1E6;
   itv.it_value.tv_usec = usec % IV_1E6;
   itv.it_interval.tv_sec = uinterval / IV_1E6;
   itv.it_interval.tv_usec = uinterval % IV_1E6;
   return setitimer(ITIMER_REAL, &itv, oitv);
}

int
hrt_ualarm_itimer(int usec, int uinterval)
{
  return hrt_ualarm_itimero(NULL, usec, uinterval);
}

#ifdef HAS_UALARM
int
hrt_ualarm(int usec, int interval) /* for binary compat before 1.91 */
{
   return hrt_ualarm_itimer(usec, interval);
}
#endif /* #ifdef HAS_UALARM */
#endif /* #if !defined(HAS_UALARM) && defined(HAS_SETITIMER) */

#if !defined(HAS_UALARM) && defined(HAS_SETITIMER)
#define HAS_UALARM
#define ualarm hrt_ualarm_itimer  /* could conflict with ncurses for static build */
#endif

#if !defined(HAS_UALARM) && defined(VMS)
#define HAS_UALARM
#define ualarm vms_ualarm 

#include <lib$routines.h>
#include <ssdef.h>
#include <starlet.h>
#include <descrip.h>
#include <signal.h>
#include <jpidef.h>
#include <psldef.h>

#define VMSERR(s)   (!((s)&1))

static void
us_to_VMS(useconds_t mseconds, unsigned long v[])
{
    int iss;
    unsigned long qq[2];

    qq[0] = mseconds;
    qq[1] = 0;
    v[0] = v[1] = 0;

    iss = lib$addx(qq,qq,qq);
    if (VMSERR(iss)) lib$signal(iss);
    iss = lib$subx(v,qq,v);
    if (VMSERR(iss)) lib$signal(iss);
    iss = lib$addx(qq,qq,qq);
    if (VMSERR(iss)) lib$signal(iss);
    iss = lib$subx(v,qq,v);
    if (VMSERR(iss)) lib$signal(iss);
    iss = lib$subx(v,qq,v);
    if (VMSERR(iss)) lib$signal(iss);
}

static int
VMS_to_us(unsigned long v[])
{
    int iss;
    unsigned long div=10,quot, rem;

    iss = lib$ediv(&div,v,&quot,&rem);
    if (VMSERR(iss)) lib$signal(iss);

    return quot;
}

typedef unsigned short word;
typedef struct _ualarm {
    int function;
    int repeat;
    unsigned long delay[2];
    unsigned long interval[2];
    unsigned long remain[2];
} Alarm;


static int alarm_ef;
static Alarm *a0, alarm_base;
#define UAL_NULL   0
#define UAL_SET    1
#define UAL_CLEAR  2
#define UAL_ACTIVE 4
static void ualarm_AST(Alarm *a);

static int 
vms_ualarm(int mseconds, int interval)
{
    Alarm *a, abase;
    struct item_list3 {
        word length;
        word code;
        void *bufaddr;
        void *retlenaddr;
    } ;
    static struct item_list3 itmlst[2];
    static int first = 1;
    unsigned long asten;
    int iss, enabled;

    if (first) {
        first = 0;
        itmlst[0].code       = JPI$_ASTEN;
        itmlst[0].length     = sizeof(asten);
        itmlst[0].retlenaddr = NULL;
        itmlst[1].code       = 0;
        itmlst[1].length     = 0;
        itmlst[1].bufaddr    = NULL;
        itmlst[1].retlenaddr = NULL;

        iss = lib$get_ef(&alarm_ef);
        if (VMSERR(iss)) lib$signal(iss);

        a0 = &alarm_base;
        a0->function = UAL_NULL;
    }
    itmlst[0].bufaddr    = &asten;
    
    iss = sys$getjpiw(0,0,0,itmlst,0,0,0);
    if (VMSERR(iss)) lib$signal(iss);
    if (!(asten&0x08)) return -1;

    a = &abase;
    if (mseconds) {
        a->function = UAL_SET;
    } else {
        a->function = UAL_CLEAR;
    }

    us_to_VMS(mseconds, a->delay);
    if (interval) {
        us_to_VMS(interval, a->interval);
        a->repeat = 1;
    } else 
        a->repeat = 0;

    iss = sys$clref(alarm_ef);
    if (VMSERR(iss)) lib$signal(iss);

    iss = sys$dclast(ualarm_AST,a,0);
    if (VMSERR(iss)) lib$signal(iss);

    iss = sys$waitfr(alarm_ef);
    if (VMSERR(iss)) lib$signal(iss);

    if (a->function == UAL_ACTIVE) 
        return VMS_to_us(a->remain);
    else
        return 0;
}



static void
ualarm_AST(Alarm *a)
{
    int iss;
    unsigned long now[2];

    iss = sys$gettim(now);
    if (VMSERR(iss)) lib$signal(iss);

    if (a->function == UAL_SET || a->function == UAL_CLEAR) {
        if (a0->function == UAL_ACTIVE) {
            iss = sys$cantim(a0,PSL$C_USER);
            if (VMSERR(iss)) lib$signal(iss);

            iss = lib$subx(a0->remain, now, a->remain);
            if (VMSERR(iss)) lib$signal(iss);

            if (a->remain[1] & 0x80000000) 
                a->remain[0] = a->remain[1] = 0;
        }

        if (a->function == UAL_SET) {
            a->function = a0->function;
            a0->function = UAL_ACTIVE;
            a0->repeat = a->repeat;
            if (a0->repeat) {
                a0->interval[0] = a->interval[0];
                a0->interval[1] = a->interval[1];
            }
            a0->delay[0] = a->delay[0];
            a0->delay[1] = a->delay[1];

            iss = lib$subx(now, a0->delay, a0->remain);
            if (VMSERR(iss)) lib$signal(iss);

            iss = sys$setimr(0,a0->delay,ualarm_AST,a0);
            if (VMSERR(iss)) lib$signal(iss);
        } else {
            a->function = a0->function;
            a0->function = UAL_NULL;
        }
        iss = sys$setef(alarm_ef);
        if (VMSERR(iss)) lib$signal(iss);
    } else if (a->function == UAL_ACTIVE) {
        if (a->repeat) {
            iss = lib$subx(now, a->interval, a->remain);
            if (VMSERR(iss)) lib$signal(iss);

            iss = sys$setimr(0,a->interval,ualarm_AST,a);
            if (VMSERR(iss)) lib$signal(iss);
        } else {
            a->function = UAL_NULL;
        }
        iss = sys$wake(0,0);
        if (VMSERR(iss)) lib$signal(iss);
        lib$signal(SS$_ASTFLT);
    } else {
        lib$signal(SS$_BADPARAM);
    }
}

#endif /* #if !defined(HAS_UALARM) && defined(VMS) */

#ifdef HAS_GETTIMEOFDAY

static int
myU2time(pTHX_ UV *ret)
{
  struct timeval Tp;
  int status;
  status = gettimeofday (&Tp, NULL);
  ret[0] = Tp.tv_sec;
  ret[1] = Tp.tv_usec;
  return status;
}

static NV
myNVtime()
{
#ifdef WIN32
  dTHX;
#endif
  struct timeval Tp;
  int status;
  status = gettimeofday (&Tp, NULL);
  return status == 0 ? Tp.tv_sec + (Tp.tv_usec / NV_1E6) : -1.0;
}

#endif /* #ifdef HAS_GETTIMEOFDAY */

static void
hrstatns(UV *atime_nsec, UV *mtime_nsec, UV *ctime_nsec)
{
  dTHX;
#if TIME_HIRES_STAT == 1
  *atime_nsec = PL_statcache.st_atimespec.tv_nsec;
  *mtime_nsec = PL_statcache.st_mtimespec.tv_nsec;
  *ctime_nsec = PL_statcache.st_ctimespec.tv_nsec;
#elif TIME_HIRES_STAT == 2
  *atime_nsec = PL_statcache.st_atimensec;
  *mtime_nsec = PL_statcache.st_mtimensec;
  *ctime_nsec = PL_statcache.st_ctimensec;
#elif TIME_HIRES_STAT == 3
  *atime_nsec = PL_statcache.st_atime_n;
  *mtime_nsec = PL_statcache.st_mtime_n;
  *ctime_nsec = PL_statcache.st_ctime_n;
#elif TIME_HIRES_STAT == 4
  *atime_nsec = PL_statcache.st_atim.tv_nsec;
  *mtime_nsec = PL_statcache.st_mtim.tv_nsec;
  *ctime_nsec = PL_statcache.st_ctim.tv_nsec;
#elif TIME_HIRES_STAT == 5
  *atime_nsec = PL_statcache.st_uatime * 1000;
  *mtime_nsec = PL_statcache.st_umtime * 1000;
  *ctime_nsec = PL_statcache.st_uctime * 1000;
#else /* !TIME_HIRES_STAT */
  *atime_nsec = 0;
  *mtime_nsec = 0;
  *ctime_nsec = 0;
#endif /* !TIME_HIRES_STAT */
}

#include "const-c.inc"

MODULE = Time::HiRes            PACKAGE = Time::HiRes

PROTOTYPES: ENABLE

BOOT:
{
#ifdef MY_CXT_KEY
  MY_CXT_INIT;
#endif
#ifdef ATLEASTFIVEOHOHFIVE
#   ifdef HAS_GETTIMEOFDAY
  {
    (void) hv_store(PL_modglobal, "Time::NVtime", 12,
		newSViv(PTR2IV(myNVtime)), 0);
    (void) hv_store(PL_modglobal, "Time::U2time", 12,
		newSViv(PTR2IV(myU2time)), 0);
  }
#   endif
#endif
}

#if defined(USE_ITHREADS) && defined(MY_CXT_KEY)

void
CLONE(...)
    CODE:
    MY_CXT_CLONE;

#endif

INCLUDE: const-xs.inc

#if defined(HAS_USLEEP) && defined(HAS_GETTIMEOFDAY)

NV
usleep(useconds)
        NV useconds
	PREINIT:
	struct timeval Ta, Tb;
	CODE:
	gettimeofday(&Ta, NULL);
	if (items > 0) {
	    if (useconds >= 1E6) {
		IV seconds = (IV) (useconds / 1E6);
		/* If usleep() has been implemented using setitimer()
		 * then this contortion is unnecessary-- but usleep()
		 * may be implemented in some other way, so let's contort. */
		if (seconds) {
		    sleep(seconds);
		    useconds -= 1E6 * seconds;
		}
	    } else if (useconds < 0.0)
	        croak("Time::HiRes::usleep(%"NVgf"): negative time not invented yet", useconds);
	    usleep((U32)useconds);
	} else
	    PerlProc_pause();
	gettimeofday(&Tb, NULL);
#if 0
	printf("[%ld %ld] [%ld %ld]\n", Tb.tv_sec, Tb.tv_usec, Ta.tv_sec, Ta.tv_usec);
#endif
	RETVAL = 1E6*(Tb.tv_sec-Ta.tv_sec)+(NV)((IV)Tb.tv_usec-(IV)Ta.tv_usec);

	OUTPUT:
	RETVAL

#if defined(TIME_HIRES_NANOSLEEP)

NV
nanosleep(nsec)
        NV nsec
	PREINIT:
	struct timespec sleepfor, unslept;
	CODE:
	if (nsec < 0.0)
	    croak("Time::HiRes::nanosleep(%"NVgf"): negative time not invented yet", nsec);
	sleepfor.tv_sec = (Time_t)(nsec / 1e9);
	sleepfor.tv_nsec = (long)(nsec - ((NV)sleepfor.tv_sec) * 1e9);
	if (!nanosleep(&sleepfor, &unslept)) {
	    RETVAL = nsec;
	} else {
	    sleepfor.tv_sec -= unslept.tv_sec;
	    sleepfor.tv_nsec -= unslept.tv_nsec;
	    if (sleepfor.tv_nsec < 0) {
		sleepfor.tv_sec--;
		sleepfor.tv_nsec += 1000000000;
	    }
	    RETVAL = ((NV)sleepfor.tv_sec) * 1e9 + ((NV)sleepfor.tv_nsec);
	}
    OUTPUT:
	RETVAL

#else  /* #if defined(TIME_HIRES_NANOSLEEP) */

NV
nanosleep(nsec)
        NV nsec
    CODE:
        croak("Time::HiRes::nanosleep(): unimplemented in this platform");
        RETVAL = 0.0;
    OUTPUT:
	RETVAL

#endif /* #if defined(TIME_HIRES_NANOSLEEP) */

NV
sleep(...)
	PREINIT:
	struct timeval Ta, Tb;
	CODE:
	gettimeofday(&Ta, NULL);
	if (items > 0) {
	    NV seconds  = SvNV(ST(0));
	    if (seconds >= 0.0) {
	         UV useconds = (UV)(1E6 * (seconds - (UV)seconds));
		 if (seconds >= 1.0)
		     sleep((U32)seconds);
		 if ((IV)useconds < 0) {
#if defined(__sparc64__) && defined(__GNUC__)
		   /* Sparc64 gcc 2.95.3 (e.g. on NetBSD) has a bug
		    * where (0.5 - (UV)(0.5)) will under certain
		    * circumstances (if the double is cast to UV more
		    * than once?) evaluate to -0.5, instead of 0.5. */
		   useconds = -(IV)useconds;
#endif /* #if defined(__sparc64__) && defined(__GNUC__) */
		   if ((IV)useconds < 0)
		     croak("Time::HiRes::sleep(%"NVgf"): internal error: useconds < 0 (unsigned %"UVuf" signed %"IVdf")", seconds, useconds, (IV)useconds);
		 }
		 usleep(useconds);
	    } else
	        croak("Time::HiRes::sleep(%"NVgf"): negative time not invented yet", seconds);
	} else
	    PerlProc_pause();
	gettimeofday(&Tb, NULL);
#if 0
	printf("[%ld %ld] [%ld %ld]\n", Tb.tv_sec, Tb.tv_usec, Ta.tv_sec, Ta.tv_usec);
#endif
	RETVAL = (NV)(Tb.tv_sec-Ta.tv_sec)+0.000001*(NV)(Tb.tv_usec-Ta.tv_usec);

	OUTPUT:
	RETVAL

#else  /* #if defined(HAS_USLEEP) && defined(HAS_GETTIMEOFDAY) */

NV
usleep(useconds)
        NV useconds
    CODE:
        croak("Time::HiRes::usleep(): unimplemented in this platform");
        RETVAL = 0.0;
    OUTPUT:
	RETVAL

#endif /* #if defined(HAS_USLEEP) && defined(HAS_GETTIMEOFDAY) */

#ifdef HAS_UALARM

IV
ualarm(useconds,uinterval=0)
	int useconds
	int uinterval
	CODE:
	if (useconds < 0 || uinterval < 0)
	    croak("Time::HiRes::ualarm(%d, %d): negative time not invented yet", useconds, uinterval);
#if defined(HAS_SETITIMER) && defined(ITIMER_REAL)
	  {
	        struct itimerval itv;
	        if (hrt_ualarm_itimero(&itv, useconds, uinterval)) {
		  /* To conform to ualarm's interface, we're actually ignoring
		     an error here.  */
		  RETVAL = 0;
		} else {
		  RETVAL = itv.it_value.tv_sec * IV_1E6 + itv.it_value.tv_usec;
		}
	  }
#else
	if (useconds >= IV_1E6 || uinterval >= IV_1E6) 
		croak("Time::HiRes::ualarm(%d, %d): useconds or uinterval equal to or more than %"IVdf, useconds, uinterval, IV_1E6);
	RETVAL = ualarm(useconds, uinterval);
#endif

	OUTPUT:
	RETVAL

NV
alarm(seconds,interval=0)
	NV seconds
	NV interval
	CODE:
	if (seconds < 0.0 || interval < 0.0)
	    croak("Time::HiRes::alarm(%"NVgf", %"NVgf"): negative time not invented yet", seconds, interval);
	{
	  IV iseconds = (IV)seconds;
	  IV iinterval = (IV)interval;
	  NV fseconds = seconds - iseconds;
	  NV finterval = interval - iinterval;
	  IV useconds, uinterval;
	  if (fseconds >= 1.0 || finterval >= 1.0)
		croak("Time::HiRes::alarm(%"NVgf", %"NVgf"): seconds or interval too large to split correctly", seconds, interval);
	  useconds = IV_1E6 * fseconds;
	  uinterval = IV_1E6 * finterval;
#if defined(HAS_SETITIMER) && defined(ITIMER_REAL)
	  {
	        struct itimerval nitv, oitv;
		nitv.it_value.tv_sec = iseconds;
		nitv.it_value.tv_usec = useconds;
		nitv.it_interval.tv_sec = iinterval;
		nitv.it_interval.tv_usec = uinterval;
	        if (setitimer(ITIMER_REAL, &nitv, &oitv)) {
		  /* To conform to alarm's interface, we're actually ignoring
		     an error here.  */
		  RETVAL = 0;
		} else {
		  RETVAL = oitv.it_value.tv_sec + ((NV)oitv.it_value.tv_usec) / NV_1E6;
		}
	  }
#else
	  if (iseconds || iinterval)
		croak("Time::HiRes::alarm(%"NVgf", %"NVgf"): seconds or interval equal to or more than 1.0 ", seconds, interval);
	    RETVAL = (NV)ualarm( useconds, uinterval ) / NV_1E6;
#endif
	}

	OUTPUT:
	RETVAL

#else

int
ualarm(useconds,interval=0)
	int useconds
	int interval
    CODE:
        croak("Time::HiRes::ualarm(): unimplemented in this platform");
	RETVAL = -1;
    OUTPUT:
	RETVAL

NV
alarm(seconds,interval=0)
	NV seconds
	NV interval
    CODE:
        croak("Time::HiRes::alarm(): unimplemented in this platform");
	RETVAL = 0.0;
    OUTPUT:
	RETVAL

#endif /* #ifdef HAS_UALARM */

#ifdef HAS_GETTIMEOFDAY
#    ifdef MACOS_TRADITIONAL	/* fix epoch TZ and use unsigned time_t */
void
gettimeofday()
        PREINIT:
        struct timeval Tp;
        struct timezone Tz;
        PPCODE:
        int status;
        status = gettimeofday (&Tp, &Tz);

	if (status == 0) {
	     Tp.tv_sec += Tz.tz_minuteswest * 60;	/* adjust for TZ */
             if (GIMME == G_ARRAY) {
                 EXTEND(sp, 2);
                 /* Mac OS (Classic) has unsigned time_t */
                 PUSHs(sv_2mortal(newSVuv(Tp.tv_sec)));
                 PUSHs(sv_2mortal(newSViv(Tp.tv_usec)));
             } else {
                 EXTEND(sp, 1);
                 PUSHs(sv_2mortal(newSVnv(Tp.tv_sec + (Tp.tv_usec / NV_1E6))));
	     }
        }

NV
time()
        PREINIT:
        struct timeval Tp;
        struct timezone Tz;
        CODE:
        int status;
        status = gettimeofday (&Tp, &Tz);
	if (status == 0) {
            Tp.tv_sec += Tz.tz_minuteswest * 60;	/* adjust for TZ */
	    RETVAL = Tp.tv_sec + (Tp.tv_usec / NV_1E6);
        } else {
	    RETVAL = -1.0;
	}
	OUTPUT:
	RETVAL

#    else	/* MACOS_TRADITIONAL */
void
gettimeofday()
        PREINIT:
        struct timeval Tp;
        PPCODE:
	int status;
        status = gettimeofday (&Tp, NULL);
	if (status == 0) {
	     if (GIMME == G_ARRAY) {
	         EXTEND(sp, 2);
                 PUSHs(sv_2mortal(newSViv(Tp.tv_sec)));
                 PUSHs(sv_2mortal(newSViv(Tp.tv_usec)));
             } else {
                 EXTEND(sp, 1);
                 PUSHs(sv_2mortal(newSVnv(Tp.tv_sec + (Tp.tv_usec / NV_1E6))));
             }
        }

NV
time()
        PREINIT:
        struct timeval Tp;
        CODE:
	int status;
        status = gettimeofday (&Tp, NULL);
	if (status == 0) {
            RETVAL = Tp.tv_sec + (Tp.tv_usec / NV_1E6);
	} else {
	    RETVAL = -1.0;
	}
	OUTPUT:
	RETVAL

#    endif	/* MACOS_TRADITIONAL */
#endif /* #ifdef HAS_GETTIMEOFDAY */

#if defined(HAS_GETITIMER) && defined(HAS_SETITIMER)

#define TV2NV(tv) ((NV)((tv).tv_sec) + 0.000001 * (NV)((tv).tv_usec))

void
setitimer(which, seconds, interval = 0)
	int which
	NV seconds
	NV interval
    PREINIT:
	struct itimerval newit;
	struct itimerval oldit;
    PPCODE:
	if (seconds < 0.0 || interval < 0.0)
	    croak("Time::HiRes::setitimer(%"IVdf", %"NVgf", %"NVgf"): negative time not invented yet", (IV)which, seconds, interval);
	newit.it_value.tv_sec  = (IV)seconds;
	newit.it_value.tv_usec =
	  (IV)((seconds  - (NV)newit.it_value.tv_sec)    * NV_1E6);
	newit.it_interval.tv_sec  = (IV)interval;
	newit.it_interval.tv_usec =
	  (IV)((interval - (NV)newit.it_interval.tv_sec) * NV_1E6);
        /* on some platforms the 1st arg to setitimer is an enum, which
         * causes -Wc++-compat to complain about passing an int instead
         */
#ifdef GCC_DIAG_IGNORE
        GCC_DIAG_IGNORE(-Wc++-compat);
#endif
	if (setitimer(which, &newit, &oldit) == 0) {
	  EXTEND(sp, 1);
	  PUSHs(sv_2mortal(newSVnv(TV2NV(oldit.it_value))));
	  if (GIMME == G_ARRAY) {
	    EXTEND(sp, 1);
	    PUSHs(sv_2mortal(newSVnv(TV2NV(oldit.it_interval))));
	  }
	}
#ifdef GCC_DIAG_RESTORE
        GCC_DIAG_RESTORE;
#endif

void
getitimer(which)
	int which
    PREINIT:
	struct itimerval nowit;
    PPCODE:
        /* on some platforms the 1st arg to getitimer is an enum, which
         * causes -Wc++-compat to complain about passing an int instead
         */
#ifdef GCC_DIAG_IGNORE
        GCC_DIAG_IGNORE(-Wc++-compat);
#endif
	if (getitimer(which, &nowit) == 0) {
	  EXTEND(sp, 1);
	  PUSHs(sv_2mortal(newSVnv(TV2NV(nowit.it_value))));
	  if (GIMME == G_ARRAY) {
	    EXTEND(sp, 1);
	    PUSHs(sv_2mortal(newSVnv(TV2NV(nowit.it_interval))));
	  }
	}
#ifdef GCC_DIAG_RESTORE
        GCC_DIAG_RESTORE;
#endif

#endif /* #if defined(HAS_GETITIMER) && defined(HAS_SETITIMER) */

#if defined(TIME_HIRES_CLOCK_GETTIME)

NV
clock_gettime(clock_id = CLOCK_REALTIME)
	int clock_id
    PREINIT:
	struct timespec ts;
	int status = -1;
    CODE:
#ifdef TIME_HIRES_CLOCK_GETTIME_SYSCALL
	status = syscall(SYS_clock_gettime, clock_id, &ts);
#else
	status = clock_gettime(clock_id, &ts);
#endif
	RETVAL = status == 0 ? ts.tv_sec + (NV) ts.tv_nsec / (NV) 1e9 : -1;

    OUTPUT:
	RETVAL

#else  /* if defined(TIME_HIRES_CLOCK_GETTIME) */

NV
clock_gettime(clock_id = 0)
	int clock_id
    CODE:
        croak("Time::HiRes::clock_gettime(): unimplemented in this platform");
        RETVAL = 0.0;
    OUTPUT:
	RETVAL

#endif /*  #if defined(TIME_HIRES_CLOCK_GETTIME) */

#if defined(TIME_HIRES_CLOCK_GETRES)

NV
clock_getres(clock_id = CLOCK_REALTIME)
	int clock_id
    PREINIT:
	int status = -1;
	struct timespec ts;
    CODE:
#ifdef TIME_HIRES_CLOCK_GETRES_SYSCALL
	status = syscall(SYS_clock_getres, clock_id, &ts);
#else
	status = clock_getres(clock_id, &ts);
#endif
	RETVAL = status == 0 ? ts.tv_sec + (NV) ts.tv_nsec / (NV) 1e9 : -1;

    OUTPUT:
	RETVAL

#else  /* if defined(TIME_HIRES_CLOCK_GETRES) */

NV
clock_getres(clock_id = 0)
	int clock_id
    CODE:
        croak("Time::HiRes::clock_getres(): unimplemented in this platform");
        RETVAL = 0.0;
    OUTPUT:
	RETVAL

#endif /*  #if defined(TIME_HIRES_CLOCK_GETRES) */

#if defined(TIME_HIRES_CLOCK_NANOSLEEP) && defined(TIMER_ABSTIME)

NV
clock_nanosleep(clock_id, nsec, flags = 0)
	int clock_id
	NV  nsec
	int flags
    PREINIT:
	struct timespec sleepfor, unslept;
    CODE:
	if (nsec < 0.0)
	    croak("Time::HiRes::clock_nanosleep(..., %"NVgf"): negative time not invented yet", nsec);
	sleepfor.tv_sec = (Time_t)(nsec / 1e9);
	sleepfor.tv_nsec = (long)(nsec - ((NV)sleepfor.tv_sec) * 1e9);
	if (!clock_nanosleep(clock_id, flags, &sleepfor, &unslept)) {
	    RETVAL = nsec;
	} else {
	    sleepfor.tv_sec -= unslept.tv_sec;
	    sleepfor.tv_nsec -= unslept.tv_nsec;
	    if (sleepfor.tv_nsec < 0) {
		sleepfor.tv_sec--;
		sleepfor.tv_nsec += 1000000000;
	    }
	    RETVAL = ((NV)sleepfor.tv_sec) * 1e9 + ((NV)sleepfor.tv_nsec);
	}
    OUTPUT:
	RETVAL

#else  /* if defined(TIME_HIRES_CLOCK_NANOSLEEP) && defined(TIMER_ABSTIME) */

NV
clock_nanosleep(clock_id, nsec, flags = 0)
    CODE:
        croak("Time::HiRes::clock_nanosleep(): unimplemented in this platform");
        RETVAL = 0.0;
    OUTPUT:
	RETVAL

#endif /*  #if defined(TIME_HIRES_CLOCK_NANOSLEEP) && defined(TIMER_ABSTIME) */

#if defined(TIME_HIRES_CLOCK) && defined(CLOCKS_PER_SEC)

NV
clock()
    PREINIT:
	clock_t clocks;
    CODE:
	clocks = clock();
	RETVAL = clocks == (clock_t) -1 ? (clock_t) -1 : (NV)clocks / (NV)CLOCKS_PER_SEC;

    OUTPUT:
	RETVAL

#else  /* if defined(TIME_HIRES_CLOCK) && defined(CLOCKS_PER_SEC) */

NV
clock()
    CODE:
        croak("Time::HiRes::clock(): unimplemented in this platform");
        RETVAL = 0.0;
    OUTPUT:
	RETVAL

#endif /*  #if defined(TIME_HIRES_CLOCK) && defined(CLOCKS_PER_SEC) */

void
stat(...)
PROTOTYPE: ;$
    PREINIT:
	OP fakeop;
	int nret;
    ALIAS:
	Time::HiRes::lstat = 1
    PPCODE:
	XPUSHs(sv_2mortal(newSVsv(items == 1 ? ST(0) : DEFSV)));
	PUTBACK;
	ENTER;
	PL_laststatval = -1;
	SAVEOP();
	Zero(&fakeop, 1, OP);
	fakeop.op_type = ix ? OP_LSTAT : OP_STAT;
	fakeop.op_ppaddr = PL_ppaddr[fakeop.op_type];
	fakeop.op_flags = GIMME_V == G_ARRAY ? OPf_WANT_LIST :
		GIMME_V == G_SCALAR ? OPf_WANT_SCALAR : OPf_WANT_VOID;
	PL_op = &fakeop;
	(void)fakeop.op_ppaddr(aTHX);
	SPAGAIN;
	LEAVE;
	nret = SP+1 - &ST(0);
	if (nret == 13) {
	  UV atime = SvUV(ST( 8));
	  UV mtime = SvUV(ST( 9));
	  UV ctime = SvUV(ST(10));
	  UV atime_nsec;
	  UV mtime_nsec;
	  UV ctime_nsec;
	  hrstatns(&atime_nsec, &mtime_nsec, &ctime_nsec);
	  if (atime_nsec)
	    ST( 8) = sv_2mortal(newSVnv(atime + 1e-9 * (NV) atime_nsec));
	  if (mtime_nsec)
	    ST( 9) = sv_2mortal(newSVnv(mtime + 1e-9 * (NV) mtime_nsec));
	  if (ctime_nsec)
	    ST(10) = sv_2mortal(newSVnv(ctime + 1e-9 * (NV) ctime_nsec));
	}
	XSRETURN(nret);
