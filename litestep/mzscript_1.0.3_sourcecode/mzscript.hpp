#ifndef MZSCRIPT_MZSCRIPT_HPP_INCLUDED
#define MZSCRIPT_MZSCRIPT_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  mzscript.hpp
//  This is a part of the mzscript source code.
//
//  Copyright (C) 2000-2003 the mzscript developers.
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

#include "common.hpp"

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Constants
//

// don't forget to change this in the version resource as well
const char g_szAppName[] = "mzscript";
const char g_szAppVersion[] = "1.0.3";


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// exception class invalid_token
//
class invalid_token : public std::invalid_argument
{
public:
    invalid_token(const std::string& sToken) : invalid_argument(sToken) { }
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// typedefs
//
typedef std::pair<std::string, std::string> Line;
typedef std::vector<Line> LineVector;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Function prototypes
//
void LoadSetup(bool bIsRefresh);   // invalid_argument, runtime_error
void ClearSetup();

void LoadScriptFile(LPCSTR pszFile, bool bIsRefresh); // throws invalid_argument, runtime_error

void LoadVarFile(LPCSTR pszFile);

bool EvalIf (std::string& sStatement);

void ExecCommand(const std::string& sCommand);

LRESULT CALLBACK WndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam);


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Exports
//
extern "C"
{
    __declspec(dllexport) int initModuleEx(HWND hLiteStep, HINSTANCE hInst, LPCSTR pszPath);
    __declspec(dllexport) void quitModule(HINSTANCE hInst);
}

#endif // !defined(MZSCRIPT_MZSCRIPT_HPP_INCLUDED)
