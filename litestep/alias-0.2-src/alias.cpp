//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  alias.cpp
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

#include "alias.hpp"

using std::string;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// typedefs
//
typedef struct AliasData {
	string Format;
	string Defaults;
	unsigned short NumberOfVariables;
} AliasData;
typedef std::map<string, AliasData, stringicmp> AliasMap;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Globals
//
HWND g_hMain = NULL;
HWND g_hLitestep = NULL;

const UINT g_lsMessages[] = { LM_GETREVID, LM_REFRESH, 0 };

AliasMap g_AliasMap;

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// initModuleEx
//
int initModuleEx(HWND hLiteStep, HINSTANCE hInst, LPCSTR /* strPath */)
{
	g_hLitestep = hLiteStep;

	//
	// window (class) creation/registration
	//
	WNDCLASS wc = { 0 };
	wc.lpfnWndProc = WndProc;
	wc.hInstance = hInst;
	wc.lpszClassName = g_strAppName;

	if (!RegisterClass(&wc))
	{
		ErrorMessage(GetLastError());
	}

	g_hMain = CreateMessageWindow(hInst, g_strAppName, NULL);

	SetWindowLong(g_hMain, GWL_USERDATA, magicDWord);
	SendMessage(g_hLitestep, LM_REGISTERMESSAGE,
		(WPARAM)g_hMain, (LPARAM)g_lsMessages);


	AddBangCommand("!alias", BangAlias);
	LoadSetup();

	return 0;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// quitModule
//
void quitModule(HINSTANCE hInst)
{
	ClearSetup();
	RemoveBangCommand("!alias");

	if (g_hMain)
	{
		SendMessage(g_hLitestep, LM_UNREGISTERMESSAGE,
			(WPARAM)g_hMain, (LPARAM)g_lsMessages);

		DestroyWindow(g_hMain);

		g_hMain = NULL;
	}

	UnregisterClass(g_strAppName, hInst);

	g_hLitestep = NULL;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// LoadSetup
//
void LoadSetup()
{
	try
	{
		EnumConfig(NULL, "*Alias", &ParseAliasLine);
	}
	catch (std::exception& e)
	{
		ErrorMessage(e.what());
	}
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ClearSetup
//
void ClearSetup()
{
	for (AliasMap::iterator iter = g_AliasMap.begin(); iter != g_AliasMap.end(); ++iter)
	{
		RemoveBangCommand(iter->first.c_str());
	}

	g_AliasMap.clear();
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ParseAliasLine
//
// callback for EnumSettings in LoadSetup
// also used in BangAlias
//
bool ParseAliasLine(LPCSTR strLine)
{
	if (strLine != NULL)
	{
		LPCSTR pszRest = strLine;
		char strToken[MAX_LINE_LENGTH] = { 0 };
		char strDefaults[MAX_LINE_LENGTH] = { 0 };
		int TokenPosition;

		while (pszRest)
		{
			// Find the token containing the bang name
			GetToken(pszRest, strToken, &pszRest, FALSE);
			if (strToken[0] == '!')
			{
				if (pszRest)
				{
					// Get the defaults string
					TokenPosition = strlen(strLine) - strlen(strToken) - strlen(pszRest) - 2;
					memcpy(strDefaults, strLine, (TokenPosition > 0) ? TokenPosition : 0);

					// Look for the bang name in the alias map
					AliasMap::iterator iter = g_AliasMap.find(strToken);

					unsigned short NumberOfVariables = CountVariables(pszRest);

					// FormatMessage can't handle numbers beyond 255.
					if (NumberOfVariables > 255)
					{
						ErrorMessage("Error while parsing alias %s insert with number beyond 255 detected(%%%d).", strToken, NumberOfVariables);
					}
					else
					{
						if (iter != g_AliasMap.end())
						{
							iter->second.Format.assign(pszRest);
							iter->second.Defaults.assign(strDefaults);
							iter->second.NumberOfVariables = NumberOfVariables;
						}
						else
						{
							AliasData aData;
							aData.Format.assign(pszRest);
							aData.Defaults.assign(strDefaults);
							aData.NumberOfVariables = NumberOfVariables;

							g_AliasMap.insert(AliasMap::value_type(strToken, aData));
							AddBangCommandEx(strToken, BangAliasExec);
						}
					}
				}
				break;
			}
		}
	}
	return true;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// CountVariables
//
unsigned short CountVariables(LPCSTR pszSource)
{
	LPSTR strFormat = _strdup(pszSource);
	unsigned short HighestVar = 0;

	LPSTR pszSearch = strFormat + strlen(strFormat);
	while (pszSearch >= strFormat)
	{
		if (!isdigit(*pszSearch))
		{
			if (*pszSearch == '%' && *(pszSearch + 1) != '\0')
			{
				LPSTR pszTemp = pszSearch - 1;
				while (pszTemp >= strFormat && *pszTemp == '%')
				{
					--pszTemp;
				}
				if ((pszSearch - pszTemp) % 2)
				{
					HighestVar = (unsigned short)atoi(pszSearch + 1);
				}
				pszSearch = pszTemp + 1;
			}
			*pszSearch = '\0';
		}
		--pszSearch;
	}

	free(strFormat);

	return HighestVar;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// FormatString
//
bool FormatString(LPSTR strBuffer, DWORD cchBuffer, LPCSTR strFormat,
				  LPCSTR* pstrArray)
{
	return (0 != FormatMessage(
		FORMAT_MESSAGE_FROM_STRING | FORMAT_MESSAGE_ARGUMENT_ARRAY,
		strFormat,
		0,
		0,
		strBuffer,
		cchBuffer,
		(va_list*)pstrArray));
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// BangAlias
//
void BangAlias(HWND, LPCSTR pszArgs)
{
	ParseAliasLine(pszArgs);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// BangAliasExec
//
// the alias "interpreter"
//
void BangAliasExec(HWND, LPCSTR strName, LPCSTR strArgs)
{
	AliasMap::iterator iter = g_AliasMap.find(strName);

	if (iter != g_AliasMap.end())
	{
		LPCSTR pszNextToken = strArgs;
		LPCSTR pszDefaults = iter->second.Defaults.c_str();
		char strBuffer[MAX_LINE_LENGTH] = { 0 };
		char strResult[MAX_LINE_LENGTH] = { 0 };
		char strDefault[MAX_LINE_LENGTH] = { 0 };
		char* pszArgument;
		std::vector<char*> argsVec;
		unsigned short NumberofParams = 0;

		// Make sure that pszNextToken is not blank
		if (strcmp(pszNextToken, "") != 0)
		{
			// Build Args vector and find the number of params passed
			while (pszNextToken)
			{
				GetToken(pszNextToken, strBuffer, &pszNextToken, FALSE);
				pszArgument = _strdup(strBuffer);

				if (pszArgument)
				{
					NumberofParams++;
					argsVec.push_back(pszArgument);

					// Keep pszDefaults moving forward
					GetToken(pszDefaults, strDefault, &pszDefaults, FALSE);
				}
			}
		}

		// Inflate argsVec with defaults or ""
		for (unsigned short i = NumberofParams; i <= iter->second.NumberOfVariables; i++)
		{
			if (pszDefaults)
			{
				GetToken(pszDefaults, strDefault, &pszDefaults, FALSE);
				pszArgument = _strdup(strDefault);
			}
			else
			{
				pszArgument = _strdup("");
			}
			argsVec.push_back(pszArgument);
		}

		// Let FormatString build the final command string
		bool bStringBuilt = FormatString(strResult, MAX_LINE_LENGTH,
			iter->second.Format.c_str(), const_cast<const char**>(&argsVec[0]));

		std::for_each(argsVec.begin(), argsVec.end(), free);

		// Execute the final command string
		if (bStringBuilt)
		{
			LSExecute(NULL, strResult, SW_SHOWNORMAL);
		}
	}
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// WndProc
//
LRESULT CALLBACK WndProc(HWND hWnd, UINT uMessage, WPARAM wParam, LPARAM lParam)
{
	switch (uMessage)
	{
	case LM_GETREVID:
		{
			if (wParam == 0 || wParam == 1)
			{
				if (SUCCEEDED(StringCchPrintf((char*)lParam, 64,
					"%s %s", g_strAppName, g_strAppVersion)))
				{
					return lstrlen((char*)lParam);
				}
			}

			// something above failed
			lParam = NULL;
		}
		break;

	case LM_REFRESH:
		{
			ClearSetup();
			LoadSetup();

			return 0;
		}
		break;

	default:
		break;
	}

	return DefWindowProc(hWnd, uMessage, wParam, lParam);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// DllMain
//
// DLL entry point
//
BOOL APIENTRY DllMain(HINSTANCE hInst, DWORD dwReason, LPVOID /* pvReserved */)
{
	if (dwReason == DLL_PROCESS_ATTACH)
	{
		DisableThreadLibraryCalls(hInst);
	}

	return TRUE;
}
