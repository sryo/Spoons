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
#ifndef ALIAS_UTILITY_HPP_INCLUDED
#define ALIAS_UTILITY_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

#include "common.hpp"
// #include <boost/function.hpp>


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// stringicmp
//
// provides case insensitive string comparison for std::map
//
struct stringicmp
{
    bool operator()(const std::string& s1, const std::string& s2) const
    {
        return (lstrcmpi(s1.c_str(), s2.c_str()) < 0);
    }
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// typedefs
//
typedef bool (* ConfigCallback)(LPCSTR);
// typedef boost::function1<bool, LPCSTR> ConfigCallback;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Function prototypes
//
void ErrorMessage(DWORD dwCode);
void ErrorMessage(const char* pszFormat, ...);
inline void ErrorMessage(const std::string& sMessage)
{
    ErrorMessage(sMessage.c_str());
}

// throws runtime_error plus whatever the callback throws
bool EnumConfig(LPCSTR pszFile, const std::string& sConfig,
                ConfigCallback fnCallback);

HWND CreateMessageWindow(HINSTANCE hInst, LPCSTR pszClass, LPCSTR pszWndName);
BOOL GetErrorString(DWORD dwCode, LPSTR pszBuffer, DWORD cchBuffer);


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// DEFAULT_NOTREACHABLE
//
#ifdef _DEBUG
#  define DEFAULT_NOTREACHABLE default: ASSERT(0); break
#elif _MSC_VER >= 1200
#  define DEFAULT_NOTREACHABLE default: __assume(0); break
#else
#  define DEFAULT_NOTREACHABLE default: break
#endif;


#endif // !defined(ALIAS_UTILITY_HPP_INCLUDED)
