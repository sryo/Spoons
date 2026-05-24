/*
    This software displays the ScanCode of any key pressed on the keyboard.

    Copyright (C) 2000 Chris Rempel

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

    Contact info: jugg@hotmail.com
*/

#include <tchar.h>
#include <windows.h>
#include <winuser.h>
#include <stdio.h>

#ifndef WM_APPCOMMAND
#define WM_APPCOMMAND 0x319
#endif

#ifndef KBDLLHOOKSTRUCT
typedef struct tagKBDLLHOOKSTRUCT {
    DWORD   vkCode;
    DWORD   scanCode;
    DWORD   flags;
    DWORD   time;
    ULONG_PTR dwExtraInfo;
} KBDLLHOOKSTRUCT, FAR *LPKBDLLHOOKSTRUCT, *PKBDLLHOOKSTRUCT;
#endif

#ifndef GET_APPCOMMAND_LPARAM
#define GET_APPCOMMAND_LPARAM(lParam) ((short)(HIWORD(lParam) & ~FAPPCOMMAND_MASK))
#endif

#ifndef FAPPCOMMAND_MASK
#define FAPPCOMMAND_MASK  0xF000
#endif

LPCTSTR szAppClass = _T("ScanKeyClass"); // Class Name
LPCTSTR szAppName = _T("Press a key, any key."); // Window Name

HWND hMainWnd;
HINSTANCE hMainInst;

HHOOK kHook;
_TCHAR sCodeVk[128] = _T("");
_TCHAR sCodeSc[128] = _T("");
_TCHAR sCodeAp[128] = _T("");

LRESULT CALLBACK WndProc( HWND, UINT, WPARAM, LPARAM );
LRESULT CALLBACK KeyboardProc( _TINT, WPARAM, LPARAM );

RECT r;

typedef BOOL (*MYIMPORTEDPROC)(HWND hWnd);


INT WINAPI _tWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, INT nCmdShow)
{
	MSG msg;
	_TINT nMsg;

	HINSTANCE hinstDLL;
	MYIMPORTEDPROC SetHooks;
	MYIMPORTEDPROC UnSetHooks;

	nCmdShow=nCmdShow;
	lpCmdLine=lpCmdLine;
	hPrevInstance=hPrevInstance;
	hMainInst = hInstance;

	{
		WNDCLASS wc;
		memset(&wc, 0, sizeof(wc));
		wc.hbrBackground = NULL;
		wc.hCursor = LoadCursor(NULL, IDC_ARROW);
		wc.hIcon = LoadIcon(NULL, IDI_INFORMATION);

		wc.hInstance = hMainInst;
		wc.lpfnWndProc = (WNDPROC)WndProc;
		wc.lpszClassName = szAppClass;

		wc.style = 0;

		if (!RegisterClass(&wc)){
			MessageBox(NULL,_T("Error registering window class"),szAppClass,MB_OK|MB_ICONERROR|MB_SYSTEMMODAL);
			return 0;
		}
	}

	hMainWnd = CreateWindowEx(WS_EX_TOOLWINDOW|WS_EX_TOPMOST|WS_EX_APPWINDOW,szAppClass,szAppName,WS_POPUP|WS_VISIBLE|WS_BORDER|WS_CAPTION|WS_SYSMENU,CW_USEDEFAULT,CW_USEDEFAULT,150,150,NULL,NULL,hMainInst,NULL);
	if (hMainWnd == NULL){
		MessageBox(NULL,_T("Error creating window!"),szAppName,MB_OK|MB_ICONERROR|MB_SYSTEMMODAL);
		UnregisterClass(szAppClass, hMainInst);
		return 0;
	}

	kHook = SetWindowsHookEx(WH_KEYBOARD, (HOOKPROC)KeyboardProc, NULL, GetCurrentThreadId());

	hinstDLL = LoadLibrary(_T(/*"MMShellHook.dll"*/ "skhook.dll")); 
	SetHooks = (MYIMPORTEDPROC)GetProcAddress(hinstDLL, "SetHooks"); 
	UnSetHooks = (MYIMPORTEDPROC)GetProcAddress(hinstDLL, "UnSetHooks");
	if (!hinstDLL || !SetHooks || !UnSetHooks)
	{
		MessageBox(NULL,"skhooks.dll not found or corrupt!","Scnakey",MB_OK|MB_ICONERROR|MB_SYSTEMMODAL);
		return 2;
	}
	SetHooks(hMainWnd);

	GetClientRect(hMainWnd, &r);
	InvalidateRect(hMainWnd, NULL, TRUE);

	while ((nMsg = GetMessage(&msg,NULL,0,0)) != -1 && nMsg){
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}

	if (hMainWnd != NULL){
		UnSetHooks(hMainWnd);
		DestroyWindow(hMainWnd);
		hMainWnd = NULL;
	}

	UnhookWindowsHookEx( kHook );

	return msg.wParam;
}

LRESULT CALLBACK KeyboardProc( _TINT code, WPARAM wParam, LPARAM lParam )
{
	_stprintf(sCodeVk, _T("%s %08X"), _T("VkCode:  "), wParam);
	InvalidateRect(hMainWnd, NULL, TRUE);
	return CallNextHookEx(kHook, code, wParam, lParam);
}

LRESULT CALLBACK WndProc ( HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam ){
	switch(uMsg){
		case WM_PAINT:
			{
				PAINTSTRUCT ps;
				HDC hdc = BeginPaint(hwnd, &ps);
				HDC bufhdc = CreateCompatibleDC(hdc);

				HBITMAP workbmp = CreateCompatibleBitmap(hdc, r.right-r.left, r.bottom-r.top);
				HBITMAP oldbmp = (HBITMAP) SelectObject(bufhdc, workbmp);

				HBRUSH bgBrush = (HBRUSH) GetStockObject(GRAY_BRUSH);
				HBRUSH oldBrush = (HBRUSH) SelectObject(bufhdc, bgBrush);

				FillRect(bufhdc, &r, bgBrush);
				SelectObject(bufhdc, oldBrush);
				DeleteObject(bgBrush);


				SetBkMode(bufhdc, TRANSPARENT);

				{
					HFONT Font, oldFont;
					Font = CreateFont(16, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, PROOF_QUALITY, DEFAULT_PITCH|FF_DONTCARE, _T("Arial"));
					oldFont = (HFONT) SelectObject(bufhdc, Font);

					if (*sCodeVk)
						TextOut(bufhdc, 8,   8, sCodeVk, strlen(sCodeVk));
					if (*sCodeSc)
						TextOut(bufhdc, 8,  58, sCodeSc, strlen(sCodeSc));
					if (*sCodeAp)
						TextOut(bufhdc, 8, 108, sCodeAp, strlen(sCodeAp));

					SelectObject(bufhdc, oldFont);
					DeleteObject(Font);
				}

				BitBlt(hdc,0,0,r.right-r.left,r.bottom-r.top,bufhdc,0,0,SRCCOPY);

				SelectObject(bufhdc,oldbmp);
				DeleteObject(workbmp);
				DeleteDC(bufhdc);
				EndPaint(hwnd, &ps);
			}
			break;

		case WM_DESTROY:
			hMainWnd = NULL;
			PostQuitMessage(0);
			break;
		case WM_USER + 1:
			_stprintf(sCodeSc, _T("%s %08X"), _T("ScCode:"), ((PKBDLLHOOKSTRUCT)lParam)->scanCode);
			break;

		case WM_APPCOMMAND:
			_stprintf(sCodeAp, _T("%s %08X"), _T("ApCode:"), GET_APPCOMMAND_LPARAM(lParam));
			break;			

		default:
			return DefWindowProc(hwnd,uMsg,wParam,lParam);
	}
	return 0;
}