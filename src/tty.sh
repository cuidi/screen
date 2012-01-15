#! /bin/sh
# sh tty.sh tty.c
# This inserts all the needed #ifdefs for IF{} statements
# and generates tty.c

#
# Stupid cpp on A/UX barfs on ``#if defined(FOO) && FOO < 17'' when
# FOO is undefined. Reported by Robert C. Tindall (rtindall@uidaho.edu)
#
rm -f $1
sed -e '1,26d' \
-e 's%^IF{\([^}]*\)}\(.*\)%#if defined(\1)\
\2\
#endif /* \1 */%' \
-e 's%^IFN{\([^}]*\)}\(.*\)%#if !defined(\1)\
\2\
#endif /* \1 */%' \
-e 's%^XIF{\([^}]*\)}\(.*\)%#if defined(\1)\
#if (\1 < MAXCC)\
\2\
#endif \
#endif /* \1 */%' \
 < $0 > $1
chmod -w $1
exit 0

/* Copyright (c) 2008, 2009
 *      Juergen Weigert (jnweiger@immd4.informatik.uni-erlangen.de)
 *      Michael Schroeder (mlschroe@immd4.informatik.uni-erlangen.de)
 *      Micah Cowan (micah@cowan.name)
 *      Sadrul Habib Chowdhury (sadrul@users.sourceforge.net)
 * Copyright (c) 1993-2002, 2003, 2005, 2006, 2007
 *      Juergen Weigert (jnweiger@immd4.informatik.uni-erlangen.de)
 *      Michael Schroeder (mlschroe@immd4.informatik.uni-erlangen.de)
 * Copyright (c) 1987 Oliver Laumann
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program (see the file COPYING); if not, see
 * http://www.gnu.org/licenses/, or contact Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA  02111-1301  USA
 *
 ****************************************************************
 */

/*
 * NOTICE: tty.c is automatically generated from tty.sh
 * Do not change anything here. If you then change tty.sh.
 */

#include <sys/types.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/ioctl.h>

#include "config.h"
#ifdef HAVE_STROPTS_H
#include <sys/stropts.h>	/* for I_POP */
#endif

#include "screen.h"
#include "extern.h"

static void consredir_readev_fn (struct event *, char *);

int separate_sids = 1;

static void DoSendBreak (int, int, int);
static void SigAlrmDummy (int);


/* Frank Schulz (fschulz@pyramid.com):
 * I have no idea why VSTART is not defined and my fix is probably not
 * the cleanest, but it works.
 */
#if !defined(VSTART) && defined(_VSTART)
#define VSTART _VSTART
#endif
#if !defined(VSTOP) && defined(_VSTOP)
#define VSTOP _VSTOP
#endif

#ifndef O_NOCTTY
# define O_NOCTTY 0
#endif

#ifndef TTYVMIN
# define TTYVMIN 1
#endif
#ifndef TTYVTIME
#define TTYVTIME 0
#endif


static void
SigAlrmDummy (int sigsig)
{
  debug("SigAlrmDummy()\n");
  return;
}

/*
 *  Carefully open a charcter device. Not used to open display ttys.
 *  The second parameter is parsed for a few stty style options.
 */

int
OpenTTY(line, opt)
char *line, *opt;
{
  int f;
  struct mode Mode;
  void (*sigalrm)(int);

  sigalrm = signal(SIGALRM, SigAlrmDummy);
  alarm(2);

  /* this open only succeeds, if real uid is allowed */
  if ((f = secopen(line, O_RDWR | O_NONBLOCK | O_NOCTTY, 0)) == -1)
    {
      if (errno == EINTR)
        Msg(0, "Cannot open line '%s' for R/W: open() blocked, aborted.", line);
      else
        Msg(errno, "Cannot open line '%s' for R/W", line);
      alarm(0);
      signal(SIGALRM, sigalrm);
      return -1;
    }
  if (!isatty(f))
    {
      Msg(0, "'%s' is not a tty", line);
      alarm(0);
      signal(SIGALRM, sigalrm);
      close(f);
      return -1;
    }
#if defined(I_POP) && defined(POP_TTYMODULES)
  debug("OpenTTY I_POP\n");
  while (ioctl(f, I_POP, (char *)0) >= 0)
    ;
#endif
  /*
   * We come here exclusively. This is to stop all kermit and cu type things
   * accessing the same tty line.
   * Perhaps we should better create a lock in some /usr/spool/locks directory?
   */
#ifdef TIOCEXCL
 errno = 0;
 if (ioctl(f, TIOCEXCL, (char *) 0) < 0)
   Msg(errno, "%s: ioctl TIOCEXCL failed", line);
 debug("%d %d %d\n", getuid(), geteuid(), getpid());
 debug("%s TIOCEXCL errno %d\n", line, errno);
#endif  /* TIOCEXCL */
  /*
   * We create a sane tty mode. We do not copy things from the display tty
   */
#if WE_REALLY_WANT_TO_COPY_THE_TTY_MODE
  if (display)
    {
      debug("OpenTTY: using mode of display for %s\n", line);
      Mode = D_NewMode;
    }
  else
#endif
    InitTTY(&Mode, W_TYPE_PLAIN);

  SttyMode(&Mode, opt);
#ifdef DEBUG
  DebugTTY(&Mode);
#endif
  SetTTY(f, &Mode);

#if defined(TIOCMSET)
  {
    int mcs = 0;
    ioctl(f, TIOCMGET, &mcs);
    mcs |= TIOCM_RTS;
    ioctl(f, TIOCMSET, &mcs);
  }
#endif

  brktty(f);
  alarm(0);
  signal(SIGALRM, sigalrm);
  debug("'%s' CONNECT fd=%d.\n", line, f);
  return f;
}


/*
 *  Tty mode handling
 */

void
InitTTY(m, ttyflag)
struct mode *m;
int ttyflag;
{
  memset((char *)m, 0, sizeof(*m));
  /* struct termios tio
   * defaults, as seen on SunOS 4.1.3
   */
  debug("InitTTY: POSIX: termios defaults based on SunOS 4.1.3, but better (%d)\n", ttyflag);
IF{BRKINT}	m->tio.c_iflag |= BRKINT;
IF{IGNPAR}	m->tio.c_iflag |= IGNPAR;
/* IF{ISTRIP}	m->tio.c_iflag |= ISTRIP;  may be needed, let's try. jw. */
IF{IXON}	m->tio.c_iflag |= IXON;
/* IF{IMAXBEL}	m->tio.c_iflag |= IMAXBEL; sorry, this one is ridiculus. jw */

  if (!ttyflag)	/* may not even be good for ptys.. */
    {
IF{ICRNL}	m->tio.c_iflag |= ICRNL;
IF{ONLCR}	m->tio.c_oflag |= ONLCR;
IF{TAB3}	m->tio.c_oflag |= TAB3;
IF{OXTABS}      m->tio.c_oflag |= OXTABS;
/* IF{PARENB}	m->tio.c_cflag |= PARENB;	nah! jw. */
IF{OPOST}	m->tio.c_oflag |= OPOST;
    }


/*
 * Or-ing the speed into c_cflags is dangerous.
 * It breaks on bsdi, where c_ispeed and c_ospeed are extra longs.
 *
 * IF{B9600}    m->tio.c_cflag |= B9600;
 * IF{IBSHIFT) && defined(B9600}        m->tio.c_cflag |= B9600 << IBSHIFT;
 *
 * We hope that we have the posix calls to do it right:
 * If these are not available you might try the above.
 */
IF{B9600}       cfsetospeed(&m->tio, B9600);
IF{B9600}       cfsetispeed(&m->tio, B9600);

IF{CS8} 	m->tio.c_cflag |= CS8;
IF{CREAD}	m->tio.c_cflag |= CREAD;
IF{CLOCAL}	m->tio.c_cflag |= CLOCAL;

IF{ECHOCTL}	m->tio.c_lflag |= ECHOCTL;
IF{ECHOKE}	m->tio.c_lflag |= ECHOKE;

  if (!ttyflag)
    {
IF{ISIG}	m->tio.c_lflag |= ISIG;
IF{ICANON}	m->tio.c_lflag |= ICANON;
IF{ECHO}	m->tio.c_lflag |= ECHO;
    }
IF{ECHOE}	m->tio.c_lflag |= ECHOE;
IF{ECHOK}	m->tio.c_lflag |= ECHOK;
IF{IEXTEN}	m->tio.c_lflag |= IEXTEN;

XIF{VINTR}	m->tio.c_cc[VINTR]    = Ctrl('C');
XIF{VQUIT}	m->tio.c_cc[VQUIT]    = Ctrl('\\');
XIF{VERASE}	m->tio.c_cc[VERASE]   = 0x7f; /* DEL */
XIF{VKILL}	m->tio.c_cc[VKILL]    = Ctrl('H');
XIF{VEOF}	m->tio.c_cc[VEOF]     = Ctrl('D');
XIF{VEOL}	m->tio.c_cc[VEOL]     = 0000;
XIF{VEOL2}	m->tio.c_cc[VEOL2]    = 0000;
XIF{VSWTCH}	m->tio.c_cc[VSWTCH]   = 0000;
XIF{VSTART}	m->tio.c_cc[VSTART]   = Ctrl('Q');
XIF{VSTOP}	m->tio.c_cc[VSTOP]    = Ctrl('S');
XIF{VSUSP}	m->tio.c_cc[VSUSP]    = Ctrl('Z');
XIF{VDSUSP}	m->tio.c_cc[VDSUSP]   = Ctrl('Y');
XIF{VREPRINT}	m->tio.c_cc[VREPRINT] = Ctrl('R');
XIF{VDISCARD}	m->tio.c_cc[VDISCARD] = Ctrl('O');
XIF{VWERASE}	m->tio.c_cc[VWERASE]  = Ctrl('W');
XIF{VLNEXT}	m->tio.c_cc[VLNEXT]   = Ctrl('V');
XIF{VSTATUS}	m->tio.c_cc[VSTATUS]  = Ctrl('T');

  if (ttyflag)
    {
      m->tio.c_cc[VMIN] = TTYVMIN;
      m->tio.c_cc[VTIME] = TTYVTIME;
    }

#if defined(TIOCKSET)
  m->m_jtchars.t_ascii = 'J';
  m->m_jtchars.t_kanji = 'B';
  m->m_knjmode = KM_ASCII | KM_SYSSJIS;
#endif
}

void
SetTTY(fd, mp)
int fd;
struct mode *mp;
{
  errno = 0;
  tcsetattr(fd, TCSADRAIN, &mp->tio);
#if defined(TIOCKSET)
  ioctl(fd, TIOCKSETC, &mp->m_jtchars);
  ioctl(fd, TIOCKSET, &mp->m_knjmode);
#endif
  if (errno)
    Msg(errno, "SetTTY (fd %d): ioctl failed", fd);
}

void
GetTTY(fd, mp)
int fd;
struct mode *mp;
{
  errno = 0;
  tcgetattr(fd, &mp->tio);
#if defined(TIOCKSET)
  ioctl(fd, TIOCKGETC, &mp->m_jtchars);
  ioctl(fd, TIOCKGET, &mp->m_knjmode);
#endif
  if (errno)
    Msg(errno, "GetTTY (fd %d): ioctl failed", fd);
}

/*
 * needs interrupt = iflag and flow = d->d_flow
 */
void
SetMode(op, np, flow, interrupt)
struct mode *op, *np;
int flow, interrupt;
{
  *np = *op;

  ASSERT(display);
# ifdef CYTERMIO
  np->m_mapkey = NOMAPKEY;
  np->m_mapscreen = NOMAPSCREEN;
  np->tio.c_line = 0;
# endif
IF{ICRNL}  np->tio.c_iflag &= ~ICRNL;
IF{ISTRIP}  np->tio.c_iflag &= ~ISTRIP;
IF{ONLCR}  np->tio.c_oflag &= ~ONLCR;
  np->tio.c_lflag &= ~(ICANON | ECHO);
  /*
   * From Andrew Myers (andru@tonic.lcs.mit.edu)
   * to avoid ^V^V-Problem on OSF1
   */
IF{IEXTEN}  np->tio.c_lflag &= ~IEXTEN;

  /*
   * Unfortunately, the master process never will get SIGINT if the real
   * terminal is different from the one on which it was originaly started
   * (process group membership has not been restored or the new tty could not
   * be made controlling again). In my solution, it is the attacher who
   * receives SIGINT (because it is always correctly associated with the real
   * tty) and forwards it to the master [kill(MasterPid, SIGINT)].
   * Marc Boucher (marc@CAM.ORG)
   */
  if (interrupt)
    np->tio.c_lflag |= ISIG;
  else
    np->tio.c_lflag &= ~ISIG;
  /*
   * careful, careful catche monkey..
   * never set VMIN and VTIME to zero, if you want blocking io.
   *
   * We may want to do a VMIN > 0, VTIME > 0 read on the ptys too, to
   * reduce interrupt frequency.  But then we would not know how to
   * handle read returning 0. jw.
   */
  np->tio.c_cc[VMIN] = 1;
  np->tio.c_cc[VTIME] = 0;
  if (!interrupt || !flow)
    np->tio.c_cc[VINTR] = VDISABLE;
  np->tio.c_cc[VQUIT] = VDISABLE;
  if (flow == 0)
    {
XIF{VSTART}	np->tio.c_cc[VSTART] = VDISABLE;
XIF{VSTOP}	np->tio.c_cc[VSTOP] = VDISABLE;
      np->tio.c_iflag &= ~IXON;
    }
XIF{VDISCARD}	np->tio.c_cc[VDISCARD] = VDISABLE;
XIF{VLNEXT}	np->tio.c_cc[VLNEXT] = VDISABLE;
XIF{VSTATUS}	np->tio.c_cc[VSTATUS] = VDISABLE;
XIF{VSUSP}	np->tio.c_cc[VSUSP] = VDISABLE;
 /* Set VERASE to DEL, rather than VDISABLE, to avoid libvte
    "autodetect" issues. */
XIF{VERASE}	np->tio.c_cc[VERASE] = 0x7f;
XIF{VKILL}	np->tio.c_cc[VKILL] = VDISABLE;
XIF{VDSUSP}	np->tio.c_cc[VDSUSP] = VDISABLE;
XIF{VREPRINT}	np->tio.c_cc[VREPRINT] = VDISABLE;
XIF{VWERASE}	np->tio.c_cc[VWERASE] = VDISABLE;
}

/* operates on display */
void
SetFlow(on)
int on;
{
  ASSERT(display);
  if (D_flow == on)
    return;
  if (on)
    {
      D_NewMode.tio.c_cc[VINTR] = iflag ? D_OldMode.tio.c_cc[VINTR] : VDISABLE;
XIF{VSTART}	D_NewMode.tio.c_cc[VSTART] = D_OldMode.tio.c_cc[VSTART];
XIF{VSTOP}	D_NewMode.tio.c_cc[VSTOP] = D_OldMode.tio.c_cc[VSTOP];
      D_NewMode.tio.c_iflag |= D_OldMode.tio.c_iflag & IXON;
    }
  else
    {
      D_NewMode.tio.c_cc[VINTR] = VDISABLE;
XIF{VSTART}	D_NewMode.tio.c_cc[VSTART] = VDISABLE;
XIF{VSTOP}	D_NewMode.tio.c_cc[VSTOP] = VDISABLE;
      D_NewMode.tio.c_iflag &= ~IXON;
    }
#  ifdef TCOON
  if (!on)
    tcflow(D_userfd, TCOON);
#  endif
  if (tcsetattr(D_userfd, TCSANOW, &D_NewMode.tio))
    debug("SetFlow: ioctl errno %d\n", errno);
  D_flow = on;
}

/* parse commands from opt and modify m */
int
SttyMode(m, opt)
struct mode *m;
char *opt;
{
  static const char sep[] = " \t:;,";

  if (!opt)
    return 0;

  while (*opt)
    {
      while (strchr(sep, *opt)) opt++;
      if (*opt >= '0' && *opt <= '9')
        {
	  if (SetBaud(m, atoi(opt), atoi(opt)))
	    return -1;
	}
      else if (!strncmp("cs7", opt, 3))
        {
	  m->tio.c_cflag &= ~CSIZE;
	  m->tio.c_cflag |= CS7;
	}
      else if (!strncmp("cs8", opt, 3))
	{
	  m->tio.c_cflag &= ~CSIZE;
	  m->tio.c_cflag |= CS8;
	}
      else if (!strncmp("istrip", opt, 6))
	{
	  m->tio.c_iflag |= ISTRIP;
        }
      else if (!strncmp("-istrip", opt, 7))
	{
	  m->tio.c_iflag &= ~ISTRIP;
        }
      else if (!strncmp("ixon", opt, 4))
	{
	  m->tio.c_iflag |= IXON;
        }
      else if (!strncmp("-ixon", opt, 5))
	{
	  m->tio.c_iflag &= ~IXON;
        }
      else if (!strncmp("ixoff", opt, 5))
	{
	  m->tio.c_iflag |= IXOFF;
        }
      else if (!strncmp("-ixoff", opt, 6))
	{
	  m->tio.c_iflag &= ~IXOFF;
        }
      else if (!strncmp("crtscts", opt, 7))
	{
#if (defined(POSIX) || defined(TERMIO)) && defined(CRTSCTS)
	  m->tio.c_cflag |= CRTSCTS;
#endif
	}
      else if (!strncmp("-crtscts", opt, 8))
        {
#if (defined(POSIX) || defined(TERMIO)) && defined(CRTSCTS)
	  m->tio.c_cflag &= ~CRTSCTS;
#endif
	}
      else
        return -1;
      while (*opt && !strchr(sep, *opt)) opt++;
    }
  return 0;
}

/*
 *  Job control handling
 *
 *  Somehow the ultrix session handling is broken, so use
 *  the bsdish variant.
 */

/*ARGSUSED*/
void
brktty(fd)
int fd;
{
  if (separate_sids)
    setsid();		/* will break terminal affiliation */
}

int
fgtty(fd)
int fd;
{
#ifdef BSDJOBS
  int mypid;

  mypid = getpid();

  /* The next lines should be obsolete. Can anybody check if they
   * are really needed on the BSD platforms?
   *
   * this is to avoid the message:
   *	fgtty: Not a typewriter (25)
   */

  if (separate_sids)
    if (tcsetpgrp(fd, mypid))
      {
        debug("fgtty: tcsetpgrp: %d\n", errno);
        return -1;
      }
#endif /* BSDJOBS */
  return 0;
}

/*
 * The alm boards on our sparc center 1000 have a lousy driver.
 * We cannot generate long breaks unless we use the most ugly form
 * of ioctls. jw.
 */
int breaktype = 2;

/*
 * type:
 *  0:	TIOCSBRK / TIOCCBRK
 *  1:	TCSBRK
 *  2:	tcsendbreak()
 * n: approximate duration in 1/4 seconds.
 */
static void
DoSendBreak(fd, n, type)
int fd, n, type;
{
  switch (type)
    {
    case 2:	/* tcsendbreak() =============================== */
# ifdef HAVE_SUPER_TCSENDBREAK
      /* There is one rare case that I have tested, where tcsendbreak works
       * really great: this was an alm driver that came with SunOS 4.1.3
       * If you have this one, define the above symbol.
       * here we can use the second parameter to specify the duration.
       */
      debug("tcsendbreak(fd=%d, %d)\n", fd, n);
      if (tcsendbreak(fd, n) < 0)
        Msg(errno, "cannot send BREAK (tcsendbreak)");
# else
      /*
       * here we hope, that multiple calls to tcsendbreak() can
       * be concatenated to form a long break, as we do not know
       * what exact interpretation the second parameter has:
       *
       * - sunos 4: duration in quarter seconds
       * - sunos 5: 0 a short break, nonzero a tcdrain()
       * - hpux, irix: ignored
       * - mot88: duration in milliseconds
       * - aix: duration in milliseconds, but 0 is 25 milliseconds.
       */
      debug("%d * tcsendbreak(fd=%d, 0)\n", n, fd);
	{
	  int i;

	  if (!n)
	    n++;
	  for (i = 0; i < n; i++)
	    if (tcsendbreak(fd, 0) < 0)
	      {
		Msg(errno, "cannot send BREAK (tcsendbreak SVR4)");
		return;
	      }
	}
# endif
      break;

    case 1:	/* TCSBRK ======================================= */
#ifdef TCSBRK
      if (!n)
        n++;
      /*
       * Here too, we assume that short breaks can be concatenated to
       * perform long breaks. But for SOLARIS, this is not true, of course.
       */
      debug("%d * TCSBRK fd=%d\n", n, fd);
	{
	  int i;

	  for (i = 0; i < n; i++)
	    if (ioctl(fd, TCSBRK, (char *)0) < 0)
	      {
		Msg(errno, "Cannot send BREAK (TCSBRK)");
		return;
	      }
	}
#else /* TCSBRK */
      Msg(0, "TCSBRK not available, change breaktype");
#endif /* TCSBRK */
      break;

    case 0:	/* TIOCSBRK / TIOCCBRK ========================== */
#if defined(TIOCSBRK) && defined(TIOCCBRK)
      /*
       * This is very rude. Screen actively celebrates the break.
       * But it may be the only save way to issue long breaks.
       */
      debug("TIOCSBRK TIOCCBRK\n");
      if (ioctl(fd, TIOCSBRK, (char *)0) < 0)
        {
	  Msg(errno, "Can't send BREAK (TIOCSBRK)");
	  return;
	}
      sleep1000(n ? n * 250 : 250);
      if (ioctl(fd, TIOCCBRK, (char *)0) < 0)
        {
	  Msg(errno, "BREAK stuck!!! -- HELP! (TIOCCBRK)");
	  return;
	}
#else /* TIOCSBRK && TIOCCBRK */
      Msg(0, "TIOCSBRK/CBRK not available, change breaktype");
#endif /* TIOCSBRK && TIOCCBRK */
      break;

    default:	/* unknown ========================== */
      Msg(0, "Internal SendBreak error: method %d unknown", type);
    }
}

/*
 * Send a break for n * 0.25 seconds. Tty must be PLAIN.
 * The longest possible break allowed here is 15 seconds.
 */

void
SendBreak(wp, n, closeopen)
struct win *wp;
int n, closeopen;
{
  void (*sigalrm)(int);

  if (wp->w_type != W_TYPE_PLAIN)
    return;

  debug("break(%d, %d) fd %d\n", n, closeopen, wp->w_ptyfd);

  (void) tcflush(wp->w_ptyfd, TCIOFLUSH);

  if (closeopen)
    {
      close(wp->w_ptyfd);
      sleep1000(n ? n * 250 : 250);
      if ((wp->w_ptyfd = OpenTTY(wp->w_tty, wp->w_cmdargs[1])) < 1)
	{
	  Msg(0, "Ouch, cannot reopen line %s, please try harder", wp->w_tty);
	  return;
	}
      (void) fcntl(wp->w_ptyfd, F_SETFL, FNBLOCK);
    }
  else
    {
      sigalrm = signal(SIGALRM, SigAlrmDummy);
      alarm(15);

      DoSendBreak(wp->w_ptyfd, n, breaktype);

      alarm(0);
      signal(SIGALRM, sigalrm);
    }
  debug("            broken.\n");
}

/*
 *  Console grabbing
 */

static struct event consredir_ev;
static int consredirfd[2] = {-1, -1};

static void
consredir_readev_fn(ev, data)
struct event *ev;
char *data;
{
  char *p, *n, buf[256];
  int l;

  if (!console_window || (l = read(consredirfd[0], buf, sizeof(buf))) <= 0)
    {
      close(consredirfd[0]);
      close(consredirfd[1]);
      consredirfd[0] = consredirfd[1] = -1;
      evdeq(ev);
      return;
    }
  for (p = n = buf; l > 0; n++, l--)
    if (*n == '\n')
      {
        if (n > p)
	  WriteString(console_window, p, n - p);
        WriteString(console_window, "\r\n", 2);
        p = n + 1;
      }
  if (n > p)
    WriteString(console_window, p, n - p);
}

/*ARGSUSED*/
int
TtyGrabConsole(fd, on, rc_name)
int fd, on;
char *rc_name;
{
  struct display *d;
#  ifdef SRIOCSREDIR
  int cfd;
#  else
  struct mode new1, new2;
  char *slave;
#  endif

  if (on > 0)
    {
      if (displays == 0)
	{
	  Msg(0, "I need a display");
	  return -1;
	}
      for (d = displays; d; d = d->d_next)
	if (strcmp(d->d_usertty, "/dev/console") == 0)
	  break;
      if (d)
	{
	  Msg(0, "too dangerous - screen is running on /dev/console");
	  return -1;
	}
    }
  if (consredirfd[0] >= 0)
    {
      evdeq(&consredir_ev);
      close(consredirfd[0]);
      close(consredirfd[1]);
      consredirfd[0] = consredirfd[1] = -1;
    }
  if (on <= 0)
    return 0;
#  ifdef SRIOCSREDIR
  if ((cfd = secopen("/dev/console", O_RDWR|O_NOCTTY, 0)) == -1)
    {
      Msg(errno, "/dev/console");
      return -1;
    }
  if (pipe(consredirfd))
    {
      Msg(errno, "pipe");
      close(cfd);
      consredirfd[0] = consredirfd[1] = -1;
      return -1;
    }
  if (ioctl(cfd, SRIOCSREDIR, consredirfd[1]))
    {
      Msg(errno, "SRIOCSREDIR ioctl");
      close(cfd);
      close(consredirfd[0]);
      close(consredirfd[1]);
      consredirfd[0] = consredirfd[1] = -1;
      return -1;
    }
  close(cfd);
#  else
  /* special linux workaround for a too restrictive kernel */
  if ((consredirfd[0] = OpenPTY(&slave)) < 0)
    {
      Msg(errno, "%s: could not open detach pty master", rc_name);
      return -1;
    }
  if ((consredirfd[1] = open(slave, O_RDWR | O_NOCTTY)) < 0)
    {
      Msg(errno, "%s: could not open detach pty slave", rc_name);
      close(consredirfd[0]);
      return -1;
    }
  InitTTY(&new1, 0);
  SetMode(&new1, &new2, 0, 0);
  SetTTY(consredirfd[1], &new2);
  if (UserContext() == 1)
    UserReturn(ioctl(consredirfd[1], TIOCCONS, (char *)&on));
  if (UserStatus())
    {
      Msg(errno, "%s: ioctl TIOCCONS failed", rc_name);
      close(consredirfd[0]);
      close(consredirfd[1]);
      return -1;
    }
#  endif
  consredir_ev.fd = consredirfd[0];
  consredir_ev.type = EV_READ;
  consredir_ev.handler = consredir_readev_fn;
  evenq(&consredir_ev);
  return 0;
}

/*
 * Read modem control lines of a physical tty and write them to buf
 * in a readable format.
 * Will not write more than 256 characters to buf.
 * Returns buf;
 */
char *
TtyGetModemStatus(fd, buf)
int fd;
char *buf;
{
  char *p = buf;
#ifdef TIOCGSOFTCAR
  unsigned int softcar;
#endif
#if defined(TIOCMGET) || defined(TIOCMODG)
  unsigned int mflags;
#else
# ifdef MCGETA
  /* this is yet another interface, found on hpux. grrr */
  mflag mflags;
IF{MDTR}#  define TIOCM_DTR MDTR
IF{MRTS}#  define TIOCM_RTS MRTS
IF{MDSR}#  define TIOCM_DSR MDSR
IF{MDCD}#  define TIOCM_CAR MDCD
IF{MRI}#  define TIOCM_RNG MRI
IF{MCTS}#  define TIOCM_CTS MCTS
# endif
#endif
#if defined(CLOCAL) || defined(CRTSCTS)
  struct mode mtio;	/* screen.h */
#endif
#if defined(CRTSCTS) || defined(TIOCM_CTS)
  int rtscts;
#endif
  int clocal;

#if defined(CLOCAL) || defined(CRTSCTS)
  GetTTY(fd, &mtio);
#endif
  clocal = 0;
#ifdef CLOCAL
  if (mtio.tio.c_cflag & CLOCAL)
    {
      clocal = 1;
      *p++ = '{';
    }
#endif

#ifdef TIOCM_CTS
# ifdef CRTSCTS
  if (!(mtio.tio.c_cflag & CRTSCTS))
    rtscts = 0;
  else
# endif /* CRTSCTS */
    rtscts = 1;
#endif /* TIOCM_CTS */

#ifdef TIOCGSOFTCAR
  if (ioctl(fd, TIOCGSOFTCAR, (char *)&softcar) < 0)
    softcar = 0;
#endif

#if defined(TIOCMGET) || defined(TIOCMODG) || defined(MCGETA)
# ifdef TIOCMGET
  if (ioctl(fd, TIOCMGET, (char *)&mflags) < 0)
# else
#  ifdef TIOCMODG
  if (ioctl(fd, TIOCMODG, (char *)&mflags) < 0)
#  else
  if (ioctl(fd, MCGETA, &mflags) < 0)
#  endif
# endif
    {
#ifdef TIOCGSOFTCAR
      sprintf(p, "NO-TTY? %s", softcar ? "(CD)" : "CD");
#else
      sprintf(p, "NO-TTY?");
#endif
      p += strlen(p);
    }
  else
    {
      char *s;
# ifdef FANCY_MODEM
#  ifdef TIOCM_LE
      if (!(mflags & TIOCM_LE))
        for (s = "!LE "; *s; *p++ = *s++);
#  endif
# endif /* FANCY_MODEM */

# ifdef TIOCM_RTS
      s = "!RTS "; if (mflags & TIOCM_RTS) s++;
      while (*s) *p++ = *s++;
# endif
# ifdef TIOCM_CTS
      s = "!CTS ";
      if (!rtscts)
        {
          *p++ = '(';
          s = "!CTS) ";
	}
      if (mflags & TIOCM_CTS) s++;
      while (*s) *p++ = *s++;
# endif

# ifdef TIOCM_DTR
      s = "!DTR "; if (mflags & TIOCM_DTR) s++;
      while (*s) *p++ = *s++;
# endif
# ifdef TIOCM_DSR
      s = "!DSR "; if (mflags & TIOCM_DSR) s++;
      while (*s) *p++ = *s++;
# endif
# if defined(TIOCM_CD) || defined(TIOCM_CAR)
      s = "!CD ";
#  ifdef TIOCGSOFTCAR
      if (softcar)
	 {
	  *p++ = '(';
	  s = "!CD) ";
	 }
#  endif
#  ifdef TIOCM_CD
      if (mflags & TIOCM_CD) s++;
#  else
      if (mflags & TIOCM_CAR) s++;
#  endif
      while (*s) *p++ = *s++;
# endif
# if defined(TIOCM_RI) || defined(TIOCM_RNG)
#  ifdef TIOCM_RI
      if (mflags & TIOCM_RI)
#  else
      if (mflags & TIOCM_RNG)
#  endif
	for (s = "RI "; *s; *p++ = *s++);
# endif
# ifdef FANCY_MODEM
#  ifdef TIOCM_ST
      s = "!ST "; if (mflags & TIOCM_ST) s++;
      while (*s) *p++ = *s++;
#  endif
#  ifdef TIOCM_SR
      s = "!SR "; if (mflags & TIOCM_SR) s++;
      while (*s) *p++ = *s++;
#  endif
# endif /* FANCY_MODEM */
      if (p > buf && p[-1] == ' ')
        p--;
      *p = '\0';
    }
#else
# ifdef TIOCGSOFTCAR
  sprintf(p, " %s", softcar ? "(CD)", "CD");
  p += strlen(p);
# endif
#endif
  if (clocal)
    *p++ = '}';
  *p = '\0';
  return buf;
}

/*
 * On hpux, idx and sym will be different.
 * Rumor has it that, we need idx in D_dospeed to make tputs
 * padding correct.
 * Frequently used entries come first.
 */
static struct baud_values btable[] =
{
IF{B9600}	{	13,	9600,	B9600	},
IF{B19200}	{	14,	19200,	B19200	},
IF{EXTA}	{	14,	19200,	EXTA	},
IF{B38400}	{	15,	38400,	B38400	},
IF{EXTB}	{	15,	38400,	EXTB	},
IF{B57600}	{	16,	57600,	B57600	},
IF{B115200}	{	17,	115200,	B115200	},
IF{B230400}	{	18,	230400,	B230400	},
IF{B460800}	{	19,	460800,	B460800	},
IF{B7200}	{	13,	7200,	B7200	},
IF{B4800}	{	12,	4800,	B4800	},
IF{B3600}	{	12,	3600,	B3600	},
IF{B2400}	{	11,	2400,	B2400	},
IF{B1800}	{	10,	1800,	B1800	},
IF{B1200}	{	9,	1200,	B1200	},
IF{B900} 	{	9,	900,	B900	},
IF{B600} 	{	8,	600,	B600	},
IF{B300} 	{	7,	300, 	B300	},
IF{B200} 	{	6,	200, 	B200	},
IF{B150} 	{	5,	150,	B150	},
IF{B134} 	{	4,	134,	B134	},
IF{B110} 	{	3,	110,	B110	},
IF{B75}  	{	2,	75,	B75	},
IF{B50}  	{	1,	50,	B50	},
IF{B0}   	{	0,	0,	B0	},
		{	-1,	-1,	-1	}
};

/*
 * baud may either be a bits-per-second value or a symbolic
 * value as returned by cfget?speed()
 */
struct baud_values *
lookup_baud(baud)
int baud;
{
  struct baud_values *p;

  for (p = btable; p->idx >= 0; p++)
    if (baud == p->bps || baud == p->sym)
      return p;
  return NULL;
}

/*
 * change the baud rate in a mode structure.
 * ibaud and obaud are given in bit/second, or at your option as
 * termio B... symbols as defined in e.g. suns sys/ttydev.h
 * -1 means don't change.
 */
int
SetBaud(m, ibaud, obaud)
struct mode *m;
int ibaud, obaud;
{
  struct baud_values *ip, *op;

  if ((!(ip = lookup_baud(ibaud)) && ibaud != -1) ||
      (!(op = lookup_baud(obaud)) && obaud != -1))
    return -1;

  if (ip) cfsetispeed(&m->tio, ip->sym);
  if (op) cfsetospeed(&m->tio, op->sym);
  return 0;
}

int
CheckTtyname (tty)
char *tty;
{
  struct stat st;

  if (lstat(tty, &st) || !S_ISCHR(st.st_mode) ||
     (st.st_nlink > 1 && strncmp(tty, "/dev/", 5)))
    return -1;
  return 0;
}

/*
 *  Write out the mode struct in a readable form
 */

#ifdef DEBUG
void
DebugTTY(m)
struct mode *m;
{
  int i;

  debug("struct termios tio:\n");
  debug("c_iflag = %#x\n", (unsigned int)m->tio.c_iflag);
  debug("c_oflag = %#x\n", (unsigned int)m->tio.c_oflag);
  debug("c_cflag = %#x\n", (unsigned int)m->tio.c_cflag);
  debug("c_lflag = %#x\n", (unsigned int)m->tio.c_lflag);
  debug("cfgetospeed() = %d\n", (int)cfgetospeed(&m->tio));
  debug("cfgetispeed() = %d\n", (int)cfgetispeed(&m->tio));
  for (i = 0; i < sizeof(m->tio.c_cc)/sizeof(*m->tio.c_cc); i++)
    {
      debug("c_cc[%d] = %#x\n", i, m->tio.c_cc[i]);
    }
}
#endif /* DEBUG */
