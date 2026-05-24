//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  alias.hpp
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
#ifndef ALIAS_ALIAS_HPP_INCLUDED
#define ALIAS_ALIAS_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

#include "common.hpp"
#include "utility.hpp"


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Constants
//

// don't forget to change this in the version resource as well
const char g_strAppName[] = "alias";
const char g_strAppVersion[] = "0.2.0";


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Function prototypes
//
void LoadSetup();
void ClearSetup();

bool ParseAliasLine(LPCSTR strLine);
unsigned short CountVariables(LPCSTR strFormat);
bool FormatString(LPSTR strBuffer, DWORD cchBuffer, LPCSTR strFormat, LPCSTR* pstrArray);

void BangAlias(HWND, LPCSTR strArgs);
void BangAliasExec(HWND, LPCSTR strName, LPCSTR strArgs);


LRESULT CALLBACK WndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Exports
//
extern "C"
{
    __declspec(dllexport) int initModuleEx(HWND hLiteStep, HINSTANCE hInst, LPCSTR strPath);
    __declspec(dllexport) void quitModule(HINSTANCE hInst);
}

#endif // !defined(ALIAS_ALIAS_HPP_INCLUDED)
