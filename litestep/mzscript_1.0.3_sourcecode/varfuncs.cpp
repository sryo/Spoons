//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  varfuncs.cpp
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

#include "varfuncs.hpp"
#include "variables.hpp"

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// SetupVarFuncs
//
void SetupVarFuncs()
{
	srand(time(NULL));
	//keep !varrnd from returning almost the same thing 
	//on !recycles that happen in a short period of time
	rand(); rand();

    const NamedValue<VarFunc> varFuncs[] =
    {
        "xresolution",  xRes,
        "yresolution",  yRes,
        "bpp",          bpp,

        "year",         yearF,
        "month",        monthF,
        "day",          dayF,
        "weekday",      weekdayF,
        "hour",         hourF,
        "minute",       minF,
        "second",       secF,
        "milli",        milliF,

        "mousex",       mousexF,
        "mousey",       mouseyF
    };
    
    for (size_t i = 0; i < COUNTOF(varFuncs); ++i)
    {
        g_Variables->Set(varFuncs[i].name, varFuncs[i].value);
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// xRes
//
std::string xRes()
{
    return string_cast(GetSystemMetrics(SM_CXSCREEN));
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// yRes
//
std::string yRes()
{
    return string_cast(GetSystemMetrics(SM_CYSCREEN));
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// bpp
//
std::string bpp()
{
    HKEY hkey = NULL;
    char bitspp[3] = { "16" };

    if (RegOpenKeyEx(HKEY_CURRENT_CONFIG, "Display\\Settings",
        NULL, KEY_READ, &hkey) == ERROR_SUCCESS)
    {
        DWORD dwType = REG_SZ;
        DWORD dwSize = sizeof(bitspp);

        RegQueryValueEx(hkey, "BitsPerPixel", NULL, &dwType,
            (PBYTE)&bitspp, &dwSize);
        
        RegCloseKey(hkey);
    }

    return bitspp;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// yearF
//
std::string yearF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wYear);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// monthF
//
std::string monthF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wMonth);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// dayF
//
std::string dayF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wDay);
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// weekdayF
//
std::string weekdayF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wDayOfWeek);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// hourF
//
std::string hourF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wHour);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// minF
//
std::string minF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wMinute);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// secF
//
std::string secF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wSecond);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// milliF
//
std::string milliF()
{
    SYSTEMTIME systemTime;
    GetLocalTime(&systemTime);

    return string_cast(systemTime.wMilliseconds);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mousexF
//
std::string mousexF()
{
    POINT p;
    GetCursorPos(&p);

    return string_cast(p.x);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mouseyF
//
std::string mouseyF()
{
    POINT p;
    GetCursorPos(&p);

    return string_cast(p.y);
}
