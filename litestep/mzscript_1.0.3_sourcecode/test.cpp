#include <stack>

using std::stack;

bool Variables::_SaveWorker(const std::string& sVariable, const std::string& sLine, const std::string& sFile) const
{
	//if there is no file, then it is internal and doesn't need to be saved
	if(sFile.empty() || sLine.empty())
		return true;

	char szBuffer[MAX_LINE_LENGTH] = { 0 };
	bool bFound = false;
	bool bChanged = false;
	EvalParser evalParser;
	stack<bool> IfStack;


	ifstream file;
	file.open(sFile.c_str());
	if (file.is_open())
	{
		list<string> l;
		string s, f_sLine, f_sVariable, f_sValue;

		while (!file.eof() && ((bFound && bChanged) || !bFound))
		{
			file.getline(szBuffer, MAX_LINE_LENGTH);
			if(!bFound)
			{
				f_sLine.assign(szBuffer);
				_GetFileTokens(f_sLine, f_sVariable, f_sValue);

				if(StrIEqual(f_sVariable,"if"))
				{
					int* npEval;
					evalParser.evaluate(f_sLine.c_str(), npEval)
					IfStack.push(bool(*npEval));
					continue;
				}
				if(StrIEqual(f_sVariable,"else"))
				{
					if(!IfStack.empty())
					{
						bool bTemp = IfStack.top();
						IfStack.pop()l
						IfStack.push(!bTemp);
					}
					continue;
				}
				if(StrIEqual(f_sVariable,"endif"))
				{
					IfStack.pop();
					continue;
				}

				if(IfStack.top() && StrIEqual(sVariable,f_sVariable))
				{
					bFound = true;
					if(sLine.compare(f_sLine) != 0)
					{
						s.assign(szBuffer);
						size_t stLinePos = s.find(f_sVariable);

						ASSERT(stLinePos != string::npos);

						s.erase(stLinePos);
						s.append(f_sVariable);
						if(!strchr(" \t", sLine.c_str()[0]))
							s.append(" ");
						s.append(sLine);

						l.push_back(s);
						bChanged = true;
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
				g_Logger->logl("ERROR","Could not open \"%s\" for writing.",
						pszFile ? pszFile : "step.rc");
				return false;
			}
			g_Logger->logl("INFO","%s saved as line \"%s\" in \"%s\"", sVariable.c_str(), sLine.c_str(), sFile.c_str());
		}
		else if(bFound)
		{
			return true;
		}
		else
		{
			g_Logger->logl("ERROR","Variable %s could not be saved.\n\t\tIt was not found in \"%s\".\n\t\tThe file may have been altered.", sVariable.c_str(), sFile.c_str());
			return false;
		}
	}
	else
	{
		return false;
	}

	return true;
}