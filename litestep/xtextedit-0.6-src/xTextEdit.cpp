/***************************************************************************
****************************************************************************

This is a part of the xModule Source code.

Copyright (C) 2003-2006 The LS-Universe Team

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

****************************************************************************
****************************************************************************/

#include "stdafx.h"
#include "VerInfo.h"

#define StringCchCopy(a, b, c) strncpy((a), (c), (b))
#define StringCchLength(a, b, c) *(c) = strlen((a)), S_OK
#define StringCchPrintf _snprintf

#include <fstream>
#include "regexp.h"
#include "regmagic.h"

HINSTANCE hInstance;
HWND messageHandler;

bool userConfirmation = GetRCBoolDef("xTextEditConfirmation", false);
bool userDebug = GetRCBoolDef("xTextEditDebug", false);

bool userNoEscape = GetRCBoolDef("xTextEditNoEscape", false);

void getToken(char line[MAX_LINE_LENGTH], char temp[MAX_LINE_LENGTH], bool escape_codes = true);

void BangTextAppend(HWND hwndCaller, LPCSTR pszArgs);
void CodeInsert(bool after, LPCSTR pszArgs);
void BangTextInsertAfter(HWND hwndCaller, LPCSTR pszArgs);
void BangTextInsertBefore(HWND hwndCaller, LPCSTR pszArgs);
void CodeDelete(bool onlyfirst, LPCSTR pszArgs);
void BangTextDelete(HWND hwndCaller, LPCSTR pszArgs);
void BangTextDeleteAll(HWND hwndCaller, LPCSTR pszArgs);
void CodeReplace(bool onlyfirst, LPCSTR pszArgs);
void BangTextReplace(HWND hwndCaller, LPCSTR pszArgs);
void BangTextReplaceAll(HWND hwndCaller, LPCSTR pszArgs);
void BangTextSaveEvar(HWND hwndCaller, LPCSTR pszArgs);

void BangTextToggleNoEscape(HWND hwndCaller, LPCSTR pszArgs);

int lsMessages[] = {
	LM_GETREVID,
	0
};

LRESULT WINAPI MessageHandlerProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
{
	switch(message)
	{
		case LM_GETREVID:
		{
			UINT uLength;
			StringCchPrintf((char*)lParam, 64, "%s.dll: %s", V_NAME, V_VERSION);
			
			if (SUCCEEDED(StringCchLength((char*)lParam, 64, &uLength)))
				return uLength;

			lParam = NULL;
			return 0;
		}
	}

	return DefWindowProc(hWnd, message, wParam, lParam);
}

BOOL __stdcall _DllMainCRTStartup(HINSTANCE hInst, DWORD fdwReason, LPVOID lpvRes)
{
	// We don't need thread notifications for what we're doing.  Thus, get
	// rid of them, thereby eliminating some of the overhead of this DLL
	DisableThreadLibraryCalls(hInst);

	return TRUE;
}

int initModuleEx(HWND hParent, HINSTANCE hInstance, const char *lsPath)
{
	WNDCLASSEX wc;

	wc.cbSize = sizeof(WNDCLASSEX);
	wc.style = CS_GLOBALCLASS;
	wc.lpfnWndProc = MessageHandlerProc;
	wc.cbClsExtra = 0;
	wc.cbWndExtra = 0;
	wc.hInstance = hInstance;
	wc.hbrBackground = 0;
	wc.hCursor = 0;
	wc.hIcon = 0;
	wc.lpszMenuName = 0;
	wc.lpszClassName = "xTextEditMessageHandler";
	wc.hIconSm = 0;

	RegisterClassEx(&wc);

	messageHandler = CreateWindowEx(WS_EX_TOOLWINDOW,
		"xTextEditMessageHandler",
		0,
		WS_POPUP,
		0, 0, 0, 0, 
		0,
		0,
		hInstance,
		0);

	if (!messageHandler)
		return 1;

	SendMessage(GetLitestepWnd(),
		LM_REGISTERMESSAGE,
		(WPARAM) messageHandler,
		(LPARAM) lsMessages);

	::hInstance = hInstance;

	AddBangCommand("!xTextAppend", BangTextAppend);
	AddBangCommand("!xTextInsertAfter", BangTextInsertAfter);
	AddBangCommand("!xTextInsertBefore", BangTextInsertBefore);
	AddBangCommand("!xTextDelete", BangTextDelete);
	AddBangCommand("!xTextDeleteAll", BangTextDeleteAll);
	AddBangCommand("!xTextReplace", BangTextReplace);
	AddBangCommand("!xTextReplaceAll", BangTextReplaceAll);
	AddBangCommand("!xTextSaveEvar", BangTextSaveEvar);

	AddBangCommand("!xTextToggleNoEscape", BangTextToggleNoEscape);

	return 0;
}

void quitModule(HINSTANCE hInstance)
{
	RemoveBangCommand("!xTextAppend");
	RemoveBangCommand("!xTextInsertAfter");
	RemoveBangCommand("!xTextInsertBefore");
	RemoveBangCommand("!xTextDelete");
	RemoveBangCommand("!xTextDeleteAll");
	RemoveBangCommand("!xTextReplace");
	RemoveBangCommand("!xTextReplaceAll");
	RemoveBangCommand("!xTextSaveEvar");

	RemoveBangCommand("!xTextToggleNoEscape");

	SendMessage(GetLitestepWnd(),
		LM_UNREGISTERMESSAGE,
		(WPARAM) messageHandler,
		(LPARAM) lsMessages);

	DestroyWindow(messageHandler);

	UnregisterClass("xTextEditMessageHandler", hInstance);
}



//----------------------------------------------------------------
//----------------------------------------------------------------

	//=========================================================
	// getToken grabs a token and clobbers info that is parsed
	//=========================================================
	void getToken(char line[MAX_LINE_LENGTH], char temp[MAX_LINE_LENGTH], bool escape_codes /*= true*/)
	{
		int offset = 0, i;
		bool endquote = false;
		char ENCAP = '@';

		while (line[offset] == ' ')
		{
			offset++;
		}

		if (line[offset] == ENCAP)
		{
			offset++;
			endquote = true;
		}

		for (i = 0; i+offset < int(strlen(line)); ++i)
		{
			// Copy else if block to add more escape codes.
			if (escape_codes && (line[i+offset] == '\\' && int(strlen(line)) != i+offset+1))
			{
				if (line[i+offset+1] == ENCAP /*|| line[i+offset+1] == '\\'*/)
				{
					offset++;
					temp[i] = line[i+offset];
					continue;
				}
				// Bang escape code below.
				else if (line[i+offset+1] == '^')
				{
					offset++;
					temp[i] = '!';
					continue;
				}
				// EVar escape code below.
				else if (line[i+offset+1] == '#')
				{
					offset++;
					temp[i] = '$';
					continue;
				}
				// Comment escape code below.
				else if (line[i+offset+1] == '~')
				{
					offset++;
					temp[i] = ';';
					continue;
				}
				// Quotation mark escape code below.
				else if (line[i+offset+1] == '=')
				{
					offset++;
					temp[i] = '"';
					continue;
				}
			}

 			if (line[i+offset] == ENCAP && endquote)
	  			break;
			else if (line[i+offset] == ' ' && !endquote)
				break;
			else
				temp[i] = line[i+offset];
		}
		temp[i] = '\0';

		if (i+offset+1 > int(strlen(line)))
		{
			line[0] = '\0';
		}
		else
		{
			strcpy(line, line+i+offset+1);
		}
	}

	//=========================================================
	// Bang command handling
	//=========================================================

	void BangTextToggleNoEscape(HWND hwndCaller, LPCSTR pszArgs)
	{
		userNoEscape = !userNoEscape;
	}

	void BangTextAppend(HWND hwndCaller, LPCSTR pszArgs)
	{
		char filename[MAX_LINE_LENGTH], str[MAX_LINE_LENGTH];
		char rest[MAX_LINE_LENGTH];
		strcpy(rest, pszArgs);

		getToken(rest, filename, false);
		getToken(rest, str, true);

		ofstream file;
		file.open(filename, /* ios::nocreate | */ ios::app);

		if (!file.fail())
		{
			file << str << endl;
		}

		file.close();
	}

	void BangTextInsertAfter(HWND hwndCaller, LPCSTR pszArgs)
	{
		CodeInsert(true, pszArgs);
	}

	void BangTextInsertBefore(HWND hwndCaller, LPCSTR pszArgs)
	{
		CodeInsert(false, pszArgs);
	}

	void CodeInsert(bool after, LPCSTR pszArgs)
	{
		char filename[MAX_LINE_LENGTH], regex[MAX_LINE_LENGTH], input[MAX_LINE_LENGTH], insert[MAX_LINE_LENGTH];
		char rest[MAX_LINE_LENGTH];
		regexp *r;
		strcpy(rest, pszArgs);

		getToken(rest, filename, false);
		getToken(rest, regex, true);
		getToken(rest, insert, true);

		//. ? * + [ ] _ ^ ( ) | \ &
		if ( userNoEscape )
		{
			string worker = regex;
			string result = "";
				
			int length = worker.length();
			int i = 0;
				
			while(i < length)
			{
				if ( worker[i] == '.' || worker[i] == '?' || worker[i] == '*' || worker[i] == '+'
					|| worker[i] == '[' || worker[i] == ']' || worker[i] == '_' || worker[i] == '^'
					|| worker[i] == '(' || worker[i] == ')' || worker[i] == '|' || worker[i] == '\\' 
					|| worker[i] == '&' )
				{
					result.append(1, '\\');
					result.append(1, worker[i++]);
				}
				else
				{
					result.append(1, worker[i++]);
				}
			}
				
			strcpy(regex, result.c_str());
		}

		r = regcomp(regex);

		ifstream file;
		file.open(filename/*, ios::nocreate*/);        //removed because dev-cpp wont compile it... feel free to recompile to get it to work

		bool found = false;
		if (!file.fail())
		{
			list<string> l;
			while (file.getline(input, MAX_LINE_LENGTH))
			{
				if ( !found && regexec(r, input) )
				{
					if ( !userConfirmation && !userDebug )
					{
						if ( after )
						{
							l.push_back(input);
							l.push_back(insert);
						}
						else
						{
							l.push_back(insert);
							l.push_back(input);
						}
						found = true;
					}
					else
					{
						string message = "Do you want to insert\n\n";
						message.append ( insert );
						if ( after )
						{
							message.append( "\nafter\n" );
						}
						else
						{
							message.append( "\nbefore\n" );
						}
						message.append( input );
						message.append ( "\n\n in the file\n\n" );
						message.append ( filename );
						if ( userDebug )
						{
							message.append( "\n\nSearch String was:\n" );
							message.append( regex );
							message.append( "\n\nInsert String was:\n" );
							message.append( insert );
						}
						if ( MessageBox(NULL, message.c_str(), "User Confirmation", MB_YESNO | MB_SETFOREGROUND | MB_ICONQUESTION ) == IDYES )
						{
							if ( after )
							{
								l.push_back(input);
								l.push_back(insert);
							}
							else
							{
								l.push_back(insert);
								l.push_back(input);
							}
							found = true;
						}
						else
						{
							l.push_back(input);
							found = true;
						}
					}
				}
				else
				{
					l.push_back(input);
				}
			}
			file.close();
			ofstream outfile;
			outfile.open(filename);
			for (list<string>::const_iterator lci = l.begin(); lci!=l.end(); lci++)
			{
				outfile << lci->data() << endl;
			}
			l.clear();
		}

		if ( !found )
		{
			string message = "The given Search String\n\n";
			message.append( regex );
			message.append ( "\n\nwasn't found in the file\n\n" );
			message.append ( filename );
			message.append ( "\n\nInsertion canceled!" );
			MessageBox(NULL, message.c_str(), "User Confirmation", MB_OK | MB_SETFOREGROUND | MB_ICONEXCLAMATION);
		}
	}

	void BangTextDelete(HWND hwndCaller, LPCSTR pszArgs)
	{
		CodeDelete(true, pszArgs);
	}

	void BangTextDeleteAll(HWND hwndCaller, LPCSTR pszArgs)
	{
		CodeDelete(false, pszArgs);
	}

	void CodeDelete(bool onlyfirst, LPCSTR pszArgs)
	{
		char filename[MAX_LINE_LENGTH], regex[MAX_LINE_LENGTH], input[MAX_LINE_LENGTH];
		char rest[MAX_LINE_LENGTH];
		regexp *r;
		strcpy(rest, pszArgs);

		getToken(rest, filename, false);
		getToken(rest, regex, true);

		//. ? * + [ ] _ ^ ( ) | \ &
		if ( userNoEscape )
		{
			string worker = regex;
			string result = "";
				
			int length = worker.length();
			int i = 0;
				
			while(i < length)
			{
				if ( worker[i] == '.' || worker[i] == '?' || worker[i] == '*' || worker[i] == '+'
					|| worker[i] == '[' || worker[i] == ']' || worker[i] == '_' || worker[i] == '^'
					|| worker[i] == '(' || worker[i] == ')' || worker[i] == '|' || worker[i] == '\\' 
					|| worker[i] == '&' )
				{
					result.append(1, '\\');
					result.append(1, worker[i++]);
				}
				else
				{
					result.append(1, worker[i++]);
				}
			}
				
			strcpy(regex, result.c_str());
		}

		r = regcomp(regex);

		ifstream file;
		file.open(filename/*, ios::nocreate*/);        //removed because dev-cpp wont compile it... feel free to recompile to get it to work

		bool found = false;
		if (!file.fail())
		{
			list<string> l;
			while (file.getline(input, MAX_LINE_LENGTH))
			{
				if (!regexec(r, input) || found )
				{
					l.push_back(input);
				}
				else
				{
					if ( onlyfirst )
						found = true;
					if ( userConfirmation || userDebug )
					{
						string message = "Do you really want to delete\n\n";
						message.append( input );
						message.append ( "\n\n in the file\n\n" );
						message.append ( filename );
						if ( userDebug )
						{
							message.append( "\n\nSearch String was:\n\n" );
							message.append( regex );
						}
						if ( MessageBox(NULL, message.c_str(), "User Confirmation", MB_YESNO | MB_SETFOREGROUND | MB_ICONQUESTION) == IDNO )
						{
							l.push_back(input);
						}
					}
				}
			}
			file.close();
			ofstream outfile;
			outfile.open(filename);
			for (list<string>::const_iterator lci = l.begin(); lci!=l.end(); lci++)
			{
				outfile << lci->data() << endl;
			}
			l.clear();
		}
	}

	void BangTextReplace(HWND hwndCaller, LPCSTR pszArgs)
	{
		CodeReplace(true, pszArgs);
	}

	void BangTextReplaceAll(HWND hwndCaller, LPCSTR pszArgs)
	{
		CodeReplace(false, pszArgs);
	}

	void CodeReplace(bool onlyfirst, LPCSTR pszArgs)
	{
		char filename[MAX_LINE_LENGTH], regex[MAX_LINE_LENGTH], input[MAX_LINE_LENGTH], replace[MAX_LINE_LENGTH];
		char rest[MAX_LINE_LENGTH], buf[MAX_LINE_LENGTH];
		regexp *r;
		strcpy(rest, pszArgs);

		getToken(rest, filename, false);
		getToken(rest, regex, true);
		getToken(rest, replace, true);

		//. ? * + [ ] _ ^ ( ) | \ &
		if ( userNoEscape )
		{
			string worker = regex;
			string result = "";
				
			int length = worker.length();
			int i = 0;
				
			while(i < length)
			{
				if ( worker[i] == '.' || worker[i] == '?' || worker[i] == '*' || worker[i] == '+'
					|| worker[i] == '[' || worker[i] == ']' || worker[i] == '_' || worker[i] == '^'
					|| worker[i] == '(' || worker[i] == ')' || worker[i] == '|' || worker[i] == '\\' 
					|| worker[i] == '&' )
				{
					result.append(1, '\\');
					result.append(1, worker[i++]);
				}
				else
				{
					result.append(1, worker[i++]);
				}
			}
				
			strcpy(regex, result.c_str());
		}

		r = regcomp(regex);

		ifstream file;
		file.open(filename/*, ios::nocreate*/);        //removed because dev-cpp wont compile it... feel free to recompile to get it to work

		bool replaced = false;
		bool found = false;
		if (!file.fail())
		{
			list<string> l;
			while (file.getline(input, MAX_LINE_LENGTH))
			{
				if ( !replaced && regexec(r, input) )
				{
					if ( !userNoEscape )
						regsub(r, replace, buf);
					else
						strcpy(buf, replace);

					if ( !userConfirmation && !userDebug)
					{
						l.push_back(buf);
						if ( onlyfirst )
							replaced = true;
						found = true;
					}
					else
					{
						string message = "Do you want to replace\n\n";
						message.append( input );
						message.append( "\nwith\n" );
						message.append ( buf );
						message.append ( "\n\n in the file\n\n" );
						message.append ( filename );
						if ( userDebug )
						{
							message.append( "\n\nSearch String was:\n" );
							message.append( regex );
							message.append( "\n\nReplace String was:\n" );
							message.append( replace );
						}
						if ( MessageBox(NULL, message.c_str(), "User Confirmation", MB_YESNO | MB_SETFOREGROUND | MB_ICONQUESTION ) == IDYES )
						{
							l.push_back(buf);
							if ( onlyfirst )
								replaced = true;
							found = true;	
						}
						else
						{
							l.push_back(input);
							found = true;
						}
					}
				}
				else
				{
					l.push_back(input);
				}
			}
			file.close();
			ofstream outfile;
			outfile.open(filename);
			for (list<string>::const_iterator lci = l.begin(); lci!=l.end(); lci++)
			{
				outfile << lci->data() << endl;
			}
			l.clear();
		}

		if ( !found )
		{
			string message = "The given Search String\n\n";
			message.append( regex );
			message.append ( "\n\nwasn't found in the file\n\n" );
			message.append ( filename );
			message.append ( "\n\nReplace canceled!" );
			MessageBox(NULL, message.c_str(), "User Confirmation", MB_OK | MB_SETFOREGROUND | MB_ICONEXCLAMATION);
		}
	}

	void BangTextSaveEvar(HWND hwndCaller, LPCSTR pszArgs)
	{
		char filename[MAX_LINE_LENGTH] = {0};
		char str[MAX_LINE_LENGTH] = {0};
		char val[MAX_LINE_LENGTH] = {0};
		char rest[MAX_LINE_LENGTH] = {0};

		char orgevar[MAX_LINE_LENGTH] = {0};

		strcpy(rest, pszArgs);

		getToken(rest, filename, false);
		getToken(rest, str, false);
		strcpy(orgevar, str);
		getToken(rest, val, true);

		string file = filename;
		string EvarToSave = str;
		string result = "";
			
		int length = EvarToSave.length();
		int i = 0;
			
		while(i < length)
		{
			result.append(1, '[');
			result.append(1, tolower(EvarToSave[i]));
			result.append(1, toupper(EvarToSave[i++]));
			result.append(1, ']');
		}
			
		EvarToSave = result;

		result = val;
		if ( result.empty() )
		{
			result = "$";
			result.append( str );
			result.append( "$" );
			VarExpansion( str, result.c_str() );
		}
		else
		{
			strcpy( str, val);
		}

		result = str;

		BangTextReplace(NULL, ("@" + file + "@ @[		]*(" + EvarToSave + ").*@ @" + orgevar + " \"" + result + "\"@").c_str());
	}

//----------------------------------------------------------------
//----------------------------------------------------------------
