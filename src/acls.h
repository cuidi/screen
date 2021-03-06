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

/***************
 *  ==> user.h
 */

/*
 * a copy buffer
 */
struct plop
{
  char *buf;
  int len;
  int enc;
};

/*
 * A User has a list of groups, and points to other users.
 * users is the User entry of the session owner (creator)
 * and anchors all other users. Add/Delete users there.
 */
typedef struct acluser
{
  struct acluser *u_next;	/* continue the main user list */
  char u_name[MAXLOGINLEN+ 1];	/* login name how he showed up */
  char *u_password;		/* his password (may be NullStr). */
  int  u_checkpassword;		/* nonzero if this u_password is valid */
  int  u_detachwin;		/* the window where he last detached */
  int  u_detachotherwin;	/* window that was "other" when he detached */
  int  u_Esc, u_MetaEsc;	/* the users screen escape character */
  struct plop u_plop;
} User;

extern int DefaultEsc, DefaultMetaEsc;

int UserFreeCopyBuffer (struct acluser *);
struct acluser **FindUserPtr (char *);
int UserAdd (char *, char *, struct acluser **);
int UserDel (char *, struct acluser **);
