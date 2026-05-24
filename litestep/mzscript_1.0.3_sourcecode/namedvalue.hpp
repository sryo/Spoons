#ifndef LSSDK_NAMEDVALUE_HPP_INCLUDED
#define LSSDK_NAMEDVALUE_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  namedvalue.hpp
//  This is a part of the LS C/C++ SDK source code.
//
//  Copyright (C) 2003 ilmcuts.
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

#include <windows.h> // TODO: add windows_select header
//#include "debug.hpp"


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// NamedValue
//
// This could be done with std::map or std::pair but sometimes that's overkill
//
template <class Value, Value t_default = 0, class Name = const TCHAR*>
struct NamedValue
{
    Name name;
    Value value;
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// LookupValue
//
template <class T, T t_def>
T LookupValue(const char* pszName, const NamedValue<T, t_def>* nvArray, size_t stCount)
{
    ASSERT(pszName);
    ASSERT(nvArray);
    ASSERT(stCount > 0);

    for (size_t stCounter = 0; stCounter < stCount; ++stCounter)
    {
        if (!lstrcmpi(nvArray[stCounter].name, pszName))
        {
            return nvArray[stCounter].value;
        }
    }
    
    return t_def;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// macro COUNTOF
//
#ifndef COUNTOF
#define COUNTOF(array) (sizeof(array)/sizeof(array[0]))
#endif


#endif // !defined(LSSDK_NAMEDVALUE_HPP_INCLUDED)
