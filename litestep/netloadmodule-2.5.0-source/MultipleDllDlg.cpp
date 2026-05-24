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


bool InitDllListCtrl(HWND hCtrl, s_Archive *pArchive)
{
	_TCHAR Label[NLM_PATH_LENGTH];
	LVCOLUMN lvc;
	int TotalWidth;
	RECT r;

	GetClientRect(hCtrl,&r);
	TotalWidth = r.right-r.left;
 
	lvc.mask = LVCF_FMT | LVCF_WIDTH | LVCF_TEXT | LVCF_SUBITEM; 

	/* Add the column.  */ 
	lvc.pszText = Label;	
	lvc.fmt = LVCFMT_LEFT;

	lvc.iSubItem = 0;
	lvc.cx = TotalWidth;
	LoadString(GlobalData.hInstance, IDS_DLLFILE + 0, Label, NLM_PATH_LENGTH);
	if (ListView_InsertColumn(hCtrl, 0, &lvc) == -1) 
		return false; 

	/* insert list items */ 
	_TCHAR *pDllName,*pBar;
	int nLeft;
	LVITEM lvi;

	pDllName = pArchive->DllNames;
	nLeft = pArchive->nDlls;
	ZeroMemory(&lvi,sizeof(lvi));
	lvi.mask = LVIF_TEXT;

	while (nLeft>0)
	{
		if (*pDllName==0)
			return false;

		/* split first and rest */ 
		/* no risk of overflow so long as the */ 
		/* buffer where this is built is the  */ 
		/* same size as Label, which it is.   */ 
		pBar = Label;
		while (*pDllName!=0 && *pDllName!=_T('|')) *pBar++ = *pDllName++;
		*pBar = 0; pDllName++;

		lvi.iSubItem=0;
		lvi.pszText = Label;
		if (ListView_InsertItem(hCtrl, &lvi) == -1)
			return false;

		lvi.iItem++; --nLeft;
	}

	return true; 
}


INT_PTR CALLBACK MultiDllDlgProc(
		HWND hwndDlg,  /* handle to dialog box     */ 
		UINT uMsg,     /* message                  */ 
		WPARAM wParam, /* first message parameter  */ 
		LPARAM lParam  /* second message parameter */ 
	)
{
	HWND hCtrl;
	TCHAR message[NLM_PATH_LENGTH];
	const _TCHAR *args[4];
	int index;

  s_Archive *pArchive = reinterpret_cast<s_Archive *>(GetWindowLongPtr(hwndDlg, GWLP_USERDATA));

	switch (uMsg)
	{
		case WM_INITDIALOG:
      pArchive = reinterpret_cast<s_Archive *>(lParam);
      SetWindowLongPtr(hwndDlg, GWLP_USERDATA, reinterpret_cast<LPARAM>(pArchive));
			/* fill in the archive name                  */ 
			args[0] = pArchive->pModule->OrigName;
			if (args[0]==NULL) args[0] = pArchive->pModule->Name;
			FormatMessage(
			  FORMAT_MESSAGE_FROM_HMODULE|FORMAT_MESSAGE_ARGUMENT_ARRAY
        |FORMAT_MESSAGE_MAX_WIDTH_MASK,
				GlobalData.hInstance, NLM_MESSAGE_MULTIPLE, 0,
				message, NLM_PATH_LENGTH,
				(va_list *)args);
			SetDlgItemText(hwndDlg,IDC_TOP_MESSAGE,message);
			/* disable view documentation if appropriate */ 
			if (!pArchive->bHasDocs || GlobalData.DocPath==NULL)
			{
				hCtrl = GetDlgItem(hwndDlg, IDC_VIEW_DOCS);
				EnableWindow(hCtrl, FALSE);
				LoadString(GlobalData.hInstance, IDS_NO_DOCS, message, NLM_PATH_LENGTH);
				SetDlgItemText(hwndDlg, IDC_VIEW_DOCS, message);
			}
			/* check install all dll files by default    */ 
			hCtrl = GetDlgItem(hwndDlg, IDC_INSTALL_ALL);
			SendMessage(hCtrl, BM_SETCHECK, BST_CHECKED,0);
			/* fill the dll file list                    */ 
			if (InitDllListCtrl(GetDlgItem(hwndDlg, IDC_FILE_LIST), pArchive))
			{
				return TRUE;
			}
			EndDialog(hwndDlg, IDCANCEL);
			return TRUE;

		case WM_COMMAND:
			if (HIWORD(wParam) == BN_CLICKED) {
				switch (LOWORD(wParam))
				{
				case IDC_VIEW_DOCS:
					LSExecute(NULL, pArchive->pDocPath, SW_SHOWNORMAL);
					break;

				case IDOK:
					if (SendDlgItemMessage(hwndDlg, IDC_INSTALL_ALL, BM_GETCHECK,NULL,NULL) == BST_CHECKED)
						pArchive->bCreateDllFolder = true;
					else
						pArchive->bCreateDllFolder = false;
					/* send the focused item back */ 
					hCtrl = GetDlgItem(hwndDlg,IDC_FILE_LIST);
					index = ListView_GetNextItem(hCtrl,-1,LVNI_ALL|LVNI_FOCUSED);
					if (index!=-1)
					{
						ListView_GetItemText(hCtrl,
							index,0,
							pArchive->DllNames,
							(int)_tcslen(pArchive->DllNames));
						pArchive->nDlls = 1;
						EndDialog(hwndDlg,IDOK);
					}
					/* ignore it if nothing focused     */ 
					/* this shouldn't happen because OK */ 
					/* is disabled below in this case   */ 
					return TRUE;

				case IDCANCEL:
					pArchive->nDlls = 0;
					EndDialog(hwndDlg,IDCANCEL);
					return TRUE;
				}
			}
			break;

		case WM_NOTIFY:
			{
				LPNMHDR pnmh = (LPNMHDR)lParam;
				if (pnmh->idFrom == IDC_FILE_LIST)
				{
					switch (pnmh->code)
					{
					case LVN_ITEMCHANGED:
						/* enable install only if a dll is selected */ 
						hCtrl = GetDlgItem(hwndDlg,IDC_FILE_LIST);
						EnableWindow(GetDlgItem(hwndDlg,IDOK),
							(ListView_GetSelectedCount(hCtrl)>0)?TRUE:FALSE);
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

