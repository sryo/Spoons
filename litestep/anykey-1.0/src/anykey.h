#ifndef __ANYKEY_H
#define __ANYKEY_H

#ifndef KBDLLHOOKSTRUCT
typedef struct tagKBDLLHOOKSTRUCT {
    DWORD   vkCode;
    DWORD   scanCode;
    DWORD   flags;
    DWORD   time;
    ULONG_PTR dwExtraInfo;
} KBDLLHOOKSTRUCT, FAR *LPKBDLLHOOKSTRUCT, *PKBDLLHOOKSTRUCT;
#endif

#ifndef WH_KEYBOARD_LL
#define WH_KEYBOARD_LL     13
#endif

#ifndef WM_APPCOMMAND
#define FAPPCOMMAND_MASK			0xF000
#define GET_APPCOMMAND_LPARAM(lParam) ((SHORT)(HIWORD(lParam) & ~FAPPCOMMAND_MASK))
#endif

#define ERRORBOX(x) MessageBox(NULL,x,"AnyKey",MB_OK|MB_ICONERROR|MB_DEFBUTTON1|MB_SYSTEMMODAL)

typedef struct tagtVKTable{
	LPTSTR key;
	UINT vkey;
} tVKTable;

typedef struct tagTKey{
	LPTSTR cmd;
	UINT ckey;
	UINT modkey;
	ATOM id;
} TKey;

typedef struct tagTSettings{
	BOOL bNoWarn;
	LPTSTR pLWinKey, pRWinKey;
	int nLWinKeyTimeout, nRWinKeyTimeout;
} TSettings;

#ifdef __cplusplus
	extern "C" {
#endif

		__declspec( dllexport ) INT initModuleEx ( HWND, HINSTANCE, LPCTSTR );
		__declspec( dllexport ) VOID quitModule ( HINSTANCE );

#ifdef __cplusplus
	}
#endif

#endif
