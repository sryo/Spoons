//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  scripts.cpp
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

using std::string;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// typedefs
//
//
typedef std::map<string, ScriptPtr, stringicmp> ScriptMap;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Local helper functions
//
//
static ScriptMap::iterator ScriptFind(const std::string& sName);
static void ScriptRemove(ScriptMap::iterator iter);


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Globals
//
//
ScriptMap g_Scripts;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Script::Addline
//
//
void Script::AddLine(const string& sType, const string& sRest)
{
    LINETYPE lineType;
    
    if (StrIEqual(sType, "exit"))
    {
        lineType = EXIT;
    }
    else if (sRest.empty())
    {
        // all linetypes from here on need something in sRest
        FormattedException<std::invalid_argument>(
            "Insufficient tokens for \"%s\"", sType.c_str());
    }
    else if (StrIEqual(sType, "exec"))
    {
        lineType = EXEC;
    }
    else if (StrIEqual(sType, "label"))
    {
        lineType = LABEL;
    }
    else if (StrIEqual(sType, "goto"))
    {
        lineType = GOTO;
    }
    else if (StrIEqual(sType, "gotoif"))
    {
        lineType = GOTOIF;
    }
    else
    {
        throw invalid_token(sType);
    }
    
    m_Source.push_back(ScriptLine(lineType, sRest));
}



//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Script::Execute
//
//
void Script::Execute(Variables::Ptr pVarContext)
{
    ASSERT(pVarContext);
    using std::invalid_argument;
    
    try
    {
        for (ScriptSource::iterator iter = m_Source.begin();
             iter != m_Source.end(); ++iter)
        {
            string sLine(iter->second);
            pVarContext->Expand(sLine);

            switch (iter->first)
            {
                case EXEC:
                {
                    ExecCommand(sLine);
                }
                break;
                
                case GOTOIF:
                {
					//expand $vars$
					char szBuffer[MAX_LINE_LENGTH]= { 0 };
					VarExpansion(szBuffer, sLine.c_str());
					sLine.assign(szBuffer);

                    EvalIf(sLine);
                    if (sLine.empty())
                    {
                        break;
                    }
                }
                case GOTO:
                {
                    for (iter = m_Source.begin(); iter != m_Source.end(); ++iter)
                    {
                        if (iter->first == LABEL &&
                            StrIEqual(iter->second.c_str(), sLine.c_str()))
                        {
                            break;
                        }
                    }
                    
                    if (iter == m_Source.end())
                    {
                        throw invalid_argument("Label \"" + sLine +
                            "\" not found");
                    }
                }
                break;
                
                case EXIT:
                {
                    return;
                }
                break;

                // label lines
                default:
                {
                    ASSERT(iter->first == LABEL);
                    continue;
                }
            }
        }
    }
    catch (invalid_argument& e)
    {
		ErrorMessage("ERROR","Script execution stopped in %s: %s",
            m_sName.c_str(), e.what());
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ScriptFind
//
//
static ScriptMap::iterator ScriptFind(const string& sName)
{
    ASSERT(!sName.empty());
    return g_Scripts.find(sName);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ScriptAdd
//
//
void ScriptAdd(ScriptPtr pScript)
{
    ASSERT(pScript);
    ScriptMap::iterator iter = ScriptFind(pScript->GetName());
    
    if (iter != g_Scripts.end())
    {
        ScriptRemove(iter);
        
		ErrorMessage("ERROR","Script \"%s\" already defined. Old version removed.",
            pScript->GetName().c_str());
    }

    g_Scripts.insert(ScriptMap::value_type(pScript->GetName(), pScript));
    AddBangCommandEx(pScript->GetName().c_str(), ScriptBangHandler);
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ScriptRemove
//
//
static void ScriptRemove(ScriptMap::iterator iter)
{
    ASSERT(iter != g_Scripts.end());

    RemoveBangCommand(iter->first.c_str());
    g_Scripts.erase(iter);
}

void ScriptRemove(const string& sName)
{
    ASSERT(!sName.empty());
    ScriptMap::iterator iter = ScriptFind(sName);

    if (iter != g_Scripts.end())
    {
        ScriptRemove(iter);
    }
    else
    {
		ErrorMessage("ERROR","Removal of nonexistent script <%s>", sName.c_str());
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ScriptsClear
//
//
void ScriptsClear()
{
    for (ScriptMap::iterator iter = g_Scripts.begin(); iter != g_Scripts.end(); ++iter)
    {
        RemoveBangCommand(iter->first.c_str());
    }

    g_Scripts.clear();
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ScriptsBangHandler
//
//
void ScriptBangHandler(HWND /* hCaller */, const char* pszName,
                       const char* pszArgs)
{
    ScriptMap::iterator iter = ScriptFind(pszName);

    ASSERT(iter != g_Scripts.end());
    ASSERT(iter->second);

    Variables::Ptr pLocalVars(new Variables(g_Variables));

    if (pLocalVars)
    {
        pLocalVars->Set("script", pszName);

        Variables::VarPtr pArgsVar = pLocalVars->Set("args",
            pszArgs ? pszArgs : "");
        
        if (pArgsVar)
        {
            pArgsVar->SetTokenSep();
        }
        
        ScriptPtr pScript = iter->second;
        pScript->Execute(pLocalVars);
    }
    else
    {
		ErrorMessage("ERROR","Couldn't create local variables for Script \"%s\". "
                     "Script stopped. Out of memory?", pszName);
    }
}
