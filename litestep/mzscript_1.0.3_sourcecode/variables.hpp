#ifndef MZSCRIPT_VARIABLES_HPP_INCLUDED
#define MZSCRIPT_VARIABLES_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  variables.hpp
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
#include "utility.hpp"
#include "varfuncs.hpp"
#include "mzscript.hpp"
#include "SettingsEvalParser.h"

#define TOKEN "token"

using std::string;
using std::list;
using std::vector;
using std::stack;
using std::ifstream;
using std::ofstream;
using std::ios;
using std::endl;

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// class Variable
//
class Variable
{
public:
	Variable() : m_pFunc(NULL), m_sSeparator(":"), m_bCurrent(false) {}

	Variable(const string& sValue, const string& sLine = string(), const string& sFile = string()) :
      m_sValue(sValue), m_pFunc(NULL), m_sFile(sFile), m_sLine(sLine), m_sSeparator(":"), m_bCurrent(false) {}

    Variable(VarFunc pFunc) : m_pFunc(pFunc), m_bCurrent(true) { ASSERT(m_pFunc); }
      
    ~Variable() {}
     
    string Get(string sIndex) const;

    void Set(const string& sValue, string sIndex);

    bool Remove(string sIndex);

    void SetSeparator(const string& sSeparator) { m_sSeparator = sSeparator; }

	void SetTokenSep() {m_sSeparator = TOKEN;}

	string toString() const;

	string VarDump() const;

	void Set(const string& sValue, const string& sLine, const string& sFile) 
					{ m_sValue = sValue; m_sLine = sLine; m_sFile = sFile; }

	string GetLine() const { return m_sLine; }

    string GetFile() const { return m_sFile; }

	void SetCurrent(bool bCurrent) { m_bCurrent = bCurrent; }
	bool GetCurrent() const { return m_bCurrent; }
      
private:
	static int _GetElement(const string& sArray, const string& sSeparator, 
					const int& nIndex, string& sElement);

    static int _GetElementPos(const string& sArray, const string& sSeparator, const int& nIndex, size_t& stStart, size_t& stEnd);

	static string _InterpretIndex(string& sIndex);

    mutable string m_sValue;
	string m_sSeparator;
    string m_sLine;
    string m_sFile;
    VarFunc m_pFunc;
	bool m_bCurrent;	//for !loadvarfile - allows refreshing variables but only 
						//the first time they appear in the file (similar to $vars$)
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// class Variables
//
// Currently only GetValue is aware of m_pParent
//
class Variables
{
public:
    typedef boost::shared_ptr<Variables> Ptr;
    typedef boost::shared_ptr<Variable> VarPtr;
    
    explicit Variables(Ptr pParent) : m_pParent(pParent) {}
    ~Variables(){}
    
    bool Expand(string& sString) const;

    bool Get(string sVariable, string* psValue) const;

    string GetFile(const string& sVariable) const;

    string GetLine(const string& sVariable) const;

    VarPtr Set(string sVariable, const string& sValue);

	VarPtr SetFromFile(string sLine, const string& sFile);

    bool Set(const string& sVariable, VarFunc pFunc);
	
	bool Save(const string& sVariable) const;

	bool SaveAll() const;

    bool Remove(string sVariable);
    
    void Clear() { m_VarMap.clear(); }

    size_t GetCount() const { return m_VarMap.size(); }

	bool VarDump(const string& sFile) const;

	string toString(const string& sVariable) const;

	void ResetCurrent();

	static bool _GetFileTokens(string& sLine, string& sVariable, string& sValue, string& sComment);
    
private:
    typedef std::map<string, VarPtr, stringicmp> VarMap;

    bool _GetValueWorker(const string& sVariable, string* psValue,
        const string& sIndex) const;

	bool _ExpandVarsWorker(string& sString, size_t stPosition) const;


	static size_t _FindComment(string& sLine);

    static string _InterpretVar(string& sVariable);

	bool _SaveWorker(const string& sVariable, const std::string& sLine, const string& sFile) const;

    Ptr m_pParent;
    VarMap m_VarMap;
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// "exports"
//
extern Variables::Ptr g_Variables;


#endif // !defined(MZSCRIPT_VARIABLES_HPP_INCLUDED)
