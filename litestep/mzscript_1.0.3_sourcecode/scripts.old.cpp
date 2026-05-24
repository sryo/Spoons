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
// Globals
//
ScriptMap g_ScriptMap;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Script::Addline
//
// throws invalid_argument
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
    
    m_execList.push_back(ExecLine(lineType, sRest));
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Execute
//
void Script::Execute()
{
    for (ExecList::iterator iter = m_execList.begin(); (iter != m_execList.end() && iter->first != EXIT); ++iter)
    {
        char buffer[MAX_LINE_LENGTH] = { 0 };
        char* label = buffer;

        // string sExpanded = fnStringFilter(iter->second);
        // StringCchCopy(buffer, MAX_LINE_LENGTH, sExpanded.c_str());
        
        switch (iter->first)
        {
            case EXEC:
            {
                // Execute(sExpanded);
            }
            break;
            
            case GOTOIF:
            {
/*                if (!EvalIf(buffer, &label))
                {
                    break;
                }*/
            }
            // no break here
            case GOTO:
            {
                for (ExecList::iterator itGoto = m_execList.begin(); itGoto != m_execList.end(); ++itGoto)
                {
                    if (itGoto->first == LABEL && StrIEqual(itGoto->second, label))
                    {
                        iter = itGoto;
                        break;
                    }
                }

                if (iter == m_execList.end())
                {
                    FormattedException<std::invalid_argument>(
                        "Label \"%s\" not found", label);
                }
            }
            break;

            case LABEL:
            break;

            DEFAULT_NOTREACHABLE;
        }
    }
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// bangScript
//
void bangScript(HWND caller, LPCSTR pszName, LPCSTR pszArgs)
{
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ScriptMake
//
ScriptPtr ScriptMake(LPCSTR pszName)
{
    ASSERT(pszName); ASSERT(pszName[0]);

    if (g_ScriptMap.find(pszName) != g_ScriptMap.end())
    {
        FormattedException<std::invalid_argument>("Script %s already exists",
            pszName);
    }

    ScriptPtr pReturn(new Script(pszName));

    g_ScriptMap.insert(ScriptMap::value_type(pszName, pReturn));
    AddBangCommandEx(pszName, bangScript);

    return pReturn;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// ScriptsClear
//
void ScriptsClear()
{
    for (ScriptMap::iterator iter = g_ScriptMap.begin(); iter != g_ScriptMap.end(); ++iter)
    {
        RemoveBangCommand(iter->first.c_str());
    }

    g_ScriptMap.clear();
}
