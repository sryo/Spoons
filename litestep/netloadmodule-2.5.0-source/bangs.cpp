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
#include "keywords.h"

#ifndef TRACE
#define TRACE(n) (void)0
#endif

void RegisterBangs(bangcmddef *Bangs)
{
	bangcmddef *pBang;
	char BangString[64];

	TRACE("RegisterBangs");

  BangString[0] = '!';

	pBang = Bangs;
	while (pBang->Name != NULL) {
		lstrcpy(BangString+1,pBang->Name);
		AddBangCommand(BangString, pBang->Command);
		pBang++;
	}
}

void RemoveBangs(bangcmddef *Bangs)
{
	bangcmddef *pBang;
	char BangString[64];

	TRACE("RemoveBangs");

  BangString[0] = '!';

	pBang = Bangs;
	while (pBang->Name != NULL) {
		lstrcpy(BangString+1,pBang->Name);
		RemoveBangCommand(BangString);
		pBang++;
	}
}


// ======================================================
//
// ======================================================


void BangNetReloadModule(HWND sender, LPCSTR args)
{
  _TCHAR buffer[NLM_PATH_LENGTH];
  /* reload yourself */ 
  if (GetToken(args, buffer, NULL, FALSE)
    && _tcscmp(buffer,".")==0)
  {
    SendMessage(GlobalData.hLiteStepWnd, LM_RELOADMODULE,
      (WPARAM)GlobalData.hInstance, LMM_HINSTANCE);
    return;
  }
  /* reload something else */ 
  s_Module *pMod = new NLM_NOTHROW s_Module; /* deleted by PML */ 
#ifdef NLM_IGNORE_EXCEPTIONS
  if (!pMod)
    return;
#endif
  ZeroMemory(pMod, sizeof(s_Module));

  if (GlobalData.pOpenBatchState)
    GlobalData.pOpenBatchState->bAnyFail = false;

  if (!ParseModuleProc(pMod, args, PARSE_LOAD_MODULE))
  {
    delete pMod;
    return;
  }

  if (GlobalData.pOpenBatchState)
  {
    /* add it to the end of the list */ 
    s_Module **p = &GlobalData.pOpenBatchState->pModuleList;
    while (*p)
      p = &(*p)->pNext;
    *p = pMod;
  }
  else
  {
    ProcessModuleList(pMod);
  }
}

void BangNetUnloadModule(HWND sender, LPCSTR args)
{
  _TCHAR buffer[NLM_PATH_LENGTH+14];
  /* unload yourself */ 
  if (GetToken(args, buffer, NULL, FALSE)
    && _tcscmp(buffer,".")==0)
  {
    PostMessage(GlobalData.hLiteStepWnd, LM_UNLOADMODULE,
      (WPARAM)GlobalData.hInstance, LMM_HINSTANCE);
    return;
  }
  /* unload something else */ 
  _tcscpy(buffer, _T("!UnloadModule "));
  bool bWhoCaresIfItHasAnAlias;
  if (GetModulePath(args, _tcslen(args), buffer+14, NLM_PATH_LENGTH, bWhoCaresIfItHasAnAlias))
    LSExecute(sender, buffer, SW_SHOWNORMAL);
}

void BangNetInstallModule(HWND sender, LPCSTR args)
{
  s_Module *pMod = new NLM_NOTHROW s_Module;
#ifdef NLM_IGNORE_EXCEPTIONS
  if (!pMod)
    return;
#endif
  ZeroMemory(pMod, sizeof(s_Module));

  if (GlobalData.pOpenBatchState)
    GlobalData.pOpenBatchState->bAnyFail = false;

  ParseModuleProc(pMod, args, PARSE_INSTALL_MODULE);

  if (GlobalData.pOpenBatchState)
  {
    s_Module **p = &GlobalData.pOpenBatchState->pModuleList;
    while (*p)
      p = &(*p)->pNext;
    *p = pMod;
  }
  else
  {
    ProcessModuleList(pMod);
  }
}

static void UninstallPath(TCHAR *sDir, size_t nDirLen,
                          TCHAR *sName, size_t nNameLen)
{
  TCHAR file[NLM_PATH_LENGTH];
  WIN32_FIND_DATA f;
  HANDLE ffh;

  /* delete a subdirectory */ 
  _tcscpy(file, sDir);
  _tcscpy(file+nDirLen, sName);
  _tcscpy(file+nDirLen+nNameLen, _T("//*"));
  ZeroMemory(&f, sizeof(f));
  ffh = FindFirstFile(file, &f);
  if (ffh!=INVALID_HANDLE_VALUE)
  {
    do
    {
      _tcscpy(file+nDirLen+nNameLen+1, f.cFileName);
      DeleteFile(file);
    } while (FindNextFile(ffh, &f));
    FindClose(ffh);
    *(file+nDirLen+nNameLen) = 0;
    RemoveDirectory(file);
  }
  /* delete files */ 
  _tcscpy(file+nDirLen+nNameLen, _T(".*"));
  ZeroMemory(&f, sizeof(f));
  ffh = FindFirstFile(file, &f);
  if (ffh!=INVALID_HANDLE_VALUE)
  {
    do
    {
      _tcscpy(file+nDirLen, f.cFileName);
      /* must match filename with extension */ 
      /* ie, don't allow extra '.'s         */ 
      if (_tcschr(file+nDirLen+nNameLen+1,_T('.'))==NULL)
        DeleteFile(file);
    } while (FindNextFile(ffh, &f));
    FindClose(ffh);
  }
}

void BangNetUninstallModule(HWND sender, LPCSTR args)
{
  /* first, make sure it's not loaded */ 
  BangNetUnloadModule(sender, args);

  /* now remove it */ 
  _TCHAR token[NLM_PATH_LENGTH];
  if (GetToken(args, token, NULL, TRUE))
  {
    _TCHAR name[NLM_PATH_LENGTH];
    size_t namelen;
    GetRawModuleName(name, token);
    namelen = _tcslen(name);

    UninstallPath(
      GlobalData.ModulePath, GlobalData.ModulePathLen,
      name, namelen);
    RemoveAlias(name);

    if (GlobalData.DocPath)
      UninstallPath(
        GlobalData.DocPath, GlobalData.DocPathLen,
        name, namelen);

    if (GlobalData.ZipPath)
      UninstallPath(
        GlobalData.ZipPath, GlobalData.ZipPathLen,
        name, namelen);
  }
}

void BangNetLoadModuleBatch(HWND sender, LPCSTR args)
{
  _TCHAR token[MAX_LINE_LENGTH];
  *token = 0;
  GetToken(args, token, NULL, FALSE);
  _tcslwr(token); /* make that case insensitive */ 
  switch (BatchKeywords(token, BATCH_BAD_TOKEN))
  {
  case BATCH_BEGIN:
    /* if we're already in a batch, continue adding to it */ 
    if (!GlobalData.pOpenBatchState)
    {
      GlobalData.pOpenBatchState = new NLM_NOTHROW s_DownloadState;
#ifdef NLM_IGNORE_EXCEPTIONS
      if (!GlobalData.pOpenBatchState)
        return;
#endif
      GlobalData.pOpenBatchState->pModuleList = NULL;
      GlobalData.pOpenBatchState->bAnyFail = false;
    }
    break;
  case BATCH_END:
    if (GlobalData.pOpenBatchState)
    {
      /* close the batch state first in case of nested batches */ 
      s_Module *pMod = GlobalData.pOpenBatchState->pModuleList;
      delete GlobalData.pOpenBatchState;
      GlobalData.pOpenBatchState = NULL;

      ProcessModuleList(pMod);
    }
    break;

  case BATCH_BAD_TOKEN:
    {
      const TCHAR *args_[4];
      TCHAR buf[NLM_PATH_LENGTH];
      args_[0] = args;
      FormatMessage(
          FORMAT_MESSAGE_FROM_HMODULE
        | FORMAT_MESSAGE_ARGUMENT_ARRAY
        | FORMAT_MESSAGE_MAX_WIDTH_MASK,
	      GlobalData.hInstance, NLM_ERROR_BATCH, 0,
	      buf, NLM_PATH_LENGTH,
	      (va_list *)args_);
      MessageBox(sender, buf, TITLE, ERROR_MESSAGE_FLAGS);
    }
    break;
  }
}

struct s_NetIfModuleLoadedProc
{
  const _TCHAR *dll;
  DWORD dwFlags;
};

BOOL __stdcall NetIfModuleLoadedProc(LPCSTR name, DWORD dwFlags, LPARAM lParam)
{
  s_NetIfModuleLoadedProc *data = reinterpret_cast<s_NetIfModuleLoadedProc *>(lParam);

  if (_tcscmp(data->dll, name) == 0)
  {
    /* report back what we found */ 
    data->dwFlags = dwFlags;
    return FALSE;
  }

  /* keep looking */ 
  return TRUE;
}

void BangNetIfModule(HWND sender, LPCSTR args)
{
  bool bGotFinalTest = false;
  bool bTestNot = false;
  int baseTest = IFTEST_BAD_TOKEN;

  _TCHAR token[MAX_LINE_LENGTH];

  /* scan until we get the final test */ 
  do
  {
    *token = 0;
    GetToken(args, token, &args, FALSE);
    _tcslwr(token); /* make that case insensitive */ 

    int t = IfTestKeywords(token, IFTEST_BAD_TOKEN);
    switch (t)
    {
    case IFTEST_NOT:
      if (bTestNot)
        return; /* why support double negatives? */ 
      bTestNot = true;
      break;

    case IFTEST_BAD_TOKEN:
      /* To be consistent, this should probably bring up */ 
      /* a message box, but I don't want to do that now. */ 
      /* Also, it's part of a script, so maybe it would  */ 
      /* be better to not do that?                       */ 
      return;

    default:
      baseTest = t;
      bGotFinalTest = true;
      break;
    }
  } while (!bGotFinalTest);

  /* pull off the module name */ 
  *token = 0;
  GetToken(args, token, &args, FALSE);
  _tcslwr(token); /* make that case insensitive */ 

  /* no matter what, we'll need the dll name */ 
  _TCHAR dll[NLM_PATH_LENGTH];
  bool bHasAlias = false;
  if (!GetModulePath(token, _tcslen(token), dll, NLM_PATH_LENGTH, bHasAlias))
    return;

  bool bCondition = false;
  switch (baseTest)
  {
  case IFTEST_HASALIAS:
    bCondition = bHasAlias;
    break;

  case IFTEST_INSTALLED:
	  bCondition = (GetFileAttributes(dll) != INVALID_FILE_ATTRIBUTES);
    break;

  case IFTEST_LOADED:
    {
      s_NetIfModuleLoadedProc data = { dll, 0 };
      const HRESULT hr = EnumLSData(ELD_MODULES, (FARPROC)NetIfModuleLoadedProc, (LPARAM)&data);
      /* the callback will cancel the enumeration if it finds a match */ 
      bCondition = (hr == S_FALSE);
    }
    break;

  case IFTEST_THREADED:
    {
      s_NetIfModuleLoadedProc data = { dll, 0 };
      const HRESULT hr = EnumLSData(ELD_MODULES, (FARPROC)NetIfModuleLoadedProc, (LPARAM)&data);
      /* the callback will cancel the enumeration if it finds a match */ 
      bCondition = (hr == S_FALSE)
                && (data.dwFlags & LS_MODULE_THREADED) != 0;
    }
    break;
  }

  /* invert if not */ 
  bCondition = (bCondition != bTestNot);

  if (bCondition)
    LSExecute(sender, args, SW_SHOWNORMAL);
}

// ======================================================
//
// ======================================================

bangcmddef Bangs[] =
{
	{ "NetReloadModule",	  &BangNetReloadModule },
	{ "NetUnloadModule",	  &BangNetUnloadModule },
  { "NetInstallModule",   &BangNetInstallModule },
  { "NetUninstallModule", &BangNetUninstallModule },
  { "NetLoadModuleBatch", &BangNetLoadModuleBatch },
  { "NetIfModule",        &BangNetIfModule },
	{ NULL, NULL }
};
