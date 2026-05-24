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

#include <windows.h>
#include <lsapi\lsapi.h>
#include "lsmod_common.h"

#ifndef ASSERT
#define ASSERT(n) (void)0
#endif

int ParseStarList(const char *key, int keylen, ParseStarItemProc Parser,void *pList,size_t size,LPARAM lParam)
{
	FILE *f;
	char line[MAX_LINE_LENGTH];
	int i=0; // number of items successfully read and parsed
	void *elem = NULL;
	void **pnext = (void **)pList; // pointer to "next" pointer of previous list item
	const char *ptr; // pointer to the beginning of the token after the key name

	ASSERT(key!=NULL);
	ASSERT(pList!=NULL);
	ASSERT(size>=sizeof(void *));

  /* find the end of any existing list */ 
  while (*pnext)
    pnext = (void **)*pnext;

	// Read a list of items.
	f = LCOpen(NULL);
	if (f)
	{
		while (LCReadNextConfig (f, key, line, MAX_LINE_LENGTH))
		{
			// Strip off the key name.
			ptr = line+keylen;

			// If the previous item failed to parse, reuse its memory rather
			// than freeing it and reallocating it, otherwise...
			if (elem == NULL)
      {
				// create a new list element.
				elem = new NLM_NOTHROW BYTE[size];
#ifdef NLM_IGNORE_EXCEPTIONS
        /* should report the error somehow... */ 
        if (!elem)
            break;
#endif
      }
			// Zero it even if we already had it in case something was written there.
			ZeroMemory(elem,size);

			// Parse it.
			if (ptr && *ptr && Parser(elem,ptr,lParam))
			{
				// one more element successfully parsed
				++i;
				// Link it (the first item in the struct must be the next pointer)
				*pnext = elem;
				pnext = (void **)elem;
				elem = NULL; // Used it, need to allocate a new one.
			}
		}
		LCClose(f);
	}

	// If the last item failed, clean up from it.
	if (elem) delete[] elem;

	return i;
}

void FreeStarList(FreeStarItemProc Freer,void *pList,LPARAM lParam)
{
	void *elem = NULL;
	void **pnext = (void **)pList; // pointer to "next" pointer of previous list item

	while (pnext!=NULL)
	{
		elem = *pnext;
		Freer(pnext,lParam);
		delete[] pnext;
		pnext = (void **)elem;
	}
}

