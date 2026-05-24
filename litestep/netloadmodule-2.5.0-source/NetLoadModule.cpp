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

// Remember to fix the include paths and link with lsapi.lib

#include "NetLoadModule.h"

#define LS_SUCCESS 0
#define LS_ERROR   1

extern "C" {
__declspec( dllexport ) int initModuleEx(HWND parent, HINSTANCE dll, LPCSTR szPath);
__declspec( dllexport ) int quitModule(HINSTANCE dll);
}

s_GlobalData GlobalData;



/* actual parsers are in parsers.cpp and lsmod_common.cpp */ 
void FreeSiteProc(void *p,LPARAM);
bool ParseSiteProc(void *p,const _TCHAR *line,LPARAM);
void FreeModuleProc(void *p,LPARAM);

inline int ParseSites(void)
{
	return (GlobalData.nSites =
		ParseStarList(CONF_SITE,CONF_SITE_LEN,ParseSiteProc,&GlobalData.pSites,sizeof(s_Site),NULL));
}

inline void FreeSites(void)
{
	FreeStarList(FreeSiteProc,GlobalData.pSites,NULL);
}

inline s_Module *ParseModules(void)
{
  s_Module *pMod = NULL;

  ParseStarList(CONF_MODULE, CONF_MODULE_LEN,
    ParseModuleProc,&pMod, sizeof(s_Module),
    PARSE_LOAD_MODULE);

  ParseStarList(CONF_INSTALL, CONF_INSTALL_LEN,
    ParseModuleProc,&pMod, sizeof(s_Module),
    PARSE_INSTALL_MODULE);

  return pMod;
}

inline void FreeModules(s_Module *pMod)
{
	FreeStarList(FreeModuleProc,pMod,NULL);
}

//

void SetModuleError(s_Module *pMod, UINT uID)
{
  const unsigned ARBITRARY_SHORT_CONSTANT = 200;
  _TCHAR buffer[ARBITRARY_SHORT_CONSTANT];
  LoadString(GlobalData.hInstance, uID, buffer, sizeof(buffer)/sizeof(*buffer));
  /* TODO: make sure this succeeds */ 
  ReplaceWithDup(pMod->Error, buffer);
}


/*
      InstallModules

  Not to be confused with InstallModule.
  Make sure all of the modules are installed.
  This will do nothing if all of the modules
  are already here.
*/
bool InstallModules(s_Module *pMod)
{
  /* do we need to install anything? */ 
  bool bSkipInstall = !GlobalData.bTestMessage;
  s_Module *p = pMod;
  while (p && bSkipInstall)
  {
    if (!p->bExists)
      bSkipInstall = false;
    p = p->pNext;
  }

  /* nope, can't fail not installing */ 
  if (bSkipInstall)
    return true;

  /* this stuff only needs to be done once */ 
  if (!GlobalData.bDownloadInitDone)
  {
		ParseSites();

		if (GlobalData.nSites<1)
		{
      _TCHAR message[NLM_PATH_LENGTH];
	    LoadString(GlobalData.hInstance,IDS_NODOWNLOADSITES,message,NLM_PATH_LENGTH);
			MessageBox(NULL, message, TITLE, ERROR_MESSAGE_FLAGS);
		}
		else if (GlobalData.nSites>1)
		{
			BalanceSites();
		}

    GlobalData.pNextSite = GlobalData.pSites;

	  INITCOMMONCONTROLSEX cc;
	  cc.dwSize = sizeof(cc);
	  cc.dwICC = ICC_LISTVIEW_CLASSES|ICC_PROGRESS_CLASS;
		if (!InitCommonControlsEx(&cc))
    {
      TRACE("Unable to initialize common controls.");
    }

    GlobalData.bDownloadInitDone = true;
  }

	/* bring up the "modules not found" dialog box  */ 
  s_DownloadState State;
  ZeroMemory(&State, sizeof(State));
  State.pModuleList = pMod;

	DialogBoxParam(GlobalData.hInstance, MAKEINTRESOURCE(IDD_MODULE_LIST),
    NULL, ModListDlgProc, reinterpret_cast<LPARAM>(&State));

  return State.bAnyFail;
}

/*
			LoadModules

	Loop through all the modules, sending a
	LM_RELOADMODULE message to litestep to 
	load each one.
*/
bool LoadModules(s_Module *pMod)
{
  bool bAnyFailLoad = false;

	while (pMod)
	{
		ASSERT(pMod->DllPath!=NULL);

		if (!pMod->bDontLoad)
    {
      if (pMod->bExists)
      {
#ifndef NLM_IGNORE_EXCEPTIONS
#ifdef _MSC_VER
        __try
#else
        try
#endif
#endif
        {
			    SendMessage(GlobalData.hLiteStepWnd,
            LM_RELOADMODULE,
            (WPARAM)pMod->DllPath,
            (LPARAM)pMod->Flags);
        }
#ifndef NLM_IGNORE_EXCEPTIONS
#ifdef _MSC_VER
        __except (EXCEPTION_EXECUTE_HANDLER)
#else
        catch (...)
#endif
        {
          /* we should never get this, as the core has its own try/catch block     */ 
          /* but just in case, I'd rather not be blamed for other modules' failing */ 
          SetModuleError(pMod, IDS_EXCEPTION_WHILE_LOADING);
          bAnyFailLoad = true;
        }
#endif
      }
      else
        bAnyFailLoad = true;
    }

		pMod = pMod->pNext;
	}

  return !bAnyFailLoad;
}

/*
      SetModuleVars

  This provides $vars$ for each module, set to
  the full path to the dll, so that the module
  can be found to load with lsbox, etc.  The
  var names are formed by chopping off the
  version, ie everything after the first - in
  the name.
*/
void SetModuleVars(s_Module *pMod)
{
  _TCHAR buffer[NLM_PATH_LENGTH];
  _TCHAR *end;

  _tcscpy(buffer, VAR_PATHTO_PREFIX);
  _TCHAR * const suffix = buffer + VAR_PATHTO_PREFIX_LEN;

  while (pMod)
  {
    if (pMod->OrigName)
      _tcscpy(suffix, pMod->OrigName);
    else
      _tcscpy(suffix, pMod->Name);

    end = _tcschr(buffer, _T('-'));
    if (end!=NULL) *end = 0;

    LSSetVariable(buffer, pMod->DllPath);

    pMod = pMod->pNext;
  }
}

/*
      ProcessModuleList

  This installs, loads, and frees the module
  list created by ParseModules at startup or
  any time later by bang commands.
*/
bool ProcessModuleList(s_Module *pMod)
{
  bool bInstallOK = true, bLoadOK = true;
  
  if (!GlobalData.bNoDownloadStep || !GlobalData.bNoInstallStep)
    bInstallOK = InstallModules(pMod);

  SetModuleVars(pMod);

  if (!GlobalData.bNoLoadStep)
	  bLoadOK = LoadModules(pMod);

	FreeModules(pMod);

  /* unload URLMON.DLL if we loaded it */ 
  /* do this after loading other modules, so it doesn't unload/reload it if another module needs it */ 
  UnloadDownloadProcs();

  return bLoadOK && bInstallOK;
}

/*
    Utility function to safely replace a string with a
    copy of another string.  Equivalent to _tcsdup, but
    using new/delete and with some extra logic for swapping.

    returns # of _TCHARs copied on success
    returns 0 if out of memory (or if copied empty string)
*/
size_t ReplaceWithDup(_TCHAR *&dest, const _TCHAR *src)
{
  const size_t cch = _tcslen(src);
  ASSERT(cch < (1 << 30)); /* arbitrary size check for sanity */ 

  /* get some space */ 
  _TCHAR *p = new NLM_NOTHROW _TCHAR[cch + 1];
#ifdef NLM_IGNORE_EXCEPTIONS
  if (!p)
    return 0; /* didn't replace it */ 
#endif

  /* copy the string */ 
  _tcscpy(p, src);

  /* swap */ 
  _TCHAR *old = dest;
  dest = p;

  /* junk the old one */ 
  delete[] old;

  return cch;
}



/*
		initModuleEx

*/
int initModuleEx(HWND parent, HINSTANCE dll, LPCSTR szPath)
{
	TRACE(TITLE);
	START_TRACE;

	/* initialize all global data to zero     */ 
	/* this makes sure all pointers are NULL  */ 
	/* and all bools are false                */ 
  /* technically it's not portable, but meh */ 
	ZeroMemory(&GlobalData,sizeof(s_GlobalData));

	GlobalData.hInstance = dll;
	GlobalData.hLiteStepWnd = GetLitestepWnd();

	_TCHAR buffer[NLM_PATH_LENGTH];

	/* get litestep path                      */ 
	if (!GetRCString(CONF_LITESTEPDIR,buffer,"",NLM_PATH_LENGTH))
	{
		TRACE("GetRCString(LiteStepDir) failed");
		VarExpansion(buffer,PATH_LITESTEPDIR);
	}
  /* TODO: make sure this succeeds */ 
  GlobalData.LiteStepPathLen
   = ReplaceWithDup(GlobalData.LiteStepPath, buffer);

	/* get global alias list                  */ 
	if (!GetRCString(CONF_ALIASFILE,buffer,"",NLM_PATH_LENGTH))
	{
		if (GlobalData.LiteStepPathLen+PATH_ALIASFILE_LEN < NLM_PATH_LENGTH)
		{
			_tcscpy(buffer,GlobalData.LiteStepPath);
			_tcscpy(buffer+GlobalData.LiteStepPathLen,PATH_ALIASFILE);
		}
		else
		{
			/* paths aren't allowed to be this long, */ 
			/* so it will never happen               */ 
			ASSERT(0);
			TRACE("Alias file path overflow.");
		}
	}
  ReplaceWithDup(GlobalData.AliasFile, buffer);

	/* read the module path                   */ 
	if (!GetRCString(CONF_MODULEDIR,buffer,"",NLM_PATH_LENGTH))
	{
		if (GlobalData.LiteStepPathLen+PATH_MODULEDIR_LEN < NLM_PATH_LENGTH)
		{
			_tcscpy(buffer,GlobalData.LiteStepPath);
			_tcscpy(buffer+GlobalData.LiteStepPathLen,PATH_MODULEDIR);
		}
		else
		{
			/* paths aren't allowed to be this long, */ 
			/* so it will never happen               */ 
			ASSERT(0);
			TRACE("Module path overflow.");
		}
	}
	if (!*buffer) return LS_ERROR; /* must have a module dir */ 

	GlobalData.ModulePathLen
    = ReplaceWithDup(GlobalData.ModulePath, buffer);
	/* create dir if it's not there  */ 
	CreateDirectory(GlobalData.ModulePath,NULL);

	/* read the documentation path            */ 
	if (!GetRCString(CONF_DOCDIR,buffer,"",NLM_PATH_LENGTH))
	{
		if (GlobalData.ModulePathLen+PATH_DOCDIR_LEN < NLM_PATH_LENGTH)
		{
			_tcscpy(buffer,GlobalData.ModulePath);
			_tcscpy(buffer+GlobalData.ModulePathLen,PATH_DOCDIR);
		}
		else
		{
			/* paths aren't allowed to be this long, */ 
			/* so it will never happen               */ 
			ASSERT(0);
			TRACE("Doc path overflow.");
		}
	}
	/* empty path = don't store documentation */ 
	if (*buffer)
	{
		GlobalData.DocPathLen
      = ReplaceWithDup(GlobalData.DocPath, buffer);
		/* create dir if it's not there  */ 
		CreateDirectory(GlobalData.DocPath,NULL);
	}

	/* read the path to store zip files       */ 
	if (GetRCString(CONF_ZIPDIR,buffer,"",NLM_PATH_LENGTH)
	/* empty path = don't store zip files     */ 
		&& *buffer)
	{
		GlobalData.ZipPathLen
      = ReplaceWithDup(GlobalData.ZipPath, buffer);
		/* create dir if it's not there  */ 
		CreateDirectory(GlobalData.ZipPath, NULL);
	}

	GlobalData.bTestMessage      = !!GetRCBool(CONF_TEST,             TRUE);
  GlobalData.bAlwaysUseFolders = !!GetRCBool(CONF_FOLDERS,          TRUE);
  GlobalData.bNoDownloadStep   = !!GetRCBool(CONF_NO_DOWNLOAD_STEP, TRUE);
  GlobalData.bNoInstallStep    = !!GetRCBool(CONF_NO_INSTALL_STEP,  TRUE);
  GlobalData.bNoLoadStep       = !!GetRCBool(CONF_NO_LOAD_STEP,     TRUE);

  RegisterBangs(Bangs);

  s_Module *pModList = ParseModules();

  bool bSuccess = ProcessModuleList(pModList);

  if (!GlobalData.bNoLoadStep)
  {
    if ( GetRCLine((bSuccess ? CONF_EVENT_OK : CONF_EVENT_FAIL),
                   buffer, NLM_PATH_LENGTH, _T("")) )
      LSExecute(GlobalData.hLiteStepWnd, buffer, SW_SHOWNORMAL);
  }

  TRACE("Done.");
	return LS_SUCCESS;
}



int quitModule(HINSTANCE dll)
{
  TRACE("Shutting down...");
	/* don't unload the modules,          */ 
	/* litestep takes care of that for us */ 

  RemoveBangs(Bangs);

	FreeSites();

	delete[] GlobalData.LiteStepPath;
	delete[] GlobalData.AliasFile;
	delete[] GlobalData.DocPath;
	delete[] GlobalData.ModulePath;
	delete[] GlobalData.ZipPath;

  /* in case someone never finished it */ 
  delete GlobalData.pOpenBatchState;

  TRACE("Done.");
	return LS_SUCCESS;
}

#define RC_HASH_IMPL 1
#include "hash.h"
