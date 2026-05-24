#ifndef MZSCRIPT_UTILITY_HPP_INCLUDED
#define MZSCRIPT_UTILITY_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  utility.hpp
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

using std::string;


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
// exception class win32_error
//
class win32_error : public std::runtime_error
{
    mutable std::string m_sWhat;
    DWORD m_dwCode;
    
public:
    win32_error() : runtime_error(""), m_dwCode(GetLastError()) { }
    win32_error(DWORD dwCode) : runtime_error(""), m_dwCode(dwCode) { }
    
    virtual ~win32_error() { }
    
    virtual const char* what() const
    {
        if (m_sWhat.empty())
        {
            LPVOID lpBuffer = NULL;
            
            if (FormatMessage(
                FORMAT_MESSAGE_FROM_SYSTEM |
                FORMAT_MESSAGE_IGNORE_INSERTS |
                FORMAT_MESSAGE_ALLOCATE_BUFFER,
                NULL,
                m_dwCode,
                0,
                (LPSTR)&lpBuffer,
                0,
                NULL
                ))
            {
                m_sWhat.assign((LPCSTR)lpBuffer);
                LocalFree(lpBuffer);
            }
        }
        
        return m_sWhat.c_str();
    }
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// typedefs
//
typedef boost::function1<bool, LPCSTR> ConfigCallback;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Function prototypes
//
int AskUser (UINT uFlags, LPCSTR pszFormat, ...);
void ErrorMessage(LPCSTR pszType, LPCSTR pszFormat, ...);
std::string GetLastErrorStr();

// throws win32_error
HWND CreateMessageWindow(HINSTANCE hInst, LPCSTR pszClass, LPCSTR pszWndName);

// throws runtime_error plus whatever the callback throws
bool EnumConfig(LPCSTR pszFile, const std::string& sConfig,
                ConfigCallback fnCallback);

int StrIComp(const char* a, const char* b);
inline int StrIComp(const std::string& s1, const std::string& s2)
{
    return StrIComp(s1.c_str(), s2.c_str());
}

bool StrIEqual(const char* a, const char* b);
inline bool StrIEqual(const std::string& s1, const std::string& s2)
{
    return StrIEqual(s1.c_str(), s2.c_str());
}

bool isnum(const char* tmp);

inline bool isnum(const std::string& tmp)
{
    return isnum(tmp.c_str());
}

bool GetToken(LPCSTR pszString, LPSTR pszToken, LPCSTR* pszNextToken,
			  bool bUseBrackets, bool bAllowEmptyToken);

bool GetTokenPos(LPCSTR pszString, size_t& stStart, size_t& stEnd,
				 bool bUseBrackets, bool bAllowEmptyToken);


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// FormattedException
//
// yet another hack to avoid the iostreams for the time being
//
template <class Exception>
void FormattedException(LPCSTR pszFormat, ...)
{
    char  szMessage[MAX_LINE_LENGTH] = { 0 };
    va_list argList;
    
    va_start(argList, pszFormat);
    StringCchVPrintf(szMessage, MAX_LINE_LENGTH, pszFormat, argList);
    va_end(argList);

    throw Exception(szMessage);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// string_cast with specializations
//
/*template <typename Source> inline std::string string_cast(Source source)
{
    return boost::lexical_cast<std::string, Source>(source);
}*/

// the "right" way to do this is to use lexical_cast, but since that uses the
// iostreams we'll stay away from it for now and use an ugly printf hack...
template <typename T> inline std::string string_cast(T source);

template <> inline std::string string_cast(int source)
{
    char szBuffer[MAX_PATH];
    StringCchPrintf(szBuffer, MAX_PATH, "%d", source);
    return szBuffer;
}

template <> inline std::string string_cast(unsigned short source)
{
    char szBuffer[MAX_PATH];
    StringCchPrintf(szBuffer, MAX_PATH, "%u", source);
    return szBuffer;
}

template <> inline std::string string_cast(long source)
{
    char szBuffer[MAX_PATH];
    StringCchPrintf(szBuffer, MAX_PATH, "%i", source);
    return szBuffer;
}

template <> inline std::string string_cast(double source)
{
    char szBuffer[MAX_PATH];
    StringCchPrintf(szBuffer, MAX_PATH, "%f", source);
    return szBuffer;
}

template <> inline std::string string_cast(char source)
{
    char szBuffer[MAX_PATH];
    StringCchPrintf(szBuffer, MAX_PATH, "%c", source);
    return szBuffer;
}


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


#endif // !defined(MZSCRIPT_UTILITY_HPP_INCLUDED)
