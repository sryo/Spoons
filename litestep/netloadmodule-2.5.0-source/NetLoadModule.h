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

#define WIN32_LEAN_AND_MEAN		// Exclude rarely-used stuff from Windows headers
#include <tchar.h>
#include <stddef.h>
#include <windows.h>
#include <commctrl.h>
#include <lsapi\lsapi.h>
#include "lsmod_common.h"
#include "resource.h"
#include "errors.h"

#define MODULE_EXT _T(".dll")
#define MODULE_EXT_LEN 4

#define ARCHIVE_EXT _T(".zip")
#define ARCHIVE_EXT_LEN 4

#define TITLE _T("NetLoadModule v2.5.0")

#define NO_SCRIPTING

#define PATH_LITESTEPDIR			_T("$litestepdir$")
#define PATH_LITESTEPDIR_LEN	(sizeof(PATH_LITESTEPDIR)/sizeof(_TCHAR)-1)
#define PATH_ALIASFILE				_T("modules.ini")
#define PATH_ALIASFILE_LEN		(sizeof(PATH_ALIASFILE)/sizeof(_TCHAR)-1)
#define PATH_MODULEDIR				_T("modules\\")
#define PATH_MODULEDIR_LEN		(sizeof(PATH_MODULEDIR)/sizeof(_TCHAR)-1)
#define PATH_DOCDIR						_T("docs\\")
#define PATH_DOCDIR_LEN				(sizeof(PATH_DOCDIR)/sizeof(_TCHAR)-1)

#define ALIAS_FILE_SECTION		_T("NetLoadModule")

#define CONF_ROOT							_T("NetLoadModule")
#define CONF_ALIASFILE				CONF_ROOT _T("AliasFile")
#define CONF_MODULEDIR				CONF_ROOT _T("Path")
#define PATH_CONF_MODULEDIR   _T("$") CONF_MODULEDIR _T("$")
#define PATH_CONF_MODULEDIR_LEN (sizeof(PATH_CONF_MODULEDIR)/sizeof(_TCHAR)-1)
#define CONF_DOCDIR						CONF_ROOT _T("DocPath")
#define CONF_ZIPDIR						CONF_ROOT _T("ZipPath")
#define CONF_TEST							CONF_ROOT _T("TestMessage")
#define CONF_FOLDERS					CONF_ROOT _T("AlwaysUseFolders")
#define CONF_EVENT_OK         CONF_ROOT _T("OnLoad")
#define CONF_EVENT_FAIL       CONF_ROOT _T("OnFail")
#define CONF_NO_DOWNLOAD_STEP CONF_ROOT _T("NoDownloadStep")
#define CONF_NO_INSTALL_STEP  CONF_ROOT _T("NoInstallStep")
/* this is not simply NoLoad because that's just one transposition away from OnLoad */ 
#define CONF_NO_LOAD_STEP     CONF_ROOT _T("NoLoadStep")
#define CONF_SITE							_T("*") CONF_ROOT _T("Site")
#define CONF_SITE_LEN         (sizeof(CONF_SITE)/sizeof(_TCHAR)-1)
#define CONF_MODULE						_T("*") CONF_ROOT
#define CONF_MODULE_LEN       (sizeof(CONF_MODULE)/sizeof(_TCHAR)-1)
#define CONF_INSTALL          _T("*NetInstallModule")
#define CONF_INSTALL_LEN      (sizeof(CONF_INSTALL)/sizeof(_TCHAR)-1)

#define CONF_LITESTEPDIR			_T("LiteStepDir")

#define VAR_PATHTO_PREFIX     _T("PathTo")
#define VAR_PATHTO_PREFIX_LEN (sizeof(VAR_PATHTO_PREFIX)/sizeof(_TCHAR)-1)

#define ERROR_MESSAGE_FLAGS   (MB_OK|MB_TOPMOST|MB_ICONERROR)

#define NLM_PATH_LENGTH 4096

#define PARSE_LOAD_MODULE     0
#define PARSE_INSTALL_MODULE  1


/* you'll need this to build against litestep .24.6 */ 

#ifndef MODULE_NOTPUMPED
#define MODULE_THREADED   0x0001
#define MODULE_NOTPUMPED  0x0002
#define LMM_HINSTANCE 0x1000
#endif


/* assert and return on failure */ 

#ifndef NDEBUG
void AssertFail(const char *assert,const char *file,int line);
#define ASSERT(c) if (!(c)) AssertFail(#c, __FILE__, __LINE__); else
#define ASSERTR(c,r) if (!(c)) { AssertFail(#c, __FILE__, __LINE__); return r; } else
#else
#define ASSERT(c) (void)(0)
// something critical optimizes out with this
// Wait -- why is this __assume(0)?  That would obviously screw things up...
// Don't feel like checking if that's the bug right now.
//#define ASSERT(c) __assume(0)
#define ASSERTR(c,r) (void)0
#endif
#ifndef CODE_UNREACHABLE
#define CODE_UNREACHABLE 0
#endif

#ifndef NDEBUG
#define DOTRACE
#endif

#ifdef DOTRACE
extern DWORD TraceStartTime;
#define START_TRACE TraceStartTime = GetTickCount()
void Trace(const char *line);
#define TRACE_FILE "C:\\bin\\shell\\litestep\\logs\\NetLoadModule.log"
#define TRACE(n) Trace(n)
#endif
#ifndef TRACE
#define START_TRACE (void)0
#define TRACE(n) (void)0
#endif

struct s_Module {
	s_Module *pNext;
	_TCHAR *Name; size_t NameLen;
	_TCHAR *OrigName; /* specified *NetLoadModule name if it has an alias */ 
      /* OrigName is not actually used, but the code will take it into  */ 
      /* account if it ever does get used.                              */ 
	_TCHAR *DllPath;  /* installed or user-selected dll                   */ 
  _TCHAR *ZipPath;  /* user-selected zip file                           */ 
	_TCHAR *PrimarySite;
	_TCHAR *Desc;
  _TCHAR *Error;    /* only one error per module per run                */ 
	bool bExists;
	bool bDontInstall;
  bool bDontLoad;

  bool bHasAlias;
  bool bHasVersion;
  bool bHasUnrecognizedOption;

  WPARAM Flags;
  TCHAR *sLoadFile;
};

struct s_Site {
	s_Site *pNext;
	_TCHAR *Prefix; size_t PrefixLen;
	_TCHAR *Suffix; size_t SuffixLen;
  unsigned nWeight;
  int iOrder;
};

struct s_Archive {
	const _TCHAR *pName;
	s_Module *pModule;
	bool bHasDocs;
	_TCHAR *pDocPath; /* path to open to view docs */ 
	int nDlls;
	_TCHAR *DllNames;
	bool bCreateDllFolder;
};

struct s_DownloadState
{
  s_Module *pModuleList;
	_TCHAR CurrentName[NLM_PATH_LENGTH];
	s_Module *pCurrentModule;
	int iCurrentModule;
	void (*CurrentStep)(HWND,s_DownloadState *);
  bool bAnyFail;
};

struct s_GlobalData {
	HINSTANCE hInstance;
	HWND hLiteStepWnd;

	_TCHAR *ModulePath;   size_t ModulePathLen;
	_TCHAR *DocPath;      size_t DocPathLen;
	_TCHAR *ZipPath;      size_t ZipPathLen;
	_TCHAR *AliasFile;
	_TCHAR *LiteStepPath; size_t LiteStepPathLen;

	s_Site *pSites,*pNextSite; int nSites;

	bool bTestMessage;
  bool bAlwaysUseFolders;
  bool bNoDownloadStep;
  bool bNoInstallStep;
  bool bNoLoadStep;

  bool bDownloadInitDone;
  s_DownloadState *pOpenBatchState;

	HWND hMainDlg; /* for download status. */ 
  /* This might cause trouble if we get multiple dlgs at the same time. :( */ 
};

struct bangcmddef
{
  const char *Name;
  BangCommand *Command;
};

extern s_GlobalData GlobalData;
extern bangcmddef Bangs[];


INT_PTR CALLBACK ModListDlgProc(
		HWND hwndDlg,  /* handle to dialog box     */ 
		UINT uMsg,     /* message                  */ 
		WPARAM wParam, /* first message parameter  */ 
		LPARAM lParam  /* second message parameter */ 
	);
INT_PTR CALLBACK DownloadDlgProc(
		HWND hwndDlg,  /* handle to dialog box     */ 
		UINT uMsg,     /* message                  */ 
		WPARAM wParam, /* first message parameter  */ 
		LPARAM lParam  /* second message parameter */ 
	);
INT_PTR CALLBACK MultiDllDlgProc(
		HWND hwndDlg,  /* handle to dialog box     */ 
		UINT uMsg,     /* message                  */ 
		WPARAM wParam, /* first message parameter  */ 
		LPARAM lParam  /* second message parameter */ 
	);

void SetModuleError(s_Module *pMod, UINT uID);

bool GetRawModuleName(_TCHAR *buffer,const _TCHAR *name);
bool GetAlias(const _TCHAR *name,_TCHAR *buffer,size_t bufferLen);
bool AddAlias(const _TCHAR *modulename,const _TCHAR *modulepath);
bool RemoveAlias(const _TCHAR *modulename);

void RegisterBangs(bangcmddef *Bangs);
void RemoveBangs(bangcmddef *Bangs);

bool ProcessModuleList(s_Module *pMod);
bool GetModulePath(const _TCHAR *name, size_t NameLen, _TCHAR *token, size_t buf_size, bool &bHasAlias);
bool ParseModuleProc(void *p,const _TCHAR *line,LPARAM);

bool DownloadModule(s_Module *pMod,_TCHAR *tempfilename,size_t tfnmaxlen);
bool InstallModule(HWND hDlg,s_Module *pMod,const _TCHAR *Archive);

void BalanceSites(void);

void LoadDownloadProcs(void);
void UnloadDownloadProcs(void);

/* safely duplicate a string and replace an existing one */ 
size_t ReplaceWithDup(_TCHAR *&dest, const _TCHAR *src);
