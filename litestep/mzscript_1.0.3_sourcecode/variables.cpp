//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  variables.cpp
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
#include "variables.hpp"

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Globals/Static members
//
// Ptr to the map that holds all of the variables
//    
Variables::Ptr g_Variables(new Variables(Variables::Ptr()));


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variable::Get
//
// returns the value at sIndex
//
string Variable::Get(string sIndex) const
{
	string sReturn;
	string sLineIndex = _InterpretIndex(sIndex);

	if (m_pFunc)
	{
		m_sValue = m_pFunc();
	}

	if (isnum(sIndex))
	{
		int nIndex = atoi(sIndex.c_str());

		if (nIndex > 0)
		{
			// array handling
			string sElement;
			if (_GetElement(m_sValue, m_sSeparator, nIndex, sElement) == nIndex)
			{
				sReturn.assign(sElement);
			}
		}
	}
	else if (StrIEqual(sIndex, "count"))
	{
		size_t stDummy1, stDummy2;
		sReturn = string_cast(_GetElementPos(m_sValue, m_sSeparator, INT_MAX, stDummy1, stDummy2));
	}
	else if (StrIEqual(sIndex, "line"))
	{
		if(isnum(sLineIndex))
		{
			int nLineIndex = atoi(sLineIndex.c_str());
			if (nLineIndex > 0)
			{
				string sElement;
				if (_GetElement(m_sLine, TOKEN, nLineIndex, sElement) == nLineIndex)
				{
					sReturn.assign(sElement);
				}
			}
		}
		else if (StrIEqual(sLineIndex, "count"))
		{
			size_t stDummy1, stDummy2;
			sReturn = string_cast(_GetElementPos(m_sLine, TOKEN, INT_MAX, stDummy1, stDummy2));
		}
		else
			sReturn.assign(m_sLine);
	}
	else if (StrIEqual(sIndex, "file"))
	{
		sReturn.assign(m_sFile);
	}
	else if (StrIEqual(sIndex, "sep"))
	{
		sReturn.assign(m_sSeparator);
	}
	else
	{
		sReturn.assign(m_sValue);
	}

	return sReturn;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variable::Set
//
// sets the element at sIndex to sValue
//
void Variable::Set(const string& sValue, string sIndex)
{
	string sLineIndex = _InterpretIndex(sIndex);
	if (isnum(sIndex))
	{
		int nIndex = atoi(sIndex.c_str());

		if (nIndex > 0)
		{
			//
			// array handling
			//
			size_t stStart, stEnd;
			int nElements = _GetElementPos(m_sValue, m_sSeparator, nIndex, stStart, stEnd);

			if (nElements != nIndex)
			{
				// If the separator is NULL, we don't need to worry about it
				if (m_sSeparator.empty())
					stStart = stEnd = m_sValue.length();
				else if (StrIEqual(m_sSeparator,TOKEN))
				{
					if(!isspace((unsigned char)m_sValue.at(m_sValue.length()-1)))
						m_sValue.append(" ");

					if(nIndex-nElements > 1)
					{
						for(int i=nIndex-nElements; i>1; i--)
							m_sValue.append("\"\" ");
					}
					stStart = stEnd = m_sValue.length();
				}
				else
				{
					for(int i=nIndex-nElements; i>0; i--) // used to be 0, changed to see if fixes separator prefix for 1st element in array when defining a new, unused list variable.
					{
						if (nIndex != 1)
							m_sValue.append(m_sSeparator);
					}
					stStart = stEnd = m_sValue.length();
				}
			}

			m_sValue.replace(stStart, stEnd-stStart, sValue);
			
			GetTokenPos(m_sLine.c_str(), stStart, stEnd, true, true);
			m_sLine.replace(stStart, stEnd - stStart, m_sValue);
		}
	}
	else if (StrIEqual(sIndex, "line"))
	{
		if(isnum(sLineIndex))
		{
			int nLineIndex = atoi(sLineIndex.c_str());
			if (nLineIndex > 0)
			{
				size_t stStart, stEnd;
				int nElements = _GetElementPos(m_sLine, TOKEN, nLineIndex, stStart, stEnd);

				if (nElements != nLineIndex)
				{
					//add the missing tokens as ""'s
					if(!isspace((unsigned char)m_sLine.at(m_sLine.length()-1)))
						m_sLine.append(" ");

					if(nLineIndex-nElements > 1)
					{
						for(int i=nLineIndex-nElements; i>1; i--)
							m_sLine.append("\"\" ");
					}
					stStart = stEnd = m_sLine.length();
				}

				m_sLine.replace(stStart, stEnd-stStart, sValue);
				
				if(nLineIndex == 1)
				{
					char szValue[MAX_LINE_LENGTH] = { 0 };
					if (GetToken(m_sLine.c_str(), szValue, NULL, TRUE))
					{
						m_sValue.assign(szValue);
					}
					else
						m_sValue.clear();
				}
			}
		}
		else
		{
			m_sLine.assign(sValue);

			char szValue[MAX_LINE_LENGTH] = { 0 };
			if (GetToken(m_sLine.c_str(), szValue, NULL, TRUE))
			{
				m_sValue.assign(szValue);
			}
			else
				m_sValue.clear();
		}
	}
	else if (StrIEqual(sIndex, "sep"))
	{
		m_sSeparator.assign(sValue);
	}
	else
	{
		//
		// change entire value
		//
		m_sValue = sValue;

		size_t stStart, stEnd;
		GetTokenPos(m_sLine.c_str(), stStart, stEnd, true, true);
		m_sLine.replace(stStart, stEnd - stStart, m_sValue);
	}
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variable::Remove
//
// Returns true if the variable can be deleted
//
bool Variable::Remove(string sIndex)
{
	string sLineIndex = _InterpretIndex(sIndex);
	if (isnum(sIndex))
	{
		int nIndex = atoi(sIndex.c_str());

		if (nIndex > 0)
		{
			size_t stStart, stEnd;

			if (_GetElementPos(m_sValue, m_sSeparator, nIndex, stStart, stEnd) == nIndex)
			{
				if (StrIEqual(m_sSeparator,TOKEN))
				{
					//remove the surrounding quotes/brackets
					if(stStart && stStart <= m_sValue.length() && !isspace((unsigned char)m_sValue.at(stStart-1)))
						stStart--;
					if(stEnd < m_sValue.length() && !isspace((unsigned char)m_sValue.at(stEnd)))
						stEnd++;
				}
				else if (nIndex > 1)
				{
					// need to delete the leading separator if not NULL
					if (!m_sSeparator.empty())
						stStart-=m_sSeparator.length();
				}
				else if (stEnd != string::npos)
				{
					// need to delete the trailing separator if not NULL
					if (!m_sSeparator.empty())
						stEnd+=m_sSeparator.length();
				}

				m_sValue.erase(stStart, stEnd-stStart);

				GetTokenPos(m_sLine.c_str(), stStart, stEnd, true, true);
				m_sLine.replace(stStart, stEnd - stStart, m_sValue);
			}

		}
		
		return false;
	}
	else if (StrIEqual(sIndex, "sep"))
	{
		m_sSeparator.clear();
		return false;
	}
	else if (StrIEqual(sIndex, "line"))
	{
		if(isnum(sLineIndex))
		{
			int nLineIndex = atoi(sLineIndex.c_str());

			if (nLineIndex > 0)
			{
				size_t stStart, stEnd;

				if (_GetElementPos(m_sLine, TOKEN, nLineIndex, stStart, stEnd) == nLineIndex)
				{
					//remove the surrounding quotes/brackets
					if(stStart && stStart <= m_sLine.length() && !isspace((unsigned char)m_sLine.at(stStart-1)))
						stStart--;
					if(stEnd < m_sLine.length() && !isspace((unsigned char)m_sLine.at(stEnd)))
						stEnd++;

					m_sLine.erase(stStart, stEnd-stStart);

					if(nLineIndex == 1)
					{
						char szValue[MAX_LINE_LENGTH] = { 0 };
						if (GetToken(m_sLine.c_str(), szValue, NULL, TRUE))
						{
							m_sValue.assign(szValue);
						}
						else
							m_sValue.clear();
					}
				}

			}
		}
		else
		{
			m_sLine.clear();
			m_sValue.clear();
		}
		return false;
	}
	else if (!sIndex.empty())
	{
		return false;
	}

	return true;
}

string Variable::toString() const
{
	string sResult;
	sResult.append("\nValue\t   =");
	sResult.append(m_sValue);
	sResult.append("\nSep\t   =");
	sResult.append(m_sSeparator);
	sResult.append("\nCount\t   =");
	sResult.append(Get("count"));
	sResult.append("\n\nLine\t   =");
	sResult.append(m_sLine);
	sResult.append("\nLine:Count  =");
	sResult.append(Get("line:count"));
	sResult.append("\n\nFile\t   =");
	sResult.append(m_sFile);
	return sResult;
}

string Variable::VarDump() const
{
	string sResult;
	sResult.append(m_sValue);
	sResult.append("|");
	sResult.append(m_sSeparator);
	sResult.append("|");
	sResult.append(Get("count"));
	sResult.append("|");
	sResult.append(m_sLine);
	sResult.append("|");
	sResult.append(Get("line:count"));
	sResult.append("|");
	sResult.append(m_sFile);
	return sResult;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variable::_GetElement
//
// Get the value of element nIndex in the array
//
// This takes in an index of the variable array and sets sElement
// to the value in the string of this element. It returns 
// either nIndex or the count of elements if nIndex > count.
int Variable::_GetElement(const string& sArray, const string& sSeparator, const int& nIndex, string& sElement)
{
	ASSERT(nIndex > 0);
	//empty array - return 0
	if (sArray.empty())
		return 0;
	//token sep
	else if (StrIEqual(sSeparator, TOKEN))
	{
		char szToken[MAX_LINE_LENGTH] = { 0 };
		LPCSTR pszRest = sArray.c_str();
		//fill vElements
		for(int nCounter = 1; nCounter < nIndex; nCounter++)
		{
			if(!GetToken(pszRest, NULL, &pszRest, true, true))
				return nCounter - 1;
		}

		if(GetToken(pszRest, szToken, NULL, true, true))
		{
			sElement.assign(szToken);
		}
		else
			return nIndex - 1;

	}
	//null sep
	else if (sSeparator.empty())
	{
		if (nIndex > (int)sArray.length())
		{
			return (int)sArray.length();
		}

		sElement.assign(string_cast(sArray.c_str()[nIndex-1]));
	}
	//string sep
	else
	{

		size_t	stStart = 0,
				stEnd = 0,
				stCurrent = 0;
		for(int nCounter = 1; nCounter <= nIndex; nCounter++)
		{
			stStart = stEnd;
			stEnd = sArray.find(sSeparator,stCurrent);
			stCurrent = stEnd + sSeparator.length();
			if(stEnd == string::npos && nCounter < nIndex)
				return nCounter;
		}
		if(nIndex > 1)
			stStart += sSeparator.length();
		sElement.assign(sArray.substr(stStart, stEnd - stStart));
		/*
		size_t stStart = 0;
		size_t stEnd = 0;
		for(int nCounter = 1; nCounter <= nIndex; nCounter++)
		{
			stStart = stEnd;
			stEnd = sArray.find(sSeparator,stStart);
			if(stEnd == string::npos && nCounter < nIndex)
				return nCounter;
		}
		if(nIndex > 1)
			stStart += sSeparator.length();
		sElement.assign(sArray.substr(stStart, stEnd - stStart));
		*/
	}
	return nIndex;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variable::_GetElementPos
//
// Get the position of element nIndex in the array
//
// This takes in an index of the variable array and sets stStart
// and stEnd to the positions in the string of this element. It returns 
// either nIndex or the count of elements if nIndex > count.
int Variable::_GetElementPos(const string& sArray, const string& sSeparator, const int& nIndex, size_t& stStart, size_t& stEnd)
{
	ASSERT(nIndex > 0);
	//empty array - return 0
	if (sArray.empty())
		return 0;
	//token sep
	else if (StrIEqual(sSeparator, TOKEN))
	{
		LPCSTR pszRest = sArray.c_str();
		LPCSTR pszStartMarker = pszRest;

		for(int nCounter = 1; nCounter < nIndex; nCounter++)
		{
			if(!GetToken(pszRest, NULL, &pszRest, true, true))
				return nCounter - 1;
		}

		if(!GetTokenPos(pszRest, stStart, stEnd, true, true))
			return nIndex - 1;

		stStart += pszRest - pszStartMarker;
		stEnd += pszRest - pszStartMarker;
	}
	//null sep
	else if (sSeparator.empty())
	{
		if (nIndex > (int)sArray.length())
		{
			return (int)sArray.length();
		}

		stStart = nIndex -1;
		stEnd = nIndex;
	}
	//string sep
	else
	{
		stStart = stEnd = 0;
		size_t stCurrent = 0;
		for(int nCounter = 1; nCounter <= nIndex; nCounter++)
		{
			stStart = stEnd;
			stEnd = sArray.find(sSeparator,stCurrent);
			stCurrent = stEnd + sSeparator.length();
			if(stEnd == string::npos && nCounter < nIndex)
				return nCounter;
		}
		if(nIndex > 1)
			stStart += sSeparator.length();
	}
	return nIndex;

		/*	ASSERT(nIndex > 0);

	if (m_sValue.empty())
	{
		nIndex = stStart = stEnd = 0;
	}
	else if (m_bTokenSep)
	{
		vector<string> vElements;
		string sToken;
		string sRemaining = m_sValue;
		char szToken[MAX_LINE_LENGTH] = { 0 };
		LPCSTR pszRest = NULL;
		//fill vElements
		do
		{
			GetToken(sRemaining.c_str(), szToken, &pszRest, true);
			sToken.assign(szToken);

			if(!sToken.empty())
				vElements.push_back(sToken);
			if(pszRest)
				sRemaining.assign(pszRest);
		}while(pszRest && !sRemaining.empty());

		//if nIndex is greater than # of elements, set it to # of elements
		if(nIndex > (int)vElements.size())
			nIndex = vElements.size();
		if(nIndex > 0)
		{
			//set stStart to the position of the nIndex'th element
			stStart = m_sValue.find(vElements[nIndex-1]);
			//set stEnd to stStart plus the length of the nIndex'th element
			stEnd = stStart + vElements[nIndex-1].length();
		}
		else
			stStart = stEnd = 0;
	}
	else if (m_sSeparator.empty())
	{
		//
		// iterate through the string if separator is empty
		//
		if (nIndex > (int)m_sValue.length())
		{
			nIndex = m_sValue.length();
		}

		stStart = nIndex-1;
		stEnd = nIndex;
	}
	else
	{
		vector<string> vElements;
		stStart = stEnd = 0;

		//fill vElements with the elements
		do
		{
			stEnd = m_sValue.find(m_sSeparator,stStart);
			vElements.push_back(m_sValue.substr(stStart, stEnd-stStart));
			stStart = stEnd + m_sSeparator.length();
		}
		while(stEnd != string::npos);

		//if nIndex is greater than # of elements, set it to # of elements
		if(nIndex > (int)vElements.size())
			nIndex = vElements.size();
		if(nIndex > 0)
		{
			//set stStart to the position of the nIndex'th element
			stStart = m_sValue.find(vElements[nIndex-1]);
			//set stEnd to stStart plus the length of the nIndex'th element
			stEnd = stStart + vElements[nIndex-1].length();
		}
		else
			stStart = stEnd = 0;

		bool bInQuote = false;

		string::const_iterator iter, itStart, itEnd;

		iter = itEnd = m_sValue.begin();
		itStart = m_sValue.end();
		--itEnd;

		do
		{
			if (iter == m_sValue.end() || (*iter == m_sSeparator && !bInQuote))
			{
				itStart = itEnd;
				itEnd = iter;
				--nCounter;
			}
			else if (*iter == '\"')
			{
				bInQuote = !bInQuote;
			}
		}while (iter++ != m_sValue.end() && nCounter);

		stStart = itStart - m_sValue.begin() + 1;
		stEnd = itEnd - m_sValue.begin();
	}

	return (nIndex==0) ? 1 : nIndex;
		*/
}

string Variable::_InterpretIndex(string& sIndex)
{
	string sReturn;

	size_t stIndex = sIndex.find(':');

	if (stIndex != string::npos && sIndex.length() > stIndex+1)
	{
		sReturn.assign(&sIndex.c_str()[stIndex+1]);
		sIndex.erase(stIndex, sIndex.length()-stIndex);
	}

	return sReturn;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::Get
//
//puts the value of sVariable into psValue
bool Variables::Get(string sVariable, string* psValue) const
{
	assert(!sVariable.empty());
	string sIndex = _InterpretVar(sVariable);

	return _GetValueWorker(sVariable, psValue, sIndex);
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::_GetValueWorker
//
bool Variables::_GetValueWorker(const string& sVariable, string* psValue,
								const string& sIndex) const
{
	VarMap::const_iterator iter = m_VarMap.find(sVariable);

	if (iter != m_VarMap.end())
	{
		ASSERT(iter->second);

		if (psValue)
		{
			*psValue = iter->second->Get(sIndex);
		}

		return true;
	}

	if (m_pParent)
	{
		return m_pParent->_GetValueWorker(sVariable, psValue, sIndex);
	}

	return false;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::GetFile
//
// return the m_sFile of the variable
//
string Variables::GetFile(const string& sVariable) const
{
	assert(!sVariable.empty());

	VarMap::const_iterator iter = m_VarMap.find(sVariable);

	if (iter != m_VarMap.end())
	{
		ASSERT(iter->second);

		return iter->second->GetFile();
	}

	return string();
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::GetLine
//
// return the m_sLine of the variable
//
string Variables::GetLine(const string& sVariable) const
{
	assert(!sVariable.empty());

	VarMap::const_iterator iter = m_VarMap.find(sVariable);

	if (iter != m_VarMap.end())
	{
		ASSERT(iter->second);

		return iter->second->GetLine();
	}

	return string();
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::Set
//
// Change a variable's value or create a new variable
//
Variables::VarPtr Variables::Set(string sVariable, const string& sValue)
{
	assert(!sVariable.empty());
	VarPtr result;

	string sIndex = _InterpretVar(sVariable);
	VarMap::iterator iter = m_VarMap.find(sVariable);

	if (iter != m_VarMap.end())
	{
		ASSERT(iter->second);

		// variable already exists, change its value
		iter->second->Set(sValue, sIndex);
		if(sIndex.empty())
			g_Logger->logl("INFO","%s set to <%s>", sVariable.c_str(), sValue.c_str());
		else
			g_Logger->logl("INFO","%s:%s set to <%s>", sVariable.c_str(), sIndex.c_str(), sValue.c_str());

		result = iter->second;
	}
	else
	{
		// create a new variable
		VarPtr pVar = VarPtr(new Variable());

		if (pVar)
		{
			pVar->Set(sValue, sIndex);
			if(sIndex.empty())
				g_Logger->logl("INFO","%s set to <%s>", sVariable.c_str(), sValue.c_str());
			else
				g_Logger->logl("INFO","%s:%s set to <%s>", sVariable.c_str(), sIndex.c_str(), sValue.c_str());

			m_VarMap.insert(VarMap::value_type(sVariable, pVar));

			result = pVar;
		}
		else
		{
			ErrorMessage("ERROR","Couldn't set variable \"%s\" to value \"%s\". "
				"Out of memory?", sVariable.c_str(), sValue.c_str());
		}
	}

	return result;
}

//pass in the full line from mzvarfile and the file path
Variables::VarPtr Variables::SetFromFile(string sLine, const string& sFile)
{
	VarPtr result;
	string sVariable, sValue, sComment;
	if(_GetFileTokens(sLine, sVariable, sValue, sComment))
	{
		assert(!sVariable.empty());

		//Expand(sLine);
		string sIndex = _InterpretVar(sVariable);

		VarMap::iterator iter = m_VarMap.find(sVariable);

		if (iter != m_VarMap.end())
		{
			ASSERT(iter->second);
			if(iter->second->GetCurrent())
			{
				ErrorMessage("WARNING:\tVariable <%s> has already been read in from <%s>. "
					"Second instance ignored.", sVariable.c_str(), iter->second->GetFile().c_str());
			}
			else
			{
				iter->second->SetCurrent(true);
				if(sIndex.empty())
				{
					iter->second->Set(sValue, sLine, sFile);
					g_Logger->logl("INFO","%s set to <%s> with line <%s>", sVariable.c_str(), sValue.c_str(), sLine.c_str());
				}
				else
				{
					iter->second->Set(sValue, sIndex);
					g_Logger->logl("INFO","%s:%s set to <%s>", sVariable.c_str(), sIndex.c_str(), sValue.c_str());
				}
			}

			result = iter->second;
		}
		else
		{
			// create a new variable
			VarPtr pVar = VarPtr(new Variable());

			if (pVar)
			{
				pVar->SetCurrent(true);

				if(sIndex.empty())
				{
					pVar->Set(sValue, sLine, sFile);
					g_Logger->logl("INFO","%s set to <%s> with line <%s>", sVariable.c_str(), sValue.c_str(), sLine.c_str());
				}
				else
				{
					pVar->Set(sValue, sIndex);
					g_Logger->logl("INFO","%s:%s set to <%s>", sVariable.c_str(), sIndex.c_str(), sValue.c_str());
				}

				m_VarMap.insert(VarMap::value_type(sVariable, pVar));

				result = pVar;
			}
			else
			{
				ErrorMessage("ERROR","Couldn't create variable \"%s\". Out of memory?", sVariable.c_str());
			}
		}
	}
	return result;
}

//pass in the name and a varfunc
bool Variables::Set(const string& sVariable, VarFunc pFunc)
{
	ASSERT(!sVariable.empty());

	m_VarMap.erase(sVariable);

	VarPtr pVar = VarPtr(new Variable(pFunc));

	if (pVar)
	{
		m_VarMap.insert(VarMap::value_type(sVariable, pVar));
		return true;
	}

	ErrorMessage("ERROR","Couldn't set function variable \"%s\". Out of memory?",
		sVariable.c_str());

	return false;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::Save
//
//get the variable and call its save func
//if it doesn't exist or was not read in from file return false
//
bool Variables::Save(const std::string& sVariable) const
{
	assert(!sVariable.empty());
	VarMap::const_iterator iter = m_VarMap.find(sVariable);

	if (iter != m_VarMap.end())
	{
		ASSERT(iter->second);

		return _SaveWorker( iter->first, iter->second->GetLine(), iter->second->GetFile() );
	}

	return false;	//variable doesn't exist
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::SaveAll
//
bool Variables::SaveAll() const
{
	g_Logger->logl("INFO","Saving all variables");
	bool bReturn = true;
	for(VarMap::const_iterator iter = m_VarMap.begin(); iter!=m_VarMap.end(); ++iter)
	{
		ASSERT(iter->second);

		if(!_SaveWorker( iter->first, iter->second->GetLine(), iter->second->GetFile() ))
			bReturn = false;
	}
	g_Logger->logl("INFO","Saved all variables");
	return bReturn;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::_SaveWorker
//
bool Variables::_SaveWorker(const std::string& sVariable, const std::string& sLine, const std::string& sFile) const
{
	//if there is no file, then it is internal and doesn't need to be saved
	if(sFile.empty())
		return true;

	char szBuffer[MAX_LINE_LENGTH] = { 0 };
	bool bFound = false;
	bool bChanged = false;
	EvalParser evalParser;
	stack<bool> stkCurrent;
	stack<bool> stkEval;


	ifstream file;
	file.open(sFile.c_str());
	if (file.is_open())
	{
		list<string> l;
		string s, f_sLine, f_sVariable, f_sValue, f_sComment;

		while (!file.eof() && (!bFound || bChanged))
		{
			file.getline(szBuffer, MAX_LINE_LENGTH);
			if(!bFound)
			{
				f_sLine.assign(szBuffer);
				if(!_GetFileTokens(f_sLine, f_sVariable, f_sValue, f_sComment))
				{
					l.push_back(szBuffer);
					continue;
				}

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

				if(StrIEqual(sVariable,f_sVariable) && (stkCurrent.empty() || stkCurrent.top()))
				{
					bFound = true;
					string f_sLineExpanded = f_sLine;
					Expand(f_sLineExpanded);
					if(!StrIEqual(sLine,f_sLineExpanded))
					{
						s.assign(szBuffer);
						size_t stLinePos = s.find(f_sVariable);

						ASSERT(stLinePos != string::npos);

						s.erase(stLinePos);
						s.append(f_sVariable);
						if(!strchr(" \t", sLine.c_str()[0]))
							s.append(" ");
						s.append(sLine);
						s.append(f_sComment);

						l.push_back(s);
						bChanged = true;
						continue;
					}
					else
					{
						l.push_back(szBuffer);
						continue;
					}
				}
			}
			l.push_back(szBuffer);
		}
		file.close();
		if(bFound && bChanged)
		{
			ofstream outfile;
			outfile.open(sFile.c_str());
			if (outfile.is_open())
			{
				list<string>::const_iterator lci = l.begin();
				if(lci!=l.end())
				{
					outfile << lci->data();
					lci++;
				}
				for (lci; lci!=l.end(); lci++)
				{
					outfile << endl << lci->data();
				}
				l.clear();
			}
			else
			{
				g_Logger->logl("ERROR","Could not open <%s> for writing.",
						sFile.c_str());
				return false;
			}
			g_Logger->logl("INFO","%s saved as line <%s> in <%s>", sVariable.c_str(), sLine.c_str(), sFile.c_str());
		}
		else if(bFound)
		{
			return true;
		}
		else
		{
			g_Logger->logl("ERROR","Variable %s could not be saved. It was not found in <%s>. The file may have been altered.", sVariable.c_str(), sFile.c_str());
			return false;
		}
	}
	else
	{
		return false;
	}

	return true;
}

//bool Variables::_SaveWorker(const std::string& sVariable, const std::string& sLine, const std::string& sFile) const
//{
//	//if there is no file, then it is internal and doesn't need to be saved
//	if(sFile.empty())
//		return true;
//
//	char szBuffer[MAX_LINE_LENGTH] = { 0 };
//	bool found = false;
//	bool changed = false;
//
//	ifstream file;
//	file.open(sFile.c_str());
//	if (file.is_open())
//	{
//		list<string> l;
//		string s, f_sLine, f_sVariable, f_sValue;
//
//		while (!file.eof() && ((found && changed) || !found))
//		{
//			file.getline(szBuffer, MAX_LINE_LENGTH);
//			if(!found)
//			{
//				f_sLine.assign(szBuffer);
//				_GetFileTokens(f_sLine, f_sVariable, f_sValue);
//
//				if(StrIEqual(sVariable,f_sVariable))
//				{
//					found = true;
//					if(sLine.compare(f_sLine) != 0)
//					{
//						s.assign(szBuffer);
//						size_t stLinePos = s.find(f_sVariable);
//
//						ASSERT(stLinePos != string::npos);
//
//						s.erase(stLinePos);
//						s.append(f_sVariable);
//						if(!strchr(" \t", f_sLine.c_str()[0]))
//							s.append(" ");
//						s.append(f_sLine);
//
//						l.push_back(s);
//						changed = true;
//					}
//					else
//						changed = false;
//				}
//				else
//					l.push_back(szBuffer);
//			}
//			else
//			{
//				l.push_back(szBuffer);
//			}
//		}
//		file.close();
//		if(found && changed)
//		{
//			ofstream outfile;
//			outfile.open(sFile.c_str());
//			if (outfile.is_open())
//			{
//				list<string>::const_iterator lci = l.begin();
//				if(lci!=l.end())
//				{
//					outfile << lci->data();
//					lci++;
//				}
//				for (lci; lci!=l.end(); lci++)
//				{
//					outfile << endl << lci->data();
//				}
//				l.clear();
//			}
//			else
//			{
//				return false;
//			}
//			g_Logger->logl("INFO","%s\n\t\tsaved as line \"%s\"\n\t\tin \"%s\"", sVariable.c_str(), sLine.c_str(), sFile.c_str());
//		}
//		else if(found)
//		{
//			return true;
//		}
//		else
//		{
//			g_Logger->logl("ERROR","Variable %s could not be saved.\n\t\tIt was not found in \"%s\".\n\t\tThe file may have been altered.", sVariable.c_str(), sFile.c_str());
//			return false;
//		}
//	}
//	else
//	{
//		return false;
//	}
//
//	return true;
//}



//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::Remove
//
bool Variables::Remove(string sVariable)
{
	ASSERT(!sVariable.empty());

	string sIndex = _InterpretVar(sVariable);

	VarMap::iterator iter = m_VarMap.find(sVariable);

	if (iter != m_VarMap.end())
	{
		if (iter->second->Remove(sIndex))
		{
			m_VarMap.erase(iter);
			g_Logger->logl("INFO","%s removed", sVariable.c_str());
		}
		else
		{
			g_Logger->logl("INFO","%s:%s removed", sVariable.c_str(), sIndex.c_str());
		}
		return true;
	}

	g_Logger->logl("ERROR","%s could not be removed - it doesn't exist.", sVariable.c_str());
	return false;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::_InterpretVar
//
string Variables::_InterpretVar(string& sVariable)
{
	string sReturn;

	size_t stIndex = sVariable.find(':');

	if (stIndex != string::npos && sVariable.length() > stIndex+1)
	{
		sReturn.assign(&sVariable.c_str()[stIndex+1]);
		sVariable.erase(stIndex, sVariable.length()-stIndex);
	}

	return sReturn;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::Expand
//
bool Variables::Expand(string& sString) const
{
	if (sString.empty())
		return false;

	//if the string is longer than 1 character
	//then it could have escape codes, so expand it
	if (sString.length() > 1)
		return _ExpandVarsWorker(sString, sString.length()-2); 
	//skip the last char since it wont be a valid escape code

	//otherwise, we are done
	return true;
}


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::ExpandVarsWorker
//
// Worker function for Expand (see above).
// This is probably rather slow since it uses std::basic_string functions
// instead of c-string manipulation, but it's a lot easier to maintain this way
// and most likely efficient enough for now.
//
bool Variables::_ExpandVarsWorker(string& sString, size_t stPosition = string::npos) const
{
	const char cEscape = '%';

	size_t stPrefix = sString.rfind(cEscape,stPosition);

	// this also catches empty strings
	if (stPrefix == string::npos)
	{
		// nothing to expand - done
		return true;
	}	

	//
	// actual expansion starts here
	//
	switch(sString.at(stPrefix+1))
	{
		//
		// variable/array
		//
	case '{':
		{
			size_t stPostfix = sString.find('}', stPrefix+2);

			if (stPostfix != string::npos)
			{
				// Now we know the position of the %{ and the closing }.
				// Construct a new string which holds the variable's name.
				string sVariable(sString, stPrefix+2, stPostfix-stPrefix-2);
				string sValue;
				
				//for %{?[condition] [replace_if_true] [replace_if_false]}
				if(*sVariable.c_str() == '?')
				{	
					//remove the ?
					sValue.assign(&sVariable.c_str()[1]);
					//this will evaluate the if and 
					//leave [replace_if_true] or [replace_if_false]
					EvalIf(sValue);
					//replace with the value and set stPosition to the end of the value
					sString.replace(stPrefix, stPostfix-stPrefix+1, sValue);
					stPosition = stPrefix + sValue.length();
				}
				else if (Get(sVariable, &sValue))
				{
					sString.replace(stPrefix, stPostfix-stPrefix+1, sValue);
					stPosition = stPrefix + sValue.length();
				}
				else
				{
					// replace with empty string if variable doesn't exist
					sString.erase(stPrefix, stPostfix-stPrefix+1);
				}

			}
			else
			{
				ErrorMessage("ERROR","Closing } not found. Expression: %s",
					sString.c_str());

				return false;
			}
		}
		break;

		//
		// escape codes
		//
	case '#':
		{
			sString.replace(stPrefix, 2, "$");
		}
		break;

	case '=':
		{
			sString.replace(stPrefix, 2, "\"");
		}
		break;

	case '-':
		{
			sString.replace(stPrefix, 2, "\'");
		}
		break;

	default:
		{
			//if we have reached the front, exit
			if(stPrefix==0)
				return true;
			//otherwise, set stPosition one to the left of stPrefix
			stPosition = stPrefix-1;
		}
		break;
	}

	// repeat as long as there could be more to expand
	return _ExpandVarsWorker(sString,stPosition);
}

bool Variables::VarDump(const std::string& sFile) const
{
	string sBuffer;

	ofstream file;
	file.open(sFile.c_str(), ios::app);

	if (file.is_open())
	{
		file << "[VarDump]" << endl
			<< "Name|Value|Separator|Count|Line|Line:Count|File" << endl << endl;
		for(VarMap::const_iterator iter = m_VarMap.begin(); iter!=m_VarMap.end(); ++iter)
		{
			ASSERT(iter->second);
			sBuffer.assign(iter->first);
			sBuffer.append("|");
			sBuffer.append(iter->second->VarDump());

			file << sBuffer << endl;
		}
		file << endl;
		file.close();
	}
	else
	{
		return false;
	}
	return true;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::toString
//

string Variables::toString(const std::string& sVariable) const
{
	assert(!sVariable.empty());
	string sResult;

	VarMap::const_iterator iter = m_VarMap.find(sVariable);

	if (iter != m_VarMap.end())
	{
		ASSERT(iter->second);
		sResult.assign("Variable \"");
		sResult.append(sVariable);
		sResult.append("\" exists.\n");

		sResult.append(iter->second->toString());
	}

	return sResult;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::ResetCurrent
//
void Variables::ResetCurrent()
{
	for(VarMap::const_iterator iter = m_VarMap.begin(); iter!=m_VarMap.end(); ++iter)
	{
		ASSERT(iter->second);

		iter->second->SetCurrent(false);
	}
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::_GetFileTokens
//
// Change sLine to hold everything after the name
// set sVariable to hold only the name
// set sValue to hold only the value (first token of sLine)
// returns false if there is no variable to save
bool Variables::_GetFileTokens(string& sLine, string& sVariable, string& sValue, string& sComment)
{
	if(sLine.empty())
		return false;
	
	size_t stComment;
	stComment = _FindComment(sLine);
	if(stComment < sLine.length())
	{
		sComment = sLine;
		sComment.erase(0, stComment);
		sLine.erase(stComment);
	}
//////////////////////////

	LPCSTR pszCurrent = sLine.c_str();
	LPCSTR pszStartMarker = NULL;
	bool bIsToken = false;
	
	pszCurrent += strspn(pszCurrent, WHITESPACE);
	for (; *pszCurrent; pszCurrent++)
	{
		if (isspace((unsigned char)*pszCurrent))
        {
            break;
        }

		if (!bIsToken)
		{
			bIsToken = true;
			pszStartMarker = pszCurrent;
		}
	}
	
	if (!pszStartMarker)
	{
		return false;
	}

	sVariable.assign(sLine, pszStartMarker - sLine.c_str(), pszCurrent - pszStartMarker);
	sLine.erase(0, pszCurrent - sLine.c_str());

	char szValue[MAX_LINE_LENGTH] = { 0 };
    if (GetToken(sLine.c_str(), szValue, NULL, true))
    {
        sValue.assign(szValue);
    }
	else
	{
		sValue.clear();
	}


//////////////////////////
	return true;
}

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Variables::_FindComment
//
size_t Variables::_FindComment(string& sLine)
{
	LPCSTR pszCurrent = sLine.c_str();
	int iBracketLevel = 0;
	CHAR cQuote = '\0';

		pszCurrent += strspn(pszCurrent, WHITESPACE);

		for (; *pszCurrent; pszCurrent++)
		{
			if (strchr(";", *pszCurrent) && !cQuote)
				break;

			if (strchr("[]", *pszCurrent) && (!strchr("\'\"", cQuote) || !cQuote))
			{
				if (*pszCurrent == '[')
				{
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
                        cQuote = 0;
					}
				}
			}

			if (strchr("\'\"", *pszCurrent) && (cQuote != '['))
			{
				if (!cQuote)
				{
					cQuote = *pszCurrent;
					continue;
				}
				else if (*pszCurrent == cQuote)
				{
					continue;
				}
			}
		}
	if(size_t(pszCurrent - sLine.c_str()) != sLine.length())
		return pszCurrent - sLine.c_str();
	else
		return string::npos;
}