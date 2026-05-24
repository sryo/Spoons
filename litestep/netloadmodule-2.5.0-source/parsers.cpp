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
#include "keywords.h"

#ifndef TRACE
#define TRACE(n) (void)0
#endif



void FreeSiteProc(void *p,LPARAM lParam)
{
	s_Site *pElem = (s_Site *)p;

	delete[] pElem->Prefix;
	delete[] pElem->Suffix;
}



bool ParseSiteProc(void *p,const _TCHAR *line,LPARAM lParam)
{
	s_Site *pElem = (s_Site *)p;
	_TCHAR token[NLM_PATH_LENGTH];

	ASSERT(p!=NULL);
	ASSERT(line!=NULL);
	/* should be true by a very large amount */ 
	C_ASSERT(ARCHIVE_EXT_LEN < NLM_PATH_LENGTH);

	/* get prefix                  */ 
	if (GetToken(line,token,&line,FALSE)==FALSE)
		return false;

	pElem->PrefixLen
    = ReplaceWithDup(pElem->Prefix, token);

	/* get suffix, default to .zip */ 
	if (GetToken(line,token,&line,FALSE)==FALSE)
		_tcscpy(token,ARCHIVE_EXT);

	pElem->SuffixLen
    = ReplaceWithDup(pElem->Suffix, token);

  pElem->iOrder = 100;
  pElem->nWeight = 10000;
  while (GetToken(line,token,&line,FALSE)!=FALSE)
  {
    switch (SiteOptionKeywords(token, -1))
    {
    case -1:
      /* bHasUnrecognizedOption = true; */ 
      break;
    case SITE_ORDER:
      if (GetToken(line,token,&line,FALSE)!=FALSE)
        pElem->iOrder = atoi(token);
      break;
    case SITE_WEIGHT:
      if (GetToken(line,token,&line,FALSE)!=FALSE)
        pElem->nWeight = atoi(token);
      break;
    }
  }

	return true;
}

/*

*NetLoadModuleSiteList <URL> order <bleh> weight <bleh>

*NetLoadModule netloadmodule-x.y.z
*NetLoadModuleSite ...
*NetLoadModuleSite ...


  Does this really help?
  - can't rely on just one list, it will go out of date
  - can't check all lists?  would generate lots of traffic for one file, but not sure
  - can't only pick the lists that are needed, no way to know
  - list sites need to be more reliable than archive sites (in terms of availability
    and update speed), but:
        - less bandwidth
        - less frequent changes (ie, less effort)
        - similar number of requests (less data for each)
  - can't be publicly writable, too easy to abuse  (needs to be trustworthy)

  Allow *NetLoadModuleSiteList in list file, for forwarding?
  - would it matter?  old address would still be hit every time

*/

void FreeModuleProc(void *p,LPARAM lParam)
{
	s_Module *pElem = (s_Module *)p;

	ASSERT(p!=NULL);

	delete[] pElem->Name;
	delete[] pElem->OrigName;
	delete[] pElem->DllPath;
	delete[] pElem->PrimarySite;
	delete[] pElem->Desc;
  delete[] pElem->Error;
}



bool GetRawModuleName(_TCHAR *buffer,const _TCHAR *name)
{
	_TCHAR *ptr;
	bool fix = false;

	ASSERT(buffer!=NULL);
	ASSERT(name!=NULL);
/***** CHECK: should we always return true in case of VarExpansion? *****/
	VarExpansion(buffer,name);
	/* trim any directiories */ 
	ptr = _tcsrchr(buffer,_T('\\'));
	if (ptr) { _tcscpy(buffer,++ptr); fix = true; }
	ptr = _tcsrchr(buffer,_T('/'));
	if (ptr) { _tcscpy(buffer,++ptr); fix = true; }
	ptr = _tcsrchr(buffer,_T('.'));
	/* clear .dll extensions */ 
	if (ptr && _tcsicmp(ptr,MODULE_EXT)==0)
	{ *ptr = 0; fix = true; }

	return fix;
}

bool GetModulePath(const _TCHAR *name, size_t NameLen, _TCHAR *token, size_t buf_size, bool &bHasAlias)
{
  ASSERT(buf_size == NLM_PATH_LENGTH);

	/* use alias as path if there is one                         */  
	/* otherwise, path is ModulePath + name + .dll               */ 
	if ((bHasAlias = GetAlias(name,token,buf_size)) == false)
	{
		if (GlobalData.ModulePathLen+NameLen+MODULE_EXT_LEN >= buf_size)
		{
#ifdef DOTRACE
			/* Tell the user.  This should NEVER    */ 
			/* happen, but just in case...          */ 
			_TCHAR *ptr = new NLM_NOTHROW _TCHAR[NameLen+sizeof("Module path overflow: ")];
      if (ptr)
      {
			  sprintf(ptr,_T("Module path overflow: %s"),name);
			  TRACE(ptr);
			  delete[] ptr;
      }
      else
        TRACE(_T("Out of memory while reporting path overflow"));
#endif
      return false;
		}

		/* get path to where the module should be */ 
		_tcscpy(token,GlobalData.ModulePath);
		_tcscpy(token+GlobalData.ModulePathLen,name);
		_tcscpy(token+GlobalData.ModulePathLen+NameLen,MODULE_EXT);
	}
  return true;
}

bool ParseModuleProc(void *p, const _TCHAR *line, LPARAM lParam)
{
	s_Module *pElem = (s_Module *)p;
	_TCHAR token[NLM_PATH_LENGTH];
  const _TCHAR *linestart;

	ASSERT(p!=NULL);
	ASSERT(line!=NULL);

	if (GetToken(line, token, &line, FALSE) == FALSE)
		return false;
	/* token = module name                                       */ 
  _tcslwr(token); /* force to lower because no one rtfm */ 
	pElem->NameLen
    = ReplaceWithDup(pElem->Name, token);

  /* expand vars and */ 
	/* Clean up for any path junk they put on that we don't use. */ 
	/* (Save whining from people who don't rtfm!)                */ 
	GetRawModuleName(token, pElem->Name);

	/* may be longer because of VarExpansion  */ 
	pElem->NameLen
    = ReplaceWithDup(pElem->Name, token);

  pElem->bHasVersion = _tcschr(pElem->Name, _T('-')) != NULL;    

  /* get path, resolving any aliases */ 
  if (!GetModulePath(pElem->Name, pElem->NameLen, token, NLM_PATH_LENGTH, pElem->bHasAlias))
  {
		/* would overflow the buffer            */ 
    /* what did I mean?  what would?        */ 
		delete[] pElem->Name;
		return false;
  }

	/* save that path          */ 
  ReplaceWithDup(pElem->DllPath, token);

	/* does it exist?          */ 
	if (GetFileAttributes(token)!=INVALID_FILE_ATTRIBUTES)
		pElem->bExists = true;
	else
		/* flag for module is already set to      */ 
		/* false (zeroed) in ParseStarList        */ 
		;

  switch (lParam)
  {
  case PARSE_LOAD_MODULE: pElem->bDontLoad = false; break;
  case PARSE_INSTALL_MODULE: pElem->bDontLoad = true; break;
  }

  /* for error messages; don't include the module name */ 
  linestart = line;

	if (GetToken(line,token,&line,TRUE)!=FALSE && *token)
	{
    /* if it doesn't contain a / then it isn't a URL, so it must be an option */ 
    while(!_tcschr(token,'/'))
    {
      _tcslwr(token); /* force to lower because no one rtfm */ 
      switch(ModuleOptionKeywords(token, -1))
      {
      case -1:
        if (!pElem->Desc)
        {
          /* write an error to the module's description. */ 
		      const _TCHAR *args[4];
          TCHAR buf[NLM_PATH_LENGTH];
		      args[0] = token;
          args[1] = linestart;
		      FormatMessage(
			      FORMAT_MESSAGE_FROM_HMODULE|FORMAT_MESSAGE_ARGUMENT_ARRAY
            |FORMAT_MESSAGE_MAX_WIDTH_MASK,
			      GlobalData.hInstance, NLM_ERROR_OPTION, 0,
			      buf, NLM_PATH_LENGTH,
			      (va_list *)args);
          ReplaceWithDup(pElem->Error, buf);
        }
        return true;
      case MODULE_THREADED:
        pElem->Flags |= MODULE_THREADED; /* = 0x0001 */ 
        break;
      case MODULE_NOTPUMPED:
        pElem->Flags |= MODULE_NOTPUMPED; /* = 0x0002 */ 
        break;
      case MODULE_LOAD_SPECIFIED:
        /* get another token */ 
        if (!(GetToken(line,token,&line,TRUE)!=FALSE && *token)
          || pElem->sLoadFile!=NULL)
        {
          if (!pElem->Desc)
          {
            /* can't get token, write an error to the module's description. */ 
		        const _TCHAR *args[4];
            TCHAR buf[NLM_PATH_LENGTH];
		        args[0] = linestart;
		        FormatMessage(
			        FORMAT_MESSAGE_FROM_HMODULE|FORMAT_MESSAGE_ARGUMENT_ARRAY
              |FORMAT_MESSAGE_MAX_WIDTH_MASK,
			        GlobalData.hInstance, NLM_ERROR_OPTION_LOAD, 0,
			        buf, NLM_PATH_LENGTH,
			        (va_list *)args);
            ReplaceWithDup(pElem->Error, buf);
          }
          return true;
        }
        /* store it to the "load this file" string */ 
        ReplaceWithDup(pElem->sLoadFile, token);
        /* check it in the installer */ 
        break;
      default:
        ASSERT(CODE_UNREACHABLE);
      }
	    if (GetToken(line,token,&line,TRUE)==FALSE || !*token)
        return true;
    }
		/* token = site url(s)                    */ 
    ReplaceWithDup(pElem->PrimarySite, token);
	}

	/* save description string */ 
	if (line && *line)
	{
    ReplaceWithDup(pElem->Desc, line);
	}

	/* parsed successfully     */ 
	return true;
}


