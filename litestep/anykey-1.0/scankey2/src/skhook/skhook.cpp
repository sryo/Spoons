// skhook.cpp : Defines the entry point for the DLL application.
//

#include "skhook.h"
#include <tchar.h>
#include <windows.h>
#include <winuser.h>

/////////////////////////////////////////////////////////////////////////////
// Storage for the global data in the DLL

#pragma data_seg(".shared")
HWND hNotifyWnd = NULL;
HHOOK hKbdLLHook = NULL;				// Handle to low level keyboard hook
#pragma data_seg( )
/////////////////////////////////////////////////////////////////////////////
// Per-instance DLL variables

HINSTANCE hInstance = NULL;							// This instance of the DLL

//LRESULT CALLBACK ShellProc (int nCode, WPARAM wParam, LPARAM lParam);
LRESULT CALLBACK KbdLLProc (int nCode, WPARAM wParam, LPARAM lParam);


// The DLL's main procedure
BOOL WINAPI DllMain (HANDLE hInst, ULONG ul_reason_for_call, LPVOID lpReserved)
{
	// Find out why we're being called
	switch (ul_reason_for_call)
	{

	case DLL_PROCESS_ATTACH:
		// Save the instance handle
		hInstance = (HINSTANCE)hInst;
		// ALWAYS return TRUE to avoid breaking unhookable applications!!!
		return TRUE;

	case DLL_PROCESS_DETACH:
		return TRUE;

	default:
		return TRUE;
	}
}

// Add the new hook

DllExport BOOL SetHooks(HWND hWnd)
{

	// Don't add the hook if the window ID is NULL
	if (hWnd == NULL)
		return FALSE;
	
	// Don't add a hook if there is already one added
	if (hNotifyWnd != NULL)
		return FALSE;

	hKbdLLHook = SetWindowsHookEx(
					WH_KEYBOARD_LL,					// Hook in before msg reaches app
					(HOOKPROC) KbdLLProc,			// Hook procedure
					hInstance,						// This DLL instance
					0L								// Hook in to all apps
					);


	// Check that it worked
	if (/*hShellHook != NULL || */hKbdLLHook != NULL)
	{

		hNotifyWnd = hWnd;						// Save the WinRFB window handle
		return TRUE;
	}
	// The hook failed, so return an error code
	return FALSE;
}


// Remove the hook from the system
DllExport BOOL UnSetHooks(HWND hWnd)
{
	BOOL unHooked = TRUE;
	
	// Is the window handle valid?
	if (hWnd == NULL)
		MessageBox(NULL, _T("Window pointer is null"), _T("Message"), MB_OK);

	// Is the correct application calling UnSetHook?
	if (hWnd != hNotifyWnd)
		return FALSE;
	// Unhook the procs
	if (hNotifyWnd != NULL)
	{
		unHooked = UnhookWindowsHookEx(hKbdLLHook);
		hKbdLLHook = NULL;
	}
	// If we managed to unhook then reset
	if (unHooked)
	{
		hNotifyWnd = NULL;
	}

	return unHooked;

}

// Hook procedure for low-level keyboard hook

LRESULT CALLBACK KbdLLProc(int nCode, WPARAM wParam, LPARAM lParam)
{
	if (wParam == WM_KEYUP)
	{
		SendMessage(hNotifyWnd,WM_USER+1,wParam,lParam);
	}
	return CallNextHookEx(hKbdLLHook, nCode, wParam, lParam);
}
  