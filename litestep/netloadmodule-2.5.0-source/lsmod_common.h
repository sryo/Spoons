/*
  NetLoadModule LiteStep Module - version 2.5.0

  Copyright (C) 2002 - 2005 Joshua Seagoe
 
  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.
 
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
 
  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

#ifndef NLM_IGNORE_EXCEPTIONS
#define NLM_NOTHROW
#else
//#include <new>
//#define NLM_NOTHROW (std::nothrow)
#define NLM_NOTHROW
#endif

typedef bool (*ParseStarItemProc)(void *element,const char *line,LPARAM lParam);
typedef void (*FreeStarItemProc)(void *element,LPARAM lParam);

int ParseStarList(const char *key,int keylen,ParseStarItemProc Parser,void *pList,size_t size,LPARAM lParam);
void FreeStarList(FreeStarItemProc Freer,void *pList,LPARAM lParam);
