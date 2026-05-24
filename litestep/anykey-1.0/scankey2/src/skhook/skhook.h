#ifndef _ScankeyHook_DLL_
#define _ScankeyHook_DLL_

#include <windows.h>

#ifndef WH_KEYBOARD_LL
#define WH_KEYBOARD_LL     13
#endif



#define DllImport __declspec(dllimport)
#define DllExport __declspec(dllexport)

extern "C"
{
	DllExport BOOL SetHooks(HWND hWnd	);
	DllExport BOOL UnSetHooks(HWND hWnd);


}

#endif