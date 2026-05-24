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

#include "NetLoadModule.h"
#include <cstdlib>

#ifndef INT_MAX
#define INT_MAX 0x7fffffff
#endif

/* reorder the site list for load balancing */ 
/* using the weight and order options       */ 
void BalanceSites(void)
{
  s_Site **pOrigIter, *pOrig = GlobalData.pSites;
  s_Site **pNext = &GlobalData.pSites;

  int iLowestOrder;
  unsigned nTotalWeight;
  unsigned iChosen;

  TRACE("BalanceSites...");

  /* process all sites */ 
  while (pOrig) /* O(N^2+M*N), O(N^2/2+M*N) ave */ 
    /* M = # different orders */ 
    /* N = # sites */ 
  {
    iLowestOrder = INT_MAX;
    nTotalWeight = 0;
    /* find the set of sites with the lowest order */ 
    /* and calculate the total weight              */ 
    pOrigIter = &pOrig;
    while (*pOrigIter) /* th(N) */ 
    {
      /* found a lower order, restart total weight */ 
      if (iLowestOrder > (*pOrigIter)->iOrder)
      {
        iLowestOrder = (*pOrigIter)->iOrder;
        nTotalWeight = (*pOrigIter)->nWeight;
      }
      /* found same order, add to current total weight */ 
      else if (iLowestOrder == (*pOrigIter)->iOrder)
      {
        nTotalWeight += (*pOrigIter)->nWeight;
      }
      pOrigIter = &(*pOrigIter)->pNext;
    }

    /* pick them out randomly by weight */ 
    /* total weight will be 0 when there are no sites left */ 
    while (nTotalWeight) /* O(L*N), O(L*N/2) ave */ 
    {
      /* pick one */ 
      iChosen = MulDiv(rand(), nTotalWeight, RAND_MAX);
      /* find it */ 
      pOrigIter = &pOrig;
      while (*pOrigIter) /* O(N), O(N/2) ave */ 
      {
        /* ignore sites of higher orders (less than should not exist) */ 
        if ((*pOrigIter)->iOrder <= iLowestOrder)
        {
          if ((*pOrigIter)->nWeight > iChosen)
          {
            /* move it to the final list */ 
            (*pNext) = (*pOrigIter);
            (*pOrigIter) = (*pNext)->pNext;
            (*pNext)->pNext = NULL;
            /* adjust total weight */ 
            nTotalWeight -= (*pNext)->nWeight;

            pNext = &(*pNext)->pNext;
            break;
          }
          else
          {
            /* next */ 
            iChosen -= (*pOrigIter)->nWeight;
          }
        }
        pOrigIter = &(*pOrigIter)->pNext;
      }
    }
  }

#ifdef DOTRACE
  pOrig = GlobalData.pSites;
  TRACE("BalanceSites result:");
  while (pOrig)
  {
    TRACE(pOrig->Prefix);
    pOrig = pOrig->pNext;
  }
  TRACE("--");
#endif
}
