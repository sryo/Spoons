#ifndef MZSCRIPT_SCRIPTS_HPP_INCLUDED
#define MZSCRIPT_SCRIPTS_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  scripts.hpp
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
#include "variables.hpp"


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// class Script
//
class Script
{
public:
    enum LINETYPE { EXEC, LABEL, GOTO, GOTOIF, EXIT };
    
    Script(const std::string& sName) : m_sName(sName) { }
    
    // AddLine can throw ParseError
    void AddLine(const std::string& sType, const std::string& sRest);
    void Execute(Variables::Ptr pVarContext);

    const std::string& GetName() const { return m_sName; }

private:
    typedef std::pair<LINETYPE, std::string> ScriptLine;
    typedef std::vector<ScriptLine> ScriptSource;
    
    std::string m_sName;
    ScriptSource m_Source;
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// typedefs
//
typedef boost::shared_ptr<Script> ScriptPtr;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Function prototypes
//
void ScriptAdd(ScriptPtr pScript);
void ScriptRemove(const std::string& sName);

void ScriptsClear();

void ScriptBangHandler(HWND hCaller, const char* pszName, const char* pszArgs);

   
#endif // !defined(MZSCRIPT_SCRIPTS_HPP_INCLUDED)
