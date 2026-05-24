//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  bangs.cpp
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

#include "mzscript.hpp"
#include "scripts.hpp"
#include "variables.hpp"
#include "bangs.hpp"



//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// exception class insufficient_args
//
class insufficient_args : public std::invalid_argument
{
public:
    insufficient_args() : invalid_argument("insufficient arguments") { }
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Globals
//
const NamedValue<mzBangCommand> g_InternalBangs[] =
{
    "!varSet",          mzBangSetVar,
    "!varRemove",       mzBangRemoveVar,
    "!varShow",         mzBangShowVar,
    "!varRun",          mzBangRunVar,
    "!varAdd",          mzBangAddVar,
    "!varMul",          mzBangMulVar,
    "!varInt",          mzBangIntVar,
    "!varMod",          mzBangModVar,
    "!varRnd",          mzBangRndVar,
    
    "!varDump",         mzBangVarDump,
    
    "!varSave",         mzBangSaveVar,
    "!varSaveAll",      mzBangSaveAllVars,
    "!ifExist",         mzBangIfExist,
    "!if",              mzBangIf,
    "!exec",            mzBangExec,
    "!msgbox",          mzBangMsgBox,
    "!mzLoadVarFile",		mzBangLoadVarFile,
    //"!scriptload",      mzBangLoadScript,
    //"!scriptremove",    mzBangRemoveScript,
    "!pause",           mzBangPause
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// RegisterBangs
//
void RegisterBangs()
{
    for (size_t i = 0; i < COUNTOF(g_InternalBangs); ++i)
    {
        if (!AddBangCommandEx(g_InternalBangs[i].name, BangThunk))
        {
            string sWhat("Failed to register ");
            sWhat.append(g_InternalBangs[i].name);

            throw std::runtime_error(sWhat);
			g_Logger->logl("ERROR","%s",sWhat);
        }
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// UnregisterBangs
//
void UnregisterBangs()
{
    for (size_t i = 0; i < COUNTOF(g_InternalBangs); ++i)
    {
        RemoveBangCommand(g_InternalBangs[i].name);
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// BangThunk
//
// All calls to internal !bang commands are routed through this function.
//
void BangThunk(HWND /* hCaller */, LPCSTR pszName, LPCSTR pszArgs)
{
    ASSERT(pszName);
    mzBangCommand pfnBang = LookupValue(pszName, g_InternalBangs,
        COUNTOF(g_InternalBangs));

    if (pfnBang)
    {
        string sArgs(pszArgs ? pszArgs : "");
        g_Variables->Expand(sArgs);

		g_Logger->logl("INFO","%s called. Params: <%s> Expanded: <%s>",
            pszName, pszArgs, sArgs.c_str());
        
        TRACE("[%s] called. Params: [%s] Expanded: [%s]",
            pszName, pszArgs, sArgs.c_str());
        
        try
        {
            pfnBang(sArgs);
        }
        catch (std::exception& e)
        {
			ErrorMessage("ERROR","%s failed. Description: %s Parameters: %s "
                "Expanded parameters: %s",
                pszName,
                e.what(),
                pszArgs,
                sArgs.c_str());
        }
        catch (...)
        {
			ErrorMessage("ERROR","%s crashed. Parameters: %s "
                "Expanded parameters: %s",
                pszName,
                pszArgs,
                sArgs.c_str());
        }
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangSetVar
//
void mzBangSetVar(const std::string& sArgs)
{
    char newvar[MAX_LINE_LENGTH] = { 0 };
    char val[MAX_LINE_LENGTH] = { 0 };

    char* tokens[] = { newvar, val };

    int count = CommandTokenize(sArgs.c_str(), tokens, COUNTOF(tokens), NULL);

    if (count <= 1)
    {
        throw insufficient_args();
    }
	else
		g_Variables->Set(newvar, val);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// MathWorker
//
// static void MathWorker(const string& sParams,
//                     boost::function2<int, int, int> fn)
static void MathWorker(const string& sParams,
                       boost::function2<float, float, float> fn)
{
    char szVar[MAX_LINE_LENGTH] = { 0 };
    char szValue[MAX_LINE_LENGTH] = { 0 };
    char* tokens[] = { szVar, szValue };

    int count = CommandTokenize(sParams.c_str(), tokens, COUNTOF(tokens), NULL);

    if (count >= 2)
    {
        string sVarValue;

        if (!g_Variables->Get(szVar, &sVarValue))
        {
            sVarValue.assign("0");
        }

        if (!szValue[0])
        {
            szValue[0] = '0';
        }
        
//        int newValue = fn(atof(sVarValue.c_str()), atof(szValue));
        double newValue = fn(atof(sVarValue.c_str()), atof(szValue));
        
//      g_Variables->Set(szVar, string_cast<int>(newValue));
        g_Variables->Set(szVar, string_cast<double>(newValue));

	    // Now check for whether we should send back a stripped integer
	    // with no floating point nonsense.
	    g_Variables->Get(szVar, &sVarValue);
	    int integerValue = atoi(sVarValue.c_str());
        double floatValue = atof(sVarValue.c_str());
        double difference = floatValue-integerValue;
        if (!(difference > 0) && !(difference < 0))
		{
			g_Variables->Set(szVar, string_cast<int>(integerValue));
		}
    }
    else
    {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangAddVar
//
void mzBangAddVar(const string& sArgs)
{
    MathWorker(sArgs, std::plus<double>());
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangMulVar
//
void mzBangMulVar(const string& sArgs)
{
    MathWorker(sArgs, std::multiplies<double>());
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangIntVar
//
void mzBangIntVar(const string& sArgs)
{
    char szVar[MAX_LINE_LENGTH] = { 0 };
    char* tokens[] = { szVar };

    int count = CommandTokenize(sArgs.c_str(), tokens, COUNTOF(tokens), NULL);

    if (count == 1)
	{
		string szVarValue;
		g_Variables->Get(szVar, &szVarValue);

		int integerValue = atoi(szVarValue.c_str());
		double floatValue = atof(szVarValue.c_str());
		double difference = floatValue-integerValue;
		if (difference >= 0.5)
			integerValue = integerValue + 1;
		g_Variables->Set(szVar, string_cast<int>(integerValue));
		return;
    }
    else {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangModVar
//
void mzBangModVar(const string& sArgs)
{
    MathWorker(sArgs, std::modulus<int>());
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangRndVar
//
void mzBangRndVar(const string& sArgs)
{
    char szVar[MAX_LINE_LENGTH] = { 0 };
    char szValue[MAX_LINE_LENGTH] = { 0 };
    char* tokens[] = { szVar, szValue };
    
    int count = CommandTokenize(sArgs.c_str(), tokens, COUNTOF(tokens), NULL);
    
    if (count >= 2)
    {
        int newValue = 1 + rand() % atoi(szValue);
//        double newValue = 1 + rand() % atoi(szValue);
        
        g_Variables->Set(szVar, string_cast<int>(newValue));
//        g_Variables->Set(szVar, string_cast<double>(newValue));
    }
	else if (count == 1)
	{
        double newValue = rand() / (double)RAND_MAX;
        g_Variables->Set(szVar, string_cast<double>(newValue));
	}
    else
    {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangShowVar
//
void mzBangShowVar(const string& sArgs)
{
    char szVar[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szVar, NULL, FALSE))
    {
        
        string s = g_Variables->toString(szVar).c_str();
        if (!s.empty())
        {			
			MessageBox(NULL, s.c_str(), g_szAppName,
				MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
        }
        else
        {
			char szMessage[MAX_LINE_LENGTH] = { 0 };

            StringCchPrintf(szMessage, MAX_LINE_LENGTH,
                "Variable \"%s\" does not exist.", szVar);
			
			MessageBox(NULL, szMessage, g_szAppName,
				MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
        }

    }
    else
    {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangMsgBox
//
void mzBangMsgBox(const string& sArgs)
{
	if (!sArgs.empty())
    {
        MessageBox(NULL, sArgs.c_str(), g_szAppName,
            MB_OK | MB_TOPMOST | MB_SETFOREGROUND);
    }
    else
    {
        throw insufficient_args();
    }
	/*
    char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, true))
    {
        MessageBox(NULL, szToken, g_szAppName,
            MB_OK | MB_TOPMOST | MB_SETFOREGROUND);
    }
    else
    {
        throw insufficient_args();
    }
	*/
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangRemoveVar
//
void mzBangRemoveVar(const string& sArgs)
{
    char szToken[MAX_LINE_LENGTH] = { 0 };
	LPCSTR nextToken = sArgs.c_str();
	while  (GetToken(nextToken, szToken, &nextToken, TRUE))
	{
            g_Variables->Remove(szToken);
	}
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangRunVar
//
void mzBangRunVar(const string& sArgs)
{
    char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, FALSE))
    {
        string sValue;

        if (g_Variables->Get(szToken, &sValue))
        {
			g_Logger->logl("INFO","Run variable %s with value %s",szToken,sValue.c_str());
            ExecCommand(sValue);
        }
        else
        {
            throw std::invalid_argument("variable doesn't exist");
        }
    }
    else
    {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangSaveVar
//
void mzBangSaveVar(const string& sArgs)
{
	char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, FALSE))
    {
        if(!g_Variables->Save(szToken))
			ErrorMessage("ERROR","Couldn't save variable \"%s\". File failed to open.", szToken);
    }
    else
    {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangSaveAllVars
//
void mzBangSaveAllVars(const string& sArgs)
{
    if(!g_Variables->SaveAll())
		ErrorMessage("ERROR","Couldn't save one or more variables. File(s) failed to open.");
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangVarDump
//
void mzBangVarDump(const string& sArgs)
{
	char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, true))
    {
        if(!g_Variables->VarDump(szToken))
		{
			ErrorMessage("ERROR","Couldn't dump variables. File failed to open.");
		}
    }
    else
    {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangIfExist
//
void mzBangIfExist(const string& sArgs)
{
    char szVar[MAX_LINE_LENGTH] = { 0 };
    char szTrue[MAX_LINE_LENGTH] = { 0 };
    char szFalse[MAX_LINE_LENGTH] = { 0 };
    
    char* ppszTokens[] = { szVar, szTrue, szFalse };
    
    if (CommandTokenize(sArgs.c_str(), ppszTokens, COUNTOF(ppszTokens), NULL) >= 2)
    {
        if (g_Variables->Get(szVar, NULL))
        {
            ExecCommand(szTrue);
        }
        else
        {
            ExecCommand(szFalse);
        }
    }
    else
    {
        throw insufficient_args();
    }
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangIf
//
void mzBangIf(const string& sArgs)
{
    if (!sArgs.empty())
    {
        string sStatement(sArgs);
        
        EvalIf(sStatement);

        ExecCommand(sStatement);
    }
    else
    {
        throw insufficient_args();
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangExec
//
// Helper !bang to use var expansion outside of scripts
//
void mzBangExec(const string& sArgs)
{
	if (!sArgs.empty())
    {
        ExecCommand(sArgs);
    }
    else
    {
        throw insufficient_args();
    }

	/*
    char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, FALSE))
    {
        ExecCommand(szToken);
    }
    else
    {
        throw insufficient_args();
    }
	*/
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangLoadVar
//
void mzBangLoadVarFile(const string& sArgs)
{
    char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, true))
    {
		g_Variables->ResetCurrent();
        LoadVarFile(szToken);
    }
    else
    {
        throw insufficient_args();
    }
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangLoadScript
//
void mzBangLoadScript(const string& sArgs)
{
/*    char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, FALSE))
    {
        readScriptFile(szToken, false);
    }
    else
    {
        throw insufficient_args();
    }*/
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangRemoveScript
//
void mzBangRemoveScript(const string& sArgs)
{
/*    char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, FALSE))
    {
        string sCommand("!");
        sCommand.append(szToken);
        
        removeScriptBang(sCommand.c_str());
    }
    else
    {
        throw insufficient_args();
    }*/
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// mzBangPause
//
void mzBangPause(const string& sArgs)
{
    char szToken[MAX_LINE_LENGTH] = { 0 };
    
    if (GetToken(sArgs.c_str(), szToken, NULL, true))
    {
        unsigned long lInterval = atoi(szToken);
        unsigned long lTime = GetTickCount();
        MSG msg;
        
        if (lInterval > 0)
        {
            while ((GetTickCount() - lTime) < lInterval)
            {
                if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
                {
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            }
			g_Logger->logl("INFO","Paused for %s milliseconds", szToken);
        }
    }
    else
    {
        throw insufficient_args();
    }
}
