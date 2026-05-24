/*
	Anykey, a hotkey module for Litestep
	Copyright(c) 2003-2004 Sergey Gagarin a.k.a. Seg@
	Based on jKey module sources by jugg and Hollow

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <litestep/lsapi/lsapi.h>
#include "anykey.h"

//some string constants

LPCTSTR szAppClass = "AnyKeyClass"; // Class Name
LPCTSTR szAppName = "";				// Window Name

LPCTSTR aboutStr = "Anykey 1.0 (Seg@)";

LPCTSTR regerrStr = "Error registering Anykey window class";
LPCTSTR crterrStr = "Error creating Anykey window!";
LPCTSTR reserrStr = "Hotkey resource allocation failed.\n\nError while processing definition:\n%s";

// implemented functions
LRESULT CALLBACK WndProc( HWND, UINT, WPARAM, LPARAM );
LRESULT CALLBACK LLKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);

BOOL loadKeyFromString(char *buffer, TKey *tmpKey, char *cmdstr);
VOID loadKeys(VOID);
VOID loadVKTable(LPTSTR);
VOID freeKeyList(TKey *hotkeys, UINT *numhKeys);
VOID freeVKTable(VOID);
BOOL stripWS (LPTSTR);
BOOL isKeyInList(ATOM);
UINT getKeyById(ATOM);

// global variables
HWND hMainWnd;
HWND hParentWnd;

ATOM LWinKey;
ATOM RWinKey;

TSettings jks;

UINT numvKeys = 0;
UINT numhKeys = 0;
UINT numsKeys = 0;
UINT numaKeys = 0;

tVKTable *vkTable	= NULL;
TKey *hotkeys		= NULL;
TKey *scankeys	= NULL;
TKey *appkeys	= NULL;

HHOOK hLowLevelKeyboardHook = NULL;
//HHOOK hShellHook = NULL;

// Module entry point

INT initModuleEx( HWND parent, HINSTANCE dllInst, LPCTSTR szPath )
{
	szPath=szPath;
	hParentWnd = parent;
	{
		// Register the main window class
		WNDCLASS wc;
		memset(&wc, 0, sizeof(wc));
		wc.lpfnWndProc = (WNDPROC)WndProc;
		wc.hInstance = dllInst;
		wc.lpszClassName = szAppClass;
		if (!RegisterClass(&wc))
		{
			ERRORBOX(regerrStr);
			return 1;
		}
	}

	// Create main window
	hMainWnd = CreateWindowEx(WS_EX_TOOLWINDOW,szAppClass,szAppName,WS_CHILD,0,0,0,0,hParentWnd,NULL,dllInst,NULL);
	if (hMainWnd == NULL)
	{
		ERRORBOX(crterrStr);
		UnregisterClass(szAppName, dllInst);
		return 1;
	}

	// Get the settings
	jks.bNoWarn = GetRCBool("AnykeyNoWarn",TRUE);
	jks.nLWinKeyTimeout = (UINT)abs(GetRCInt("AnykeyLWinKeyTimeout", 750));
	jks.nRWinKeyTimeout = (UINT)abs(GetRCInt("AnykeyRWinKeyTimeout", 750));

	{
		// Load extended key items
		char tmp[4096];

		*tmp = 0;
		GetRCString("AnykeyVKTable", tmp, "", _MAX_PATH);
		if (*tmp)
			loadVKTable(tmp);

		*tmp = 0;
		GetRCLine("AnykeyLWinKey", tmp, 4096, "");
		if (*tmp)
		{
			jks.pLWinKey = (LPTSTR)malloc(strlen(tmp)+1);
			if (jks.pLWinKey != NULL)
			{
				strcpy(jks.pLWinKey, tmp);
				if ((LWinKey=GlobalAddAtom("LWIN_KEY")) != 0)
				{
					if (!RegisterHotKey(hMainWnd, LWinKey, MOD_WIN, VK_LWIN))
					{
						GlobalDeleteAtom(LWinKey);
						LWinKey = 0;
					}
				}
			}
			if (LWinKey == 0){
				if (jks.pLWinKey != NULL){
					free(jks.pLWinKey);
					jks.pLWinKey = NULL;
				}
				if(!jks.bNoWarn)
					ERRORBOX("Error registering Left WinKey!");
			}
		}else
			jks.pLWinKey = NULL;

		*tmp = 0;
		GetRCLine("AnykeyRWinKey", tmp, 4096, "");
		if (*tmp)
		{
			jks.pRWinKey = (LPTSTR)malloc(strlen(tmp)+1);
			if (jks.pRWinKey != NULL){
				strcpy(jks.pRWinKey, tmp);
				if ((RWinKey=GlobalAddAtom("RWIN_KEY")) != 0)
				{
					if (!RegisterHotKey(hMainWnd, RWinKey, MOD_WIN, VK_RWIN))
					{
						GlobalDeleteAtom(RWinKey);
						RWinKey = 0;
					}
				}
			}
			if (RWinKey == 0){
				if (jks.pRWinKey != NULL){
					free(jks.pRWinKey);
					jks.pRWinKey = NULL;
				}
				if(!jks.bNoWarn)
					ERRORBOX("Error registering Right WinKey!");
			}
		}else
			jks.pRWinKey = NULL;
	}

	// set low-level keyboard hook
	// it cannot be set up in Win95,98,98SE and WinNT 4.x
	// WH_KEYBOARD_LL required at least WinME or Win2k
	// but tested only in XP :)
	hLowLevelKeyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL,
											 (HOOKPROC) LLKeyboardProc,
											 dllInst,
											 0L
											 );	
	/*
	hShellHook = SetWindowsHookEx(	WH_SHELL,
									(HOOKPROC) ShellProc,
									dllInst,
									0L	);
	*/
	// Get hotkey definitions
	loadKeys();

	{	//register message for version info
		UINT Msgs[] = {LM_GETREVID, LM_APPCOMMAND, 0};
		SendMessage(hParentWnd, LM_REGISTERMESSAGE, (WPARAM)hMainWnd, (LPARAM)Msgs);
	}
	return 0;
}

// quit the module

int ErrorBox( HWND hWnd, LPCSTR pszText, DWORD dwErrorCode, LPCSTR pszTitle, UINT nFlags )
{
	char szMessage[MAX_PATH];
	int nLen;

	lstrcpyn(szMessage, pszText, MAX_PATH - 1);
	lstrcat(szMessage, " ");
	nLen = lstrlen(szMessage);

	FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM, 0, dwErrorCode,
	              MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), szMessage + nLen,
	              MAX_PATH - nLen, NULL);

	return MessageBox( hWnd, szMessage, pszTitle, nFlags | MB_TOPMOST);
}


VOID quitModule( HINSTANCE dllInst )
{
	{	//unregister message for version info
		UINT Msgs[] = {LM_GETREVID, LM_APPCOMMAND, 0};
		SendMessage(hParentWnd, LM_UNREGISTERMESSAGE, (WPARAM)hMainWnd, (LPARAM)Msgs);
	}

	if (LWinKey){
		KillTimer(hMainWnd, 1);
		UnregisterHotKey(hMainWnd, LWinKey);
		DeleteAtom(LWinKey);
		LWinKey = 0;
	}
	if (jks.pLWinKey != NULL){
		free(jks.pLWinKey);
		jks.pLWinKey = NULL;
	}

	if (RWinKey){
		KillTimer(hMainWnd, 2);
		UnregisterHotKey(hMainWnd, RWinKey);
		DeleteAtom(RWinKey);
		RWinKey = 0;
	}
	if (jks.pRWinKey != NULL){
		free(jks.pRWinKey);
		jks.pRWinKey = NULL;
	}

	if (hLowLevelKeyboardHook != NULL)
	{
		if (UnhookWindowsHookEx(hLowLevelKeyboardHook) == FALSE)
		{
			ErrorBox(NULL,"Low-level hook: ",GetLastError(),"AnyKey",MB_OK);
		}
	} 
	/*
	if (hShellHook != NULL)
	{
		if (UnhookWindowsHookEx(hShellHook) == FALSE)
		{
			ErrorBox(NULL,"ShellHook: ",GetLastError(),"AnyKey",MB_OK);
		}
	}
	*/


	freeKeyList(hotkeys, &numhKeys);
	freeKeyList(scankeys, &numsKeys);
	freeKeyList(appkeys, &numaKeys);
	freeVKTable();

	if (hMainWnd != NULL)
	{
		DestroyWindow(hMainWnd);
	}

	UnregisterClass(szAppClass, dllInst);

	return;
}

LRESULT CALLBACK WndProc( HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam )
{
	SHORT bCtrl, bAlt, bShift, bWin, AppCommand;
	UINT i;
	switch (message)
	{
		case LM_GETREVID:
			strcpy((LPTSTR)lParam, aboutStr);
			return strlen((LPTSTR)lParam);

		case LM_APPCOMMAND:
			bCtrl		= (SHORT)(0x8000 & GetKeyState(VK_CONTROL));
			bAlt		= (SHORT)(0x8000 & GetKeyState(VK_MENU));
			bShift		= (SHORT)(0x8000 & GetKeyState(VK_SHIFT));
			bWin		= (SHORT)(0x8000 & GetKeyState(VK_SHIFT));
			AppCommand	= GET_APPCOMMAND_LPARAM(wParam);
			for (i=0;i<numaKeys;i++)
			{
				if (appkeys[i].ckey == (unsigned int)AppCommand)
				{
					if ((appkeys[i].modkey & MOD_WIN)		&& !bWin)	continue;
					if ((appkeys[i].modkey & MOD_ALT)		&& !bAlt)	continue;
					if ((appkeys[i].modkey & MOD_SHIFT)		&& !bShift)	continue;
					if ((appkeys[i].modkey & MOD_CONTROL)	&& !bCtrl)	continue;
					LSExecute(hMainWnd, appkeys[i].cmd, 0);
					return 1;
				}
			}
			break;

		case WM_CLOSE:
			return 0;

		case WM_SYSCOMMAND:
			switch (wParam)
			{
				case SC_CLOSE:
					return 0;
				default:
					break;
			}
			break;

		case WM_DESTROY:
			hMainWnd = NULL;
			return 0;

		case WM_HOTKEY:
			if (isKeyInList((ATOM)wParam))
			{
				if (LWinKey)
					KillTimer(hMainWnd, 1);
				if (RWinKey)
					KillTimer(hMainWnd, 2);
				LSExecute(hMainWnd, hotkeys[getKeyById((ATOM)wParam)].cmd, 0);
			}
			else if (LWinKey && (ATOM)wParam == LWinKey)
				SetTimer(hMainWnd, 1, jks.nLWinKeyTimeout, (TIMERPROC)NULL);
			else if (RWinKey && (ATOM)wParam == RWinKey)
				SetTimer(hMainWnd, 2, jks.nRWinKeyTimeout, (TIMERPROC)NULL);
			break;

		case WM_TIMER:
			if (wParam == 1)
			{
				KillTimer(hMainWnd, 1);
				LSExecute(hMainWnd, jks.pLWinKey, 0);
			}
			else if (wParam == 2)
			{
				KillTimer(hMainWnd, 2);
				LSExecute(hMainWnd, jks.pRWinKey, 0);
			}
			return 0;
		
		default:
			break;
	}
	return DefWindowProc(hwnd,message,wParam,lParam);
}


BOOL loadKeyFromString(char *buffer, TKey *tmpKey, char *cmdstr)
{
	UINT count = 0;

	char token0[128], token1[128], token2[128];
	LPTSTR tokens[3];
	tokens[0] = token0;
	tokens[1] = token1;
	tokens[2] = token2;

	*token0 = *token1 = *token2 = 0;
	*cmdstr = 0;

	if	(	((count = LCTokenize(buffer, tokens, 3, cmdstr)) != 3 || *cmdstr == 0) ||
			(!(stripWS(token1) && stripWS(token2) && stripWS(cmdstr)))
		)
	{
		if (!jks.bNoWarn)
		{
			sprintf(cmdstr, "Invalid format. Contains too few (or empty) parameters.\n\nError in definition:\n%s", buffer);
			ERRORBOX(cmdstr);
		}
		return FALSE;
	}

	memset(tmpKey, 0, sizeof(TKey));

	tokens[1] = strtok(token1, "+");

	while (tokens[1] != NULL)
	{
		if (!stricmp(tokens[1], "win"))
			tmpKey->modkey |= MOD_WIN;
		else if (!stricmp(tokens[1], "ctrl"))
			tmpKey->modkey |= MOD_CONTROL;
		else if (!stricmp(tokens[1], "alt"))
			tmpKey->modkey |= MOD_ALT;
		else if (!stricmp(tokens[1], "shift"))
			tmpKey->modkey |= MOD_SHIFT;
		else if (!stricmp(tokens[1], ".none"))
			tmpKey->modkey = 0;
		else
		{
			if (!jks.bNoWarn)
			{
				sprintf(cmdstr, "Invalid <modkey> parameter: %s\n\nError in definition:\n%s", tokens[1], buffer);
				ERRORBOX(cmdstr);
			}
			return FALSE;
		}
		tokens[1] = strtok(NULL, "+");
	}

	tokens[1] = token1; // move pointer back to beginning of token1
	
	if (strlen(token2) == 1)
	{
		tmpKey->ckey = (0x000000FF & VkKeyScan(*token2));
		if (tmpKey->ckey == 0xFF) // Error occured, trying to use U.S. English keyboard layout
		{
			tmpKey->ckey = (0x000000FF & VkKeyScanEx(*token2,LoadKeyboardLayout("00000409",0)));
			if (tmpKey->ckey == 0xFF) // still error
				tmpKey->ckey = 0;
		}
	}
	else
	{
		for (count=0; count<numvKeys && !tmpKey->ckey; count++)
		{
			if (!stricmp(vkTable[count].key, token2))
				tmpKey->ckey = vkTable[count].vkey;
		}
	}

	if (!tmpKey->ckey)
	{
		if (!jks.bNoWarn)
		{
			sprintf(cmdstr, "Invalid <hotkey> - \"%s\"\n\nError in definition:\n%s", token2, buffer);
			ERRORBOX(cmdstr);
		}
		return FALSE;
	}
	return TRUE;
}

VOID loadHookConfig(char *cfg, TKey **keys, UINT *numKeys)
{
	char buffer[4096];
	char cmdstr[4096];
	TKey tmpKey;
	FILE *f = LCOpen(NULL);
	if (f)
	{
		*buffer = 0;
		while (LCReadNextConfig(f, cfg, buffer, 4096))
		{
			if (!loadKeyFromString(buffer,&tmpKey, cmdstr))
				continue;			
			tmpKey.id = 0;
			tmpKey.cmd = (LPTSTR)malloc(strlen(cmdstr)+1);
			if (tmpKey.cmd != NULL)
			{
				TKey *tempKeys = *keys;

				strcpy(tmpKey.cmd, cmdstr);
				if (!(*keys))
					*keys = (TKey *)malloc(sizeof(TKey));
				else
					*keys = (TKey *)realloc(*keys, ((*numKeys)+1)*sizeof(TKey));
				if (*keys == NULL)
				{
					*keys = tempKeys;
					free(tmpKey.cmd);
					if (!jks.bNoWarn)
					{
						sprintf(cmdstr, reserrStr, buffer);
						ERRORBOX(cmdstr);
					}
				}
				else
				{
					memcpy((*keys)+ (*numKeys), &tmpKey, sizeof(TKey));
					++(*numKeys);
				}
				tempKeys = NULL;
			}
			*buffer = 0;
		}
		LCClose(f);
	}
}

VOID loadKeys()
{
	char buffer[4096];
	char cmdstr[4096];
	char idstr[13];
	TKey tmpKey;

	FILE *f;

	// regular hotkeys

	f = LCOpen(NULL);
	if (f)
	{
		*buffer = 0;
		while (LCReadNextConfig(f, "*HotKey", buffer, 4096))
		{
			if (!loadKeyFromString(buffer,&tmpKey, cmdstr))
			{
				*buffer = 0;
				continue;
			}
			*idstr = 0;
			sprintf(idstr, "ANYKEY%08X", numhKeys);
			tmpKey.id = GlobalAddAtom( idstr );
			if (!tmpKey.id)
			{
				if (!jks.bNoWarn)
				{
					sprintf(cmdstr, reserrStr, buffer);
					ERRORBOX(cmdstr);
				}
				continue;
			}
			tmpKey.cmd = (LPTSTR)malloc(strlen(cmdstr)+1);
			if (tmpKey.cmd != NULL)
			{
				strcpy(tmpKey.cmd, cmdstr);
				if (!RegisterHotKey(hMainWnd,tmpKey.id,tmpKey.modkey,tmpKey.ckey))
				{
					GlobalDeleteAtom(tmpKey.id);
					free(tmpKey.cmd);
					if (!jks.bNoWarn){
						sprintf(cmdstr, "Hotkey failed to register.\n\nError while processing definition:\n%s", buffer);
						ERRORBOX(cmdstr);
					}
				}
				else
				{
					TKey * tempKeys = hotkeys;
					if (!hotkeys)
						hotkeys = (TKey *)malloc(sizeof(TKey));
					else
						hotkeys = (TKey *)realloc(hotkeys, (numhKeys+1)*sizeof(TKey));
					if (hotkeys == NULL)
					{
						hotkeys = tempKeys;
						free(tmpKey.cmd);
						UnregisterHotKey(hMainWnd, tmpKey.id);
						GlobalDeleteAtom(tmpKey.id);
						if (!jks.bNoWarn)
						{
							sprintf(cmdstr, reserrStr, buffer);
							ERRORBOX(cmdstr);
						}
					}
					else
					{
						memcpy(&hotkeys[numhKeys], &tmpKey, sizeof(TKey));
						++numhKeys;
					}
					tempKeys = NULL;
				}
			}
			*buffer = 0;
		}
		LCClose(f);
	}

	//*ScanKey and *AppKey
	
	loadHookConfig("*ScanKey",&scankeys,&numsKeys);
	loadHookConfig("*AppKey",&appkeys,&numaKeys);
	return;
}

VOID loadVKTable(LPTSTR table)
{
	FILE *f;
	tVKTable tmpTable;
	char tmpBuf[128];
	char tBuf[128];
	UINT nKey;

	f = fopen(table, "r");
	if (f != NULL)
		fseek(f, 0, SEEK_SET);
	else
		return;

	numvKeys = 0;
	while (f && !ferror(f) && !feof(f))
	{
		if (!fgets(tmpBuf, 128, f))
			continue;
		if (stripWS(strupr(tmpBuf)) && *tmpBuf != ';')
		{
			*tBuf = 0;
			nKey = 0;
			if (sscanf(tmpBuf, "%s , %08X", tBuf, &nKey))
			{
				if (*tBuf != 0 && nKey != 0)
				{
					memset(&tmpTable, 0, sizeof(tVKTable));
					tmpTable.key = (LPTSTR)malloc(strlen(tBuf)+1);
					if (tmpTable.key != NULL)
					{
						tVKTable * tempVKT = vkTable;

						strcpy(tmpTable.key, tBuf);
						tmpTable.vkey = nKey;

						if (!vkTable)
							vkTable = (tVKTable *)malloc(sizeof(tVKTable));
						else
							vkTable = (tVKTable *)realloc(vkTable, (numvKeys+1)*sizeof(tVKTable));
						if (vkTable == NULL){
							vkTable = tempVKT;
							free (tmpTable.key);
							tmpTable.key = NULL;
						}else{
							memcpy(&vkTable[numvKeys], &tmpTable, sizeof(tVKTable));
							++numvKeys;
						}
					}
				}
			}
		}
	}
	fclose(f);
	return;
}

VOID freeKeyList(TKey *keys, UINT *numKeys)
{
	UINT i;
	for (i=0;i<*numKeys;i++)
	{
		UnregisterHotKey(hMainWnd,keys[i].id);
		GlobalDeleteAtom(keys[i].id);
		keys[i].id = 0;
		if (keys[i].cmd != NULL)
		{
			free(keys[i].cmd);
			keys[i].cmd = NULL;
		}
	}
	if (keys != NULL)
	{
		free(keys);
		keys = NULL;
	}
	*numKeys = 0;
	return;
}

VOID freeVKTable( VOID )
{
	UINT i;
	for (i=0;i<numvKeys;i++)
	{
		free(vkTable[i].key);
		vkTable[i].key = NULL;
	}
	if (vkTable != NULL)
	{
		free(vkTable);
		vkTable = NULL;
	}
	return;
}

BOOL stripWS (LPTSTR buffer)
{
	size_t length = buffer != NULL ? strlen(buffer):0;
	if (length){
		LPTSTR tmpBuf = buffer;
		while (length && isspace(*tmpBuf))
		{
			++tmpBuf;
			--length;
		}
		if (length)
		{
			while (length && isspace(tmpBuf[length-1]))
			{
				tmpBuf[--length] = 0;
			}
			if (tmpBuf != buffer)
			{
				strcpy(buffer, tmpBuf);
			}
		}
	}
	return (length != 0);
}

BOOL isKeyInList(ATOM id)
{
	UINT i;

	for (i=0;i<numhKeys;i++)
	{
		if (hotkeys[i].id == id)
			return TRUE;
	}

	return FALSE;
}

UINT getKeyById(ATOM id)
{
	UINT i;

	for (i=0;i<numhKeys;i++)
	{
		if (hotkeys[i].id == id)
			return i;
	}

	return i;
}

LRESULT CALLBACK LLKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam)
{
	if (nCode>=0 && scankeys)
	{
		LPKBDLLHOOKSTRUCT ks = (LPKBDLLHOOKSTRUCT)lParam;
		if (wParam == WM_KEYUP && ks->vkCode == 0xFF)
		{
			SHORT bCtrl		= (SHORT)(0x8000 & GetKeyState(VK_CONTROL));
			SHORT bAlt		= (SHORT)(0x8000 & GetKeyState(VK_MENU));
			SHORT bShift	= (SHORT)(0x8000 & GetKeyState(VK_SHIFT));
			SHORT bWin		= (SHORT)(0x8000 & GetKeyState(VK_SHIFT));
			UINT i;
			for (i=0;i<numsKeys;i++)
			{
				if (scankeys[i].ckey == ks->scanCode)
				{
					if ((scankeys[i].modkey & MOD_WIN)		&& !bWin)	continue;
					if ((scankeys[i].modkey & MOD_ALT)		&& !bAlt)	continue;
					if ((scankeys[i].modkey & MOD_SHIFT)	&& !bShift)	continue;
					if ((scankeys[i].modkey & MOD_CONTROL)	&& !bCtrl)	continue;
					LSExecute(hMainWnd, scankeys[i].cmd, 0);
					return 1;
				}
			}
		}
	}
	return CallNextHookEx(hLowLevelKeyboardHook, nCode, wParam, lParam);
}

