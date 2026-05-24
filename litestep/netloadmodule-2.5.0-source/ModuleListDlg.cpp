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
#define _WIN32_WINNT 0x500
#include "Commdlg.h"

void mooBegin(HWND hDlg, s_DownloadState *pState);
void mooDownload(HWND hDlg, s_DownloadState *pState);
void mooInstall(HWND hDlg, s_DownloadState *pState);
void mooDone(HWND hDlg, s_DownloadState *pState);
void mooDoneAll(HWND hDlg, s_DownloadState *pState);

#define MODICON_DOT      0
#define MODICON_FAILURE  1
#define MODICON_SUCCESS  2
#define MODICON_DOWNLOAD 3
#define MODICON_ALERT    4



/*
	Initialize and fill the module list.
*/
bool InitModuleListCtrl(HWND hCtrl, s_DownloadState *pState)
{
	_TCHAR Label[NLM_PATH_LENGTH];
	LVCOLUMN lvc;
	int TotalWidth;
	RECT r;

	GetClientRect(hCtrl,&r);
	TotalWidth = r.right-r.left;
 
	lvc.mask = LVCF_FMT | LVCF_WIDTH | LVCF_TEXT | LVCF_SUBITEM; 

	/* Add the columns. */ 
	lvc.pszText = Label;	
	lvc.fmt = LVCFMT_LEFT;

	lvc.iSubItem = 0;
	lvc.cx = (TotalWidth+1)/2;
	LoadString(GlobalData.hInstance, IDS_MODULE + 0, Label, NLM_PATH_LENGTH);
	if (ListView_InsertColumn(hCtrl, 0, &lvc) == -1) 
		return false; 

	lvc.iSubItem = 1;
	lvc.cx = TotalWidth/2;
	LoadString(GlobalData.hInstance, IDS_MODULE + 1, Label, NLM_PATH_LENGTH);
	if (ListView_InsertColumn(hCtrl, 1, &lvc) == -1) 
		return false;

	HIMAGELIST hIL;
	HBITMAP hbm;

	/* don't use all 8 images right now, but whatever */ 
	hIL = ImageList_Create(16, 16, ILC_COLOR|ILC_MASK, 8, 0);
	if (hIL==NULL) return false;

	/* load the images */ 
	hbm = LoadBitmap(GlobalData.hInstance,MAKEINTRESOURCE(IDB_MODULE_STATE));
	if (ImageList_AddMasked(hIL, hbm, RGB(255, 0, 255)) == -1)
	{
		DeleteObject(hbm);
		return false;
	}
	DeleteObject(hbm);

	/* asign it to the list view                     */ 
	/* (the control now takes responsibility for it) */ 
	ListView_SetImageList(hCtrl, hIL, LVSIL_SMALL);

	/* insert list items */ 
	s_Module *pMod;
	LVITEM lvi;

	pMod = pState->pModuleList;
	lvi.iItem=0;
	lvi.state=0;
	lvi.stateMask=0;
	while (pMod!=NULL)
	{
		if (!pMod->bExists || GlobalData.bTestMessage)
		{
			/* set first column: module name */ 
			if (pMod->bExists)
				lvi.iImage=MODICON_SUCCESS;
			else
				lvi.iImage=MODICON_DOT;
      /* If we're testing, get a little more picky. */ 
      if (GlobalData.bTestMessage)
      {
        if (!pMod->bHasVersion)
        {
          SetModuleError(pMod, IDS_WARN_NOVERSION);
          lvi.iImage = MODICON_ALERT;
        }
        else if (pMod->bHasAlias && pMod->sLoadFile==NULL)
        {
          SetModuleError(pMod, IDS_WARN_NOLOADOPTION);
          lvi.iImage = MODICON_ALERT;
        }
      }
			lvi.mask = LVIF_TEXT | LVIF_IMAGE | LVIF_PARAM | LVIF_STATE;
			lvi.iSubItem=0;
			lvi.lParam = (LPARAM)pMod;
			lvi.pszText = pMod->Name;
			if (ListView_InsertItem(hCtrl, &lvi) == -1)
				return false;

			/* set second column: description or primary site */ 
			lvi.mask = LVIF_TEXT;
			lvi.iSubItem = 1;
      if (pMod->Error != NULL)
        lvi.pszText = pMod->Error;
			else if (pMod->Desc != NULL)
				lvi.pszText = pMod->Desc;
			else
				lvi.pszText = pMod->PrimarySite;
			if (lvi.pszText && ListView_SetItem(hCtrl, &lvi) == -1)
				return false;

			/* next position */ 
			lvi.iItem++;
		}
		pMod = pMod->pNext;
	}

	return true; 
}



bool BeginDownload(HWND hDlg, s_DownloadState *pState)
{
	_TCHAR buffer[NLM_PATH_LENGTH];

	EnableWindow(GetDlgItem(hDlg, IDCANCEL), FALSE);
	EnableWindow(GetDlgItem(hDlg, IDC_DOWNLOAD), FALSE);
	EnableWindow(GetDlgItem(hDlg, IDC_MODULE_LIST), FALSE);
	ShowWindow(GetDlgItem(hDlg, IDCANCEL), SW_HIDE);
	ShowWindow(GetDlgItem(hDlg, IDC_DOWNLOAD), SW_HIDE);
	ShowWindow(GetDlgItem(hDlg, IDC_PROGRESS1), SW_SHOW);

	LoadString(GlobalData.hInstance, IDS_DL_MESSAGE, buffer, NLM_PATH_LENGTH);
	SetDlgItemText(hDlg,IDC_MESSAGE,buffer);

	*buffer = 0;
	SetDlgItemText(hDlg,IDC_STATUS,buffer);

	/* switch the dialog to download mode    */ 
	SetWindowLongPtr(hDlg, DWLP_DLGPROC, (LONG_PTR)&DownloadDlgProc);

	/* detect if any modules fail to install */ 
	pState->bAnyFail = false;

	/* start download                        */ 
	pState->pCurrentModule = pState->pModuleList;
  pState->iCurrentModule = 0;
	pState->CurrentStep = &mooBegin;
	PostMessage(hDlg, WM_ENTERIDLE, NULL, NULL);

	return true;
}

HWND GetListAndItem(HWND hDlg, LVITEM *plvi)
{
	HWND hList;

	hList = GetDlgItem(hDlg, IDC_MODULE_LIST);

	plvi->mask = LVIF_PARAM;
	plvi->iSubItem=0;
	ListView_GetItem(hList, plvi);

	return hList;
}

HWND GetListAndCurrentItem(HWND hDlg, LVITEM *plvi)
{
	HWND hList;

	hList = GetDlgItem(hDlg, IDC_MODULE_LIST);

	plvi->iItem = ListView_GetNextItem(hList, -1, LVNI_ALL|LVNI_FOCUSED);

	return GetListAndItem(hDlg, plvi);
}

s_Module *GetModuleFromList(HWND hDlg)
{
	LVITEM lvi;

	GetListAndCurrentItem(hDlg, &lvi);

	return (s_Module *)lvi.lParam;
}

void ToggleInstallNow(HWND hDlg)
{
	LVITEM lvi;
	HWND hList;
	s_Module *pMod;

	hList = GetListAndCurrentItem(hDlg, &lvi);

	pMod = (s_Module *)lvi.lParam;
	pMod->bDontInstall = !pMod->bDontInstall;

	lvi.mask = LVIF_IMAGE;
	if (pMod->bDontInstall)
		lvi.iImage = MODICON_FAILURE;
	else
		lvi.iImage = MODICON_DOT;
	ListView_SetItem(hList, &lvi);
	ListView_RedrawItems(hList, 0, 0);
}

void SelectFileAlias(HWND hDlg)
{
  HMODULE hCOMDLG = NULL;
#ifndef UNICODE
  BOOL (APIENTRY *pGetOpenFileName)(LPOPENFILENAMEA) = NULL;
#else
  BOOL (APIENTRY *pGetOpenFileName)(LPOPENFILENAMEW) = NULL;
#endif

	LVITEM lvi;
	HWND hList;
	s_Module *pMod;
	OPENFILENAME ofn;
	_TCHAR file[MAX_PATH_LENGTH];
  _TCHAR filter[NLM_PATH_LENGTH];
  _TCHAR title[NLM_PATH_LENGTH];

	/* get the focused item */ 
	hList = GetListAndCurrentItem(hDlg, &lvi);

	pMod = (s_Module *)lvi.lParam;

	/* use a common open dialog to get dll path */ 
	ZeroMemory(&ofn,sizeof(ofn));
	ofn.lStructSize = sizeof(ofn);
	ofn.hwndOwner = hDlg;
	LoadString(GlobalData.hInstance, IDS_MODULEFILTER, filter, NLM_PATH_LENGTH);
  {
    /* \0 doesn't seem to work in resources... */ 
    _TCHAR *p = filter;
    while ( (p = _tcschr(p, _T('|'))) != 0 )
      *p++ = 0;
  }
	ofn.lpstrFilter = filter;
	_tcscpy(file, pMod->DllPath);
	ofn.lpstrFile = file;
	ofn.nMaxFile = MAX_PATH_LENGTH;
	LoadString(GlobalData.hInstance, IDS_MODULESELECTFILE, title, NLM_PATH_LENGTH);
	ofn.lpstrTitle = title;
	ofn.Flags = OFN_DONTADDTORECENT|OFN_NONETWORKBUTTON|OFN_FILEMUSTEXIST|OFN_HIDEREADONLY;

  hCOMDLG = LoadLibrary("COMDLG32.DLL");
#ifdef UNICODE
  pGetOpenFileName = (BOOL (APIENTRY *)(LPOPENFILENAMEW))GetProcAddress(hCOMDLG, "GetOpenFileNameW");
#else
  pGetOpenFileName = (BOOL (APIENTRY *)(LPOPENFILENAMEA))GetProcAddress(hCOMDLG, "GetOpenFileNameA");
#endif

	if (pGetOpenFileName(&ofn)==IDOK)
	{
    /* optimally we'd check the first few bytes of the file */ 
    const _TCHAR *pDot = _tcsrchr(file, _T('.'));
    if (pDot && _tcsicmp(pDot, _T(".zip")) == 0)
    {
      /* user selected a zip file */ 
      /* TODO: make sure this succeeds */ 
      ReplaceWithDup(pMod->ZipPath, file);
    }
    else /* not a zip file */ 
    {
		  /* set the path        */ 
      /* TODO: make sure this succeeds */ 
      ReplaceWithDup(pMod->DllPath, file);

		  /* remember it later   */ 
		  AddAlias(pMod->Name, pMod->DllPath);

		  /* mark it as existing */ 
		  pMod->bExists = true;
		  lvi.mask = LVIF_IMAGE;
		  lvi.iImage = MODICON_SUCCESS;
		  ListView_SetItem(hList, &lvi);
		  ListView_RedrawItems(hList, 0, 0);
    }
	}

  FreeLibrary(hCOMDLG);
}

void DoContextMenu(HWND hWnd)
{
	POINT pt;
	HMENU root,context;

	root = LoadMenu(GlobalData.hInstance, MAKEINTRESOURCE(IDR_CONTEXT_MENUS));
	context = GetSubMenu(root, 0);

	if (GetModuleFromList(hWnd)->bDontInstall)
		CheckMenuItem(context, ID_DONOTINSTALLTHISMODULENOW, MF_BYCOMMAND|MF_CHECKED);

	GetCursorPos(&pt);
	/* do the context menu, commands are sent to the dialog proc */ 
	TrackPopupMenu(context, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hWnd, NULL);

	DestroyMenu(root);
}

// DialogProc -----------------------------------------------------------------

INT_PTR CALLBACK ModListDlgProc(
		HWND hwndDlg,  /* handle to dialog box     */ 
		UINT uMsg,     /* message                  */ 
		WPARAM wParam, /* first message parameter  */ 
		LPARAM lParam  /* second message parameter */ 
	)
{
  s_DownloadState *pState = reinterpret_cast<s_DownloadState *>(GetWindowLongPtr(hwndDlg, GWLP_USERDATA));
	switch (uMsg)
	{
		case WM_INITDIALOG:
      /* force it on top so it doesn't look like ls crashed */ 
      SetWindowPos(hwndDlg, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE|SWP_NOSIZE);

			GlobalData.hMainDlg = hwndDlg;
      pState = reinterpret_cast<s_DownloadState *>(lParam);
			if (InitModuleListCtrl(GetDlgItem(hwndDlg, IDC_MODULE_LIST), pState))
			{
        SetWindowLongPtr(hwndDlg, GWLP_USERDATA, reinterpret_cast<LPARAM>(pState));
				return TRUE;
			}
			EndDialog(hwndDlg,IDCANCEL);			
			return TRUE;

		case WM_COMMAND:
			if (HIWORD(wParam)==BN_CLICKED)
      {
				switch (LOWORD(wParam))
				{
				case IDC_DOWNLOAD:
          BeginDownload(hwndDlg, pState); return TRUE;
				case IDCANCEL:
          EndDialog(hwndDlg,IDCANCEL); return TRUE;
				case IDOK:
          EndDialog(hwndDlg,IDOK); return TRUE;
				/* context menu commands */ 
				case ID_DONOTINSTALLTHISMODULENOW:
					ToggleInstallNow(hwndDlg); return TRUE;
				case ID_SELECTFILE:
					SelectFileAlias(hwndDlg); return TRUE;
				}
			}
			break;

		case WM_NOTIFY:
			{
				LPNMHDR pnmh = (LPNMHDR)lParam;
				if (pnmh->idFrom == IDC_MODULE_LIST)
				{
					switch (pnmh->code)
					{
					case NM_RCLICK:
						/* user right-clicked in module list */ 
						if (ListView_GetSelectedCount(pnmh->hwndFrom)>0)
							DoContextMenu(hwndDlg);
						return TRUE;
					}
				}
			}
			break;

		case WM_CLOSE:
			EndDialog(hwndDlg,IDCANCEL);
			return TRUE;
	}
	return FALSE;
}

//
// Installation FSM
//

void mooBegin(HWND hDlg, s_DownloadState *pState)
{
	_TCHAR message[NLM_PATH_LENGTH];

	LVITEM lvi;
	HWND hList;

	lvi.iItem= pState->iCurrentModule;
	hList = GetListAndItem(hDlg,&lvi);

	pState->pCurrentModule = (s_Module *)lvi.lParam;

	if (pState->pCurrentModule->bExists || pState->pCurrentModule->bDontInstall)
	{
		/* this one's already there, go to the next one */ 
		pState->CurrentStep = &mooDone;
		return;
	}

	lvi.mask = LVIF_IMAGE;
	lvi.iImage=MODICON_DOWNLOAD;
	ListView_SetItem(hList, &lvi);
	ListView_RedrawItems(hList, 0, 0);
	UpdateWindow(hList);

	LoadString(GlobalData.hInstance, IDS_DOWNLOADING, message, NLM_PATH_LENGTH);
	TRACE(message);
	SetDlgItemText(hDlg, IDC_STATUS, message);

	pState->CurrentStep = &mooDownload;
}

void mooDownload(HWND hDlg, s_DownloadState *pState)
{
	_TCHAR message[NLM_PATH_LENGTH];
	if (
    pState->pCurrentModule->ZipPath
    || DownloadModule(pState->pCurrentModule, pState->CurrentName, NLM_PATH_LENGTH)
		 )
	{
		LoadString(GlobalData.hInstance, IDS_INSTALLING, message, NLM_PATH_LENGTH);
		TRACE(message);
		SetDlgItemText(hDlg, IDC_STATUS, message);
		pState->CurrentStep = &mooInstall;
	}
	else
	{
		pState->CurrentStep = &mooDone;
	}
}

void mooInstall(HWND hDlg, s_DownloadState *pState)
{
  if (pState->pCurrentModule->ZipPath)
  {
	  InstallModule(hDlg, pState->pCurrentModule, pState->pCurrentModule->ZipPath);
    /* if it fails, we want to do a regular download next time */ 
    delete[] pState->pCurrentModule->ZipPath;
    pState->pCurrentModule->ZipPath = NULL;
  }
  else
	  InstallModule(hDlg, pState->pCurrentModule, pState->CurrentName);
	pState->CurrentStep = &mooDone;
}

void mooDone(HWND hDlg, s_DownloadState *pState)
{
	LVITEM lvi;
	HWND hList;

	/* update existance flag */ 
	pState->pCurrentModule->bExists =
		(GetFileAttributes(pState->pCurrentModule->DllPath) != INVALID_FILE_ATTRIBUTES);

	hList = GetDlgItem(hDlg, IDC_MODULE_LIST);

	lvi.iItem= pState->iCurrentModule;
	lvi.iSubItem=0;
	lvi.mask = LVIF_IMAGE;

	if (pState->pCurrentModule->bExists)
	{
		lvi.iImage=MODICON_SUCCESS;
		TRACE("Success.");
	}
	else
	{
		lvi.iImage=MODICON_FAILURE;
		TRACE("Failure.");
    TRACE(pState->pCurrentModule->DllPath);
		pState->bAnyFail = true;
	}

	ListView_SetItem(hList,&lvi);

  if (pState->pCurrentModule->Error)
  {
    lvi.mask = LVIF_TEXT;
    lvi.iSubItem = 1;
    lvi.pszText = pState->pCurrentModule->Error;
    ListView_SetItem(hList, &lvi);
  }

  ListView_RedrawItems(hList, 0, 0);
	UpdateWindow(hList);

	SetDlgItemText(hDlg,IDC_STATUS,"");

	/* go to the next item */ 
	++pState->iCurrentModule;
	lvi.mask = LVIF_PARAM;
	lvi.iItem = pState->iCurrentModule;

	if (ListView_GetItem(hList, &lvi))
	{
		/* do next file */ 
		pState->CurrentStep = &mooBegin;
	}
	else
	{
		/* no more files */ 
		pState->CurrentStep = &mooDoneAll;
	}
}

void mooDoneAll(HWND hDlg, s_DownloadState *pState)
{
	_TCHAR message[NLM_PATH_LENGTH];

	/* set proc back to original */ 
	SetWindowLongPtr(hDlg, DWLP_DLGPROC, (LONG_PTR)&ModListDlgProc);

	ShowWindow(GetDlgItem(hDlg, IDCANCEL), SW_SHOW);
	ShowWindow(GetDlgItem(hDlg, IDC_DOWNLOAD), SW_SHOW);
	ShowWindow(GetDlgItem(hDlg, IDC_PROGRESS1), SW_HIDE);
	EnableWindow(GetDlgItem(hDlg, IDC_MODULE_LIST), TRUE);
	EnableWindow(GetDlgItem(hDlg, IDCANCEL), TRUE);

	/* click the nonexistant 'ok' button if all is well */ 
	if (pState->bAnyFail==false)
	{
		PostMessage(hDlg,WM_COMMAND,MAKEWPARAM(IDOK,BN_CLICKED),NULL);
	}
	else
	{
		EnableWindow(GetDlgItem(hDlg, IDC_DOWNLOAD), TRUE);

		LoadString(GlobalData.hInstance, IDS_FAIL_MESSAGE, message, NLM_PATH_LENGTH);
		SetDlgItemText(hDlg,IDC_MESSAGE, message);

		LoadString(GlobalData.hInstance, IDS_FAIL_STATUS, message, NLM_PATH_LENGTH);
		SetDlgItemText(hDlg,IDC_STATUS, message);
	}
}

void DoDownloadStep(HWND hDlg, s_DownloadState *pState)
{
	/* bad and evil and yucky.  don't look */ 
	static bool bLock = false;
	if (bLock)
	{
		TRACE("got locked WM_ENTERIDLE");
		return;
	}
	bLock = true;
	pState->CurrentStep(hDlg, pState);
	bLock = false;
	PostMessage(hDlg,WM_ENTERIDLE,NULL,NULL);
	/* ok, you can look again now          */ 
}



// DialogProc for the download phase

INT_PTR CALLBACK DownloadDlgProc(
		HWND hwndDlg,  /* handle to dialog box     */ 
		UINT uMsg,     /* message                  */ 
		WPARAM wParam, /* first message parameter  */ 
		LPARAM lParam  /* second message parameter */ 
	)
{
  s_DownloadState *pState = reinterpret_cast<s_DownloadState *>(GetWindowLongPtr(hwndDlg, GWLP_USERDATA));
	switch (uMsg)
	{

		case WM_COMMAND:
			if (HIWORD(wParam)==BN_CLICKED)
      {
				switch (LOWORD(wParam))
				{
				case IDCANCEL:
					EndDialog(hwndDlg,IDCANCEL);
					return TRUE;
				}
			}
			break;

		case WM_CLOSE:
			EndDialog(hwndDlg,IDCANCEL);
			return TRUE;

		case WM_ENTERIDLE:
			/* process the next step */ 
			DoDownloadStep(hwndDlg, pState);
			/* using WM_ENTERIDLE for this turns out to be a bad     */ 
			/* idea because Windows sends them while the multiple    */ 
			/* dll dialog is up, which in turn opens up more of them */ 
			/* this is the reason for the lock in DoDownloadStep     */ 
			return TRUE;
	}
	return FALSE;
}

