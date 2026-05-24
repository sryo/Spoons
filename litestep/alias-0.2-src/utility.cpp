//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  utility.cpp
//  This is a part of the alias source code.
//
//  Copyright (C) 2004-2008 ilmcuts
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
//
//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#include "utility.hpp"

using std::string;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ErrorMessage
//
void ErrorMessage(LPCTSTR pszFormat, ...)
{
    char szMessage[MAX_LINE_LENGTH] = { 0 };
    va_list argList;
    
    va_start(argList, pszFormat);
    StringCchVPrintf(szMessage, MAX_LINE_LENGTH, pszFormat, argList);
    va_end(argList);
    
    MessageBox(NULL, szMessage, "alias Error",
        MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
}

void ErrorMessage(DWORD dwCode)
{
    char szMessage[MAX_LINE_LENGTH] = { 0 };
    GetErrorString(dwCode, szMessage, MAX_LINE_LENGTH);

    ErrorMessage(szMessage);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// EnumConfig
//
bool EnumConfig(LPCSTR pszFile, const string& sConfig, ConfigCallback fnCallback)
{
    FILE* f = LCOpen(pszFile);
    
    if (!f)
    {
        char szWhat[MAX_LINE_LENGTH] = { 0 };
        
        StringCchPrintf(szWhat, MAX_LINE_LENGTH, "Could not open \"%s\"",
            pszFile ? pszFile : "step.rc");
        
        throw std::runtime_error(szWhat);
    }
    
    bool bReturn = true;
    
    try
    {
        char szLine[MAX_LINE_LENGTH] = { 0 };
        
        while (LCReadNextConfig(f, sConfig.c_str(), szLine, MAX_LINE_LENGTH))
        {
            LPCSTR pszValue = NULL;
            GetToken(szLine, NULL, &pszValue, FALSE);
            
            if (pszValue)
            {
                if (!fnCallback(pszValue))
                {
                    bReturn = false;
                    break;
                }
            }
        }
    }
    catch (...)
    {
        LCClose(f);
        throw;
    }
    
    LCClose(f);
    
    return bReturn;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// CreateMessageWindow
//
HWND CreateMessageWindow(HINSTANCE hInst, LPCSTR pszClass, LPCSTR pszWndName)
{
    HWND hParent = NULL;

    OSVERSIONINFO ovi = { 0 };
    ovi.dwOSVersionInfoSize = sizeof(OSVERSIONINFO);

    if (GetVersionEx(&ovi) &&  // FIXME: different error return if this fails?
        ovi.dwPlatformId == VER_PLATFORM_WIN32_NT &&
        ovi.dwMajorVersion >= 5)
    {
        hParent = HWND_MESSAGE;
    }

    return CreateWindowEx(
        WS_EX_NOPARENTNOTIFY | WS_EX_TOOLWINDOW,
        pszClass, pszWndName,
        WS_POPUP,
        0, 0, 0, 0,
        hParent, NULL,
        hInst,
        NULL);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// GetErrorString
//
BOOL GetErrorString(DWORD dwCode, LPSTR pszBuffer, DWORD cchBuffer)
{
    BOOL bReturn = FALSE;

    // FIXME: could let this through...
    if (pszBuffer && cchBuffer > 0)
    {
        bReturn = (0 != FormatMessage(
            FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
            NULL,
            dwCode,
            0,
            pszBuffer,
            cchBuffer,
            NULL
            ));
    }
    else
    {
        SetLastError(ERROR_INVALID_PARAMETER);
    }

    return bReturn;
}
