//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  utility.cpp
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

#include "utility.hpp"



//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// AskUser
//
int AskUser (UINT uFlags, LPCSTR pszFormat, ...)
{
    char  szMessage[MAX_LINE_LENGTH] = { 0 };
    va_list argList;
    
    va_start(argList, pszFormat);
    StringCchVPrintf(szMessage, MAX_LINE_LENGTH, pszFormat, argList);
    va_end(argList);
    
    return MessageBox(NULL, szMessage, "mzscript",
        uFlags | MB_SETFOREGROUND | MB_TOPMOST);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ErrorMessage
//
void ErrorMessage(LPCSTR pszType, LPCSTR pszFormat, ...)
{
    char  szMessage[MAX_LINE_LENGTH] = { 0 };
    char  szType[MAX_LINE_LENGTH] = { 0 };
    va_list argList;
    
	extern bool LogOnly;

    va_start(argList, pszFormat);
    StringCchVPrintf(szType, MAX_LINE_LENGTH, pszType, argList);
    StringCchVPrintf(szMessage, MAX_LINE_LENGTH, pszFormat, argList);
    va_end(argList);
	if (LogOnly == TRUE) {
		g_Logger->logl(szType, szMessage);
	} else {
		MessageBox(NULL, szMessage, "mzscript: "+(char)szType,
        MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
	}
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// GetLastErrorStr
//
string GetLastErrorStr()
{
    void* pMsgBuf = NULL;
    
    // TODO: both FormatMessage and LocalFree can fail... and they both
    // overwrite the GetLastError() flag... sigh
    FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
        FORMAT_MESSAGE_FROM_SYSTEM |
        FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL,
        GetLastError(),
        0,
        (LPSTR)&pMsgBuf,
        0,
        NULL
        );
    
    ASSERT(pMsgBuf);
    string sReturn((LPTSTR)pMsgBuf);
    
    LocalFree(pMsgBuf);
    return sReturn;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// CreateMessageWindow
//
// throws win32_error
//
HWND CreateMessageWindow(HINSTANCE hInst, LPCSTR pszClass, LPCSTR pszWndName)
{
    ASSERT(hInst); ASSERT(pszClass);

    HWND hParent = NULL;

    OSVERSIONINFO ovi = { 0 };
    ovi.dwOSVersionInfoSize = sizeof(OSVERSIONINFO);

    GetVersionEx(&ovi);

    if (ovi.dwPlatformId == VER_PLATFORM_WIN32_NT &&
        ovi.dwMajorVersion >= 5)
    {
        hParent = HWND_MESSAGE;
    }
    

    HWND hWnd = CreateWindowEx(
        WS_EX_NOPARENTNOTIFY | WS_EX_TOOLWINDOW,
        pszClass, pszWndName,
        WS_POPUP,
        0, 0, 0, 0,
        hParent, NULL,
        hInst,
        NULL);

    if (!hWnd)
    {
        throw win32_error();
    }

    return hWnd;
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
// StrIComp
//
int StrIComp(const char* a, const char* b)
{
    return CompareString(LOCALE_USER_DEFAULT, NORM_IGNORECASE,
        a, -1, b, -1) - 2;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// StrIEqual
//
bool StrIEqual(const char* a, const char* b)
{
    return (StrIComp(a, b) == 0);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// isnum
//
// isdigit plus support for negative numbers
//
bool isnum(const char* tmp)
{
    ASSERT(tmp);
    
    if (tmp[0] ==  '-')
    {
        ++tmp;
    }
    
    // Stop null strings from returning true
    if (*tmp == '\0')
    {
        return false;
    }
    
    while (*tmp != '\0')
    {
        if (isdigit(*tmp) != 0)
        {
            ++tmp;
        }
        else
        {
            return false;
        }
    }
    
    return true;
}

bool GetToken(LPCSTR pszString, LPSTR pszToken, LPCSTR* pszNextToken, bool bUseBrackets, bool bAllowEmptyToken)
{
	LPCSTR pszCurrent = pszString;
	LPCSTR pszStartMarker = NULL;
	int iBracketLevel = 0;
	CHAR cQuote = '\0';
	bool bIsToken = false;
	bool bAppendNextToken = false;

	if (pszString)
	{
		if (pszToken)
        {
            pszToken[0] = '\0';
        }

        if (pszNextToken)
        {
            *pszNextToken = NULL;
        }

		pszCurrent += strspn(pszCurrent, WHITESPACE);

		for (; *pszCurrent; pszCurrent++)
		{
			if (isspace((unsigned char)*pszCurrent) && !cQuote)
            {
                break;
            }

			if (bUseBrackets && strchr("[]", *pszCurrent) &&
                (!strchr("\'\"", cQuote) || !cQuote))
			{
				if (*pszCurrent == '[')
				{
					if (bIsToken && !cQuote)
                    {
                        break;
                    }

					iBracketLevel++;
					cQuote = '[';
					
                    if (iBracketLevel == 1)
                    {
                        continue;
                    }
				}
				else
				{
					iBracketLevel--;
					
                    if (iBracketLevel <= 0)
                    {
                        break;
                    }
				}
			}

			if (strchr("\'\"", *pszCurrent) && (cQuote != '['))
			{
				if (!cQuote)
				{
					if (bIsToken)
					{
						bAppendNextToken = true;
						break;
					}

					cQuote = *pszCurrent;
					continue;
				}
				else if (*pszCurrent == cQuote)
				{
					break;
				}
			}

			if (!bIsToken)
			{
				bIsToken = true;
				pszStartMarker = pszCurrent;
			}
		}

		if (pszStartMarker && pszToken)
		{
			strncpy(pszToken, pszStartMarker, pszCurrent - pszStartMarker);
			pszToken[pszCurrent - pszStartMarker] = '\0';
		}

		if (!bAppendNextToken && *pszCurrent)
        {
            pszCurrent++;
        }

		pszCurrent += strspn(pszCurrent, WHITESPACE);

		if (*pszCurrent && pszNextToken)
        {
            *pszNextToken = pszCurrent;
        }

		if (bAppendNextToken && *pszCurrent)
        {
			GetToken(pszCurrent, (pszToken) ? (pszToken + strlen(pszToken)) : (pszToken),
                pszNextToken, bUseBrackets, bAllowEmptyToken);
        }
		
		if(!pszStartMarker && bAllowEmptyToken)
		{
			//if nothing left return false
			if(!*pszCurrent)
				return false;
			//if theres something left, then it was just a ""
			//so leave token null and return true
			return true;
		}

		return pszStartMarker != NULL;
	}

	return false;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// GetTokenPos
//
// similar to GetToken from LSAPI but gives you the position as stStart and stEnd
bool GetTokenPos(LPCSTR pszString, size_t& stStart, size_t& stEnd, bool bUseBrackets, bool bAllowEmptyToken)
{
	LPCSTR pszCurrent = pszString;
	LPCSTR pszStartMarker = NULL;
	int iBracketLevel = 0;
	CHAR cQuote = '\0';
	bool bIsToken = false;
	bool bAppendNextToken = false;
	stStart = 0;
	stEnd = 0;

	if (pszString)
	{
		pszCurrent += strspn(pszCurrent, WHITESPACE);

		for (; *pszCurrent; pszCurrent++)
		{
			if (isspace((unsigned char)*pszCurrent) && !cQuote)
            {
                break;
            }

			if (bUseBrackets && strchr("[]", *pszCurrent) &&
                (!strchr("\'\"", cQuote) || !cQuote))
			{
				if (*pszCurrent == '[')
				{
					if (bIsToken && !cQuote)
                    {
                        break;
                    }

					iBracketLevel++;
					cQuote = '[';
					
                    if (iBracketLevel == 1)
                    {
                        continue;
                    }
				}
				else
				{
					iBracketLevel--;
					
                    if (iBracketLevel <= 0)
                    {
                        break;
                    }
				}
			}

			if (strchr("\'\"", *pszCurrent) && (cQuote != '['))
			{
				if (!cQuote)
				{
					if (bIsToken)
					{
						bAppendNextToken = true;
					}

					cQuote = *pszCurrent;
					continue;
				}
				else if (*pszCurrent == cQuote)
				{
					break;
				}
			}

			if (!bIsToken)
			{
				bIsToken = true;
				pszStartMarker = pszCurrent;
			}
		}

		if (pszStartMarker)
		{
			stStart = pszStartMarker - pszString;
			stEnd = pszCurrent - pszString ;
			
			//append the end quote
			if(bAppendNextToken)
				stEnd++;
		}
		else if(bAllowEmptyToken)
		{
			//if nothing left return false
			if(!*pszCurrent)
				return false;
			//if theres something left, then it was just a ""
			//so set stStart and stEnd to the last "
			//and return true
			stStart = stEnd = pszCurrent - pszString;
			return true;
		}

		return pszStartMarker != NULL;
	}

	return false;
}