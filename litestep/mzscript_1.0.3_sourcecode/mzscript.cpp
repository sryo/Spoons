 //=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  mzscript.cpp
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

#include "bangs.hpp"
#include "scripts.hpp"
#include "utility.hpp"
#include "mzscript.hpp"
#include "../AggressiveOptimize/AggressiveOptimize.h"

using std::string;
using std::invalid_argument;
using std::runtime_error;
using std::ifstream;

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// local helpers
//
static bool ParseScript(LPCSTR pszName, FILE* fStart);

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Globals
//
HWND g_hMain = NULL;
HWND g_hLitestep = NULL;

const UINT g_lsMessages[] = { LM_GETREVID, LM_REFRESH, 0 };

extern char szLogFile[MAX_LINE_LENGTH] = { 0 };
extern int LogLevel = 0;
extern bool LogOpened = FALSE;
extern bool LogOnly = FALSE;

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// initModuleEx
//
int initModuleEx(HWND hLiteStep, HINSTANCE hInst, LPCSTR /* pszPath */)
{
    g_hLitestep = hLiteStep;

    try
    {
        //
        // window (class) creation/registration
        //
        WNDCLASS wc = { 0 };
        wc.lpfnWndProc = WndProc;
        wc.hInstance = hInst;
        wc.lpszClassName = g_szAppName;
        
        if (!RegisterClass(&wc))
        {
            throw win32_error();
        }

        g_hMain = CreateMessageWindow(hInst, g_szAppName, NULL);

        SetWindowLong(g_hMain, GWL_USERDATA, magicDWord);
        SendMessage(g_hLitestep, LM_REGISTERMESSAGE,
            (WPARAM)g_hMain, (LPARAM)g_lsMessages);

        //
        // register bangs, read step.rc settings
        //
        RegisterBangs();
        
        LoadSetup(false);
    }
    catch (std::bad_alloc&)
    {
		ErrorMessage("ERROR","Bad allocation during initialization. Out of memory? Shutting down...");
        
        ClearSetup(); // could also use quitModule, but that might be a bit more
                      // dangerous... then again you can hardly do anything
                      // "right" in OOM situations.
        return 2;
    }
    catch (std::exception& e)
    {
		ErrorMessage("ERROR","Initialization failed. Description: %s", e.what());

        return 1;
    }

    return 0;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// quitModule
//
void quitModule(HINSTANCE hInst)
{
    UnregisterBangs();
    ClearSetup();
    
    if (g_hMain)
    {
        SendMessage(g_hLitestep, LM_UNREGISTERMESSAGE,
            (WPARAM)g_hMain, (LPARAM)g_lsMessages);
        
        DestroyWindow(g_hMain);

        g_hMain = NULL;
    }

    UnregisterClass(g_szAppName, hInst);

    g_hLitestep = NULL;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// LoadSetup
//
// throws invalid_argument, runtime_error
//
// original code was using szBuffer to hold file name, but this is a problem with
// additional code. Renamed to make more readable.
void LoadSetup(bool bIsRefresh)
{
	char szBuffer[MAX_LINE_LENGTH] = { 0 };
	char szLogFileMaxSize[MAX_LINE_LENGTH] = { 0 };

	//Load internal function variables
	SetupVarFuncs();

	//load mzLogFile config and enable logging if defined
	if(GetRCString("mzLogFile",szLogFile,"",MAX_LINE_LENGTH) && szLogFile[0])
	{
		if(!g_Logger->open(szLogFile)) {
			ErrorMessage("ERROR","Unable to open mzScript log file. Logging disabled.");
		} else {
			GetRCString("mzLogLevel",szBuffer,"",MAX_LINE_LENGTH);
			LogLevel = (int)szBuffer;
			if ( LogLevel >= 1 || LogLevel <= 3)
			{
				LogOnly = TRUE;
				LogOpened = TRUE;
				g_Logger->logl("INFO","mzScript Log file found. Logging enabled.");
			} else {
				if (LogLevel != 0)
					ErrorMessage("ERROR","Unable to use logging. mzLogLevel is invalid.");
			}
		}
	}

	// attempting to use LSLog file if the earlier mzScript log file had problems.
	if(LogOnly == FALSE) {
		if(GetRCString("LSLogFile",szLogFile,"",MAX_LINE_LENGTH) && szLogFile[0])
		{
			if(!g_Logger->open(szLogFile)) {
				ErrorMessage("ERROR","Unable to open LiteStep log file. Logging disabled.");
			} else {
				GetRCString("LSLogLevel",szBuffer,"",MAX_LINE_LENGTH);
				LogLevel = (int)szBuffer;
				if (LogLevel <= 4 || LogLevel >= 1)
				{
					LogOnly = TRUE;
					ErrorMessage("INFO","LiteStep Log file found. Logging enabled.");
				} else {
					if (LogLevel != 0)
						ErrorMessage("ERROR","Unable to use logging. LSLogLevel is invalid.");
				}
			}
		}
	}

	// attempting to handle large log files. Code from i/step CVS and MSDN docs. Might be better in the
	// logger code, but it was easier to stick it here :b
	if(LogOnly == TRUE) {
		unsigned int limit; // = 1000; // hardcoding for testing code below. Need log file ~1 MB to trigger delete.
		// querying in order of preference for log file maximum size settings.
		if(GetRCString("MaxLogFileSize",szLogFileMaxSize,"",MAX_LINE_LENGTH)) {
			limit = (unsigned int) (szLogFileMaxSize);
		} else {
			if(GetRCString("LSLogMaxFileSize",szLogFileMaxSize,"",MAX_LINE_LENGTH)) {
				limit = (unsigned int) (szLogFileMaxSize);
			}
		}

		// Attempting to ensure that we deleted without problems and report why if we didn't.
		WIN32_FIND_DATA wfd;
		if ( (FindFirstFile(szLogFile, &wfd) != INVALID_HANDLE_VALUE) && (wfd.nFileSizeLow/1024) >  limit) {
			// GetRCString("LogFileMaxSizeAction",szBuffer,"",MAX_LINE_LENGTH)
			ErrorMessage("INFO","LiteStep Log file oversized.");
			if(!g_Logger->close()) {
					DWORD error = GetLastError();
					ErrorMessage("ERROR","Unable to close oversized log file. Error code %u", error);
			} else {
				bool deletedlogfile = DeleteFile(szLogFile);
				if ( deletedlogfile == TRUE ) {
					CreateFile(szLogFile, 
						GENERIC_WRITE,
						FILE_SHARE_READ | FILE_SHARE_WRITE,
						NULL,
						OPEN_ALWAYS,
						FILE_ATTRIBUTE_NORMAL,
						NULL);
					g_Logger->open(szLogFile);
					ErrorMessage("INFO","Deleted oversized log file."); // debugging report. Will disable for final release.
				} else {
					DWORD error = GetLastError();
					g_Logger->open(szLogFile);
					ErrorMessage("ERROR","Unable to delete oversized log file. Error code %u", error);
				}
			}
		}

	}

	//Load vars from *mzVarFile configs
	FILE *f;
	f = LCOpen(NULL);
	if(f)
	{
		char szFile[MAX_LINE_LENGTH];
		char* ppszTokens[] = { NULL, szFile };

		while(LCReadNextConfig(f, "*mzVarFile", szBuffer, MAX_LINE_LENGTH))
		{
			if(CommandTokenize(szBuffer, ppszTokens, 2, NULL) >= 2)
				LoadVarFile(szFile);
		}
	}
	LCClose(f);

    //Load scripts from step.rc
    LoadScriptFile(NULL, bIsRefresh);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ClearSetup
//
// must not throw
//
void ClearSetup()
{
	if(GetRCBool("mzAutosaveVars",true))
		if(!g_Variables->SaveAll())
			ErrorMessage("ERROR","Couldn't save one or more variables. File(s) failed to open.");
	g_Logger->close();
    ScriptsClear();
    g_Variables->Clear();
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// LoadScriptFile
//
// throws invalid_argument, runtime_error
//
void LoadScriptFile(LPCSTR pszFile, bool bIsRefresh)
{
    FILE* f = LCOpen(pszFile);

    if (f)
    {
        char szBuffer[MAX_LINE_LENGTH] = { 0 };
		std::list<std::string> lsStartBangs;

        while (LCReadNextConfig(f, "*Script", szBuffer, MAX_LINE_LENGTH))
        {
            char szType[MAX_LINE_LENGTH] = { 0 };
            char szRest[MAX_LINE_LENGTH] = { 0 };
            char* tokens[] = { NULL, szType };

            int nCount = CommandTokenize(szBuffer, tokens, COUNTOF(tokens), szRest);

            if (nCount >= 2 && szRest[0])
            {
                if ((StrIEqual(szType, "start") && !bIsRefresh) ||
                    (StrIEqual(szType, "refresh") && bIsRefresh))
                {
					lsStartBangs.push_back(szRest);
                    //ExecCommand(szRest);
                }
                else if (StrIEqual(szType, "bang"))
                {
                    if (!ParseScript(szRest, f))
                    {
                        break;
                    }
					g_Logger->logl("INFO","Loaded bangscript <%s>", szRest);
                }
                else
                {
					if (!(StrIEqual(szType, "start") && bIsRefresh) ||
                    (StrIEqual(szType, "refresh") && !bIsRefresh))
					{
						int nResponse = AskUser(MB_YESNO | MB_ICONWARNING,
							"Invalid or misplaced token \"%s\":\n"
							"*Script %s %s\n\nContinue parsing?",
							szType, szType, szRest);

						if (nResponse == IDNO)
						{
							g_Logger->logl("ERROR","Invalid or misplaced token <%s>. "
										"*Script %s %s. Discontinued parsing.",
										szType, szType, szRest);
							break;
						}
						else
						{
							g_Logger->logl("ERROR","Invalid or misplaced token <%s>. "
										"*Script %s %s. Continued parsing.",
										szType, szType, szRest);
						}
					}
                }
            }
        }

		g_Logger->logl("INFO","Executing Start/Refresh Bangs");
		std::list<std::string>::const_iterator lci = lsStartBangs.begin();
		for (lci; lci!=lsStartBangs.end(); lci++)
		{
			ExecCommand(*lci);
		}
		g_Logger->logl("INFO","Executed Start/Refresh Bangs");
		lsStartBangs.clear();
    }
    else
    {
        FormattedException<runtime_error>("Could not open \"%s\"",
            pszFile ? pszFile : "step.rc");
		g_Logger->logl("ERROR","Could not open <%s>",
            pszFile ? pszFile : "step.rc");
    }

    LCClose(f); // FIXME: not exception safe
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// LoadVarFile
//
void LoadVarFile(LPCSTR pszFile)
{
	ASSERT(pszFile);

	char szBuffer[MAX_LINE_LENGTH] = { 0 };
	EvalParser evalParser;
	stack<bool> stkCurrent;
	stack<bool> stkEval;

	ifstream file;
	file.open(pszFile);
	if (file.is_open())
	{
		g_Logger->logl("INFO","Loading mzVarFile <%s>", pszFile);
		list<string> l;
		string s, f_sLine, f_sVariable, f_sValue, f_sComment;

		while (!file.eof())
		{
			file.getline(szBuffer, MAX_LINE_LENGTH);
				f_sLine.assign(szBuffer);
				if(!Variables::_GetFileTokens(f_sLine, f_sVariable, f_sValue, f_sComment))
				{
					continue;
				}
				//	I use 2 stacks of booleans to do the if stuff.
				//	stkEval holds the evaluation of the current level only, 
				//	and stkCurrent holds the value of each level ANDed 
				//	to the previous level, so that only if every level 
				//	in the stack is true will it run.
				if(StrIEqual(f_sVariable,"if"))
				{
					int npEval = 0;
					evalParser.evaluate(f_sLine.c_str(), &npEval);
					if(stkCurrent.empty())
					{
						stkCurrent.push(npEval != 0);
					}
					else
					{
						stkCurrent.push( (npEval != 0) && stkCurrent.top() );
					}

					stkEval.push(npEval != 0);
					continue;
				}
				if(StrIEqual(f_sVariable,"elseif"))
				{
					if(!stkCurrent.empty())
					{
						int npEval = 0;
						evalParser.evaluate(f_sLine.c_str(), &npEval);
						stkCurrent.pop();
						stkCurrent.push( (npEval != 0) && stkCurrent.top() );
						stkEval.pop();
						stkEval.push(npEval != 0);
					}
					continue;
				}
				if(StrIEqual(f_sVariable,"else"))
				{
					if(!stkCurrent.empty())
					{
						stkCurrent.pop();
						stkCurrent.push( (!stkEval.top()) && stkCurrent.top() );
					}
					continue;
				}
				if(StrIEqual(f_sVariable,"endif"))
				{
					if(!stkCurrent.empty())
					{
						stkCurrent.pop();
						stkEval.pop();
					}
					continue;
				}

				if(stkCurrent.empty() || stkCurrent.top())
				{
					g_Variables->SetFromFile(szBuffer, pszFile);
					continue;
				}
		}
		file.close();
		g_Logger->logl("INFO","Loaded mzVarFile.");
	}
	else
    {
		ErrorMessage("ERROR","Could not open mzVarFile <%s>.", pszFile);
    }
	/*
	FILE* f = LCOpen(pszFile);

    if (f)
    {
		g_Logger->logl("INFO","[Loading mzVarFile \"%s\"]", pszFile);
        char szBuffer[MAX_LINE_LENGTH] = { 0 };
        while (LCReadNextLine(f, szBuffer, MAX_LINE_LENGTH))
        {
			g_Variables->SetFromFile(szBuffer, pszFile);
		}
		g_Logger->logl("INFO","[Loaded mzVarFile]");
    }
    else
    {
		g_Logger->logl("ERROR","Could not open mzVarFile \"%s\".", pszFile);
		ErrorMessage("Could not open \"%s\"", pszFile);
    }
	LCClose(f);
	*/
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ParseScript
//
// Process all lines between *Script bang and *Script ~bang
// throws invalid_argument
//
static bool ParseScript(LPCSTR pszName, FILE* fStart)
{
    ASSERT(pszName); ASSERT(pszName[0]);
    
    ScriptPtr pScript(new Script(pszName));
    
    bool bCompleted = false;
    char szBuffer[MAX_LINE_LENGTH] = { 0 };
    
    while (LCReadNextConfig(fStart, "*Script", szBuffer, MAX_LINE_LENGTH))
    {
        try
        {
            char szType[MAX_LINE_LENGTH] = { 0 };
            char szRest[MAX_LINE_LENGTH] = { 0 };
            
            // NULL skips the "*Script" token
            char* ppszTokens[] = { NULL, szType };
            
            if (CommandTokenize(szBuffer, ppszTokens, COUNTOF(ppszTokens), szRest) >= 2)
            {
                if (StrIEqual(szType, "~bang"))
                {
                    bCompleted = true;
                    break;
                }
                
                pScript->AddLine(szType, szRest);
            }
            else
            {
                throw invalid_token(szType);
            }
        }
        catch (invalid_token& it)
        {
            int nResponse = AskUser(MB_YESNO | MB_ICONWARNING,
                "Invalid or misplaced token \"%s\" in script \"%s\"\n\n"
                "Continue parsing?",
                it.what(), pszName);
            
            if (nResponse == IDNO)
            {
				g_Logger->logl("ERROR","Invalid or misplaced token <%s> in script <%s>. "
												"Discontinued parsing.",
										it.what(), pszName);
                return false;
            }
			else
			{
				g_Logger->logl("ERROR","Invalid or misplaced token <%s> in script <%s>.\t"
												"Continued parsing.",
										it.what(), pszName);
			}
        }
        catch (invalid_argument& ia)
        {
            int nResponse = AskUser(MB_YESNO | MB_ICONWARNING,
                "Invalid argument in script \"%s\"\n%s\n\n"
                "Continue parsing?",
                ia.what(), pszName);
            
            if (nResponse == IDNO)
            {
				g_Logger->logl("ERROR","Invalid argument in script <%s> %s. "
									"Discontinued parsing?",
									ia.what(), pszName);
                return false;
            }
			else
			{
				g_Logger->logl("ERROR","Invalid argument in script <%s> %s. "
									"Continued parsing?",
									ia.what(), pszName);
			}
        }
    }
    
    if (!bCompleted)
    {
        FormattedException<invalid_argument>(
            "Script %s has no closing ~bang line", pszName);
    }

    ScriptAdd(pScript);

    return true;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// EvalExpression
//
static bool EvalExpression(const string& sExpression)
{
    char szFirst[MAX_LINE_LENGTH] = { 0 };
    char szComp[MAX_LINE_LENGTH] = { 0 };
    char szSecond[MAX_LINE_LENGTH] = { 0 };

    char* ppszTokens[] = { szFirst, szComp, szSecond };
    CommandTokenize(sExpression.c_str(), ppszTokens, COUNTOF(ppszTokens), NULL);

    boost::function2<bool, int, int> fn = std::not_equal_to<int>();

    if (StrIEqual(szComp, "="))
    {
        fn = std::equal_to<int>();
    }
    else if (StrIEqual(szComp, "<="))
    {
        fn = std::less_equal<int>();
    }
    else if (StrIEqual(szComp, ">="))
    {
        fn = std::greater_equal<int>();
    }
    else if (StrIEqual(szComp, "<"))
    {
        fn = std::less<int>();
    }
    else if (StrIEqual(szComp, ">"))
    {
        fn = std::greater<int>();
    }
    else if (StrIEqual(szComp, "<>"))
    {
        fn = std::not_equal_to<int>();
    }

    if (isnum(szFirst) && isnum(szSecond))
    {
        if (fn(atoi(szFirst), atoi(szSecond)))
        {
            return true;
        }
    }
    else
    {
        if (fn(StrIComp(szFirst, szSecond), 0))
        {
            return true;
        }
    }

    return false;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// EvalIf
//
bool EvalIf(std::string& sStatement)
{
    using std::invalid_argument;
    
    bool bReturn = false;
    char szCondition[MAX_LINE_LENGTH] = { 0 };
    char szTrue[MAX_LINE_LENGTH] = { 0 };
    char szFalse[MAX_LINE_LENGTH] = { 0 };
    
    char* ppszTokens[] = { szCondition, szTrue, szFalse };
    
    if (CommandTokenize(sStatement.c_str(), ppszTokens, COUNTOF(ppszTokens), NULL) >= 2)
    {
        if (!szCondition[0])
        {
            throw invalid_argument("No condition in if-statement given");
        }
        
        if (!szTrue[0] && !szFalse[0])
        {
            throw invalid_argument("if-statement has neither actions for "
                "\"true\" nor for \"false\"");
        }
        
        bReturn = EvalExpression(szCondition);
        sStatement.assign(bReturn ? szTrue : szFalse);
    }
    else
    {
        throw invalid_argument("Not enough tokens in if-statement: " +
            sStatement);
    }
    
    return bReturn;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ExecCommand
//
void ExecCommand(const std::string& sCommand)
{
	std::string s = sCommand;
	g_Variables->Expand(s);
    if(!s.empty())
		LSExecute(NULL, s.c_str(), 0);
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
                    "%s %s", g_szAppName, g_szAppVersion)))
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
            LoadSetup(true);

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
