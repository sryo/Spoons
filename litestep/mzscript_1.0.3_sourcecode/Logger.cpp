//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  Logger.cpp
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
#include "logger.hpp"
#include <string>
using std::ofstream;
using std::endl;
using std::ios;
using std::string;

Logger::LogPtr g_Logger(new Logger());

extern char szLogFile[MAX_LINE_LENGTH];
extern int LogLevel;
extern bool LogOpened;

void Logger::logl(LPCSTR pszType, LPCSTR pszFormat, ...)
{
	char  szType[MAX_LINE_LENGTH] = { 0 };
	char  szMessage[MAX_LINE_LENGTH] = { 0 };
	va_list argList;

	va_start(argList, pszFormat, pszType); // added pszType?
	StringCchVPrintf(szMessage, MAX_LINE_LENGTH, pszFormat, argList);
	StringCchVPrintf(szType, MAX_LINE_LENGTH, pszType, argList);

	va_end(argList);

	// create variable to control whether or not log event should be written.
	// will set to 0 if logging should not be performed.
	// mzscript.cpp now does the validation against log levels so we should not
	// need to worry about this here. The only concern is direct calls to logl
	// and this has not been checked (yet). Since the module is the only user of
	// this code, only the source in this project needs to be checked.
	 
	bool writeToLog = 1;

	/* Log if :
		Level = 1 && szType == ERROR
		Level = 2 && szType == ERROR || szType == WARN
		Level = 3 && szType == ERROR || szType == WARN || szType == INFO
	*/

// Casting to strings is quick and dirty in source code, but a better way may follow
		if ((string)szType == "INFO")
		{
			if (LogLevel != 3) {
				writeToLog = 0;
			}
		}

		if ((string)szType == "WARN")
		{
			if (LogLevel <= 1)
				writeToLog = 0;
		}

		if ((string)szType == "ERROR")
		{
			// always log errors :) LogLevel 0 handled in mzscript.cpp
		}
/*
	if (szType[1] == 'I')
		MessageBox(NULL, "INFO: detected!", "mzscript debug", MB_ICONEXCLAMATION | MB_TOPMOST | MB_SETFOREGROUND);
	if (szType[4] == ':') {
		if (szType[0] == 'I' && LogLevel != 3)
			writeToLog = 0;
		if (szType[0] == 'W' && LogLevel <= 1)
			writeToLog = 0;
	}
	if (szType[5] == ':' && szType[0] == 'E') {}
			// always log errors - LogLevel == 0 is handled in mzscript.cpp
*/
	if (writeToLog == 1)
	{
		Logger::open(szLogFile);
    	//format timestamp: "[hh:mm:ss] "
		time_t seconds = time(NULL);
		char* pszTime = ctime(&seconds);
		pszTime += 10;
		pszTime[0] = '[';
		strcpy(pszTime+9,"] ");
	    
		fout << pszTime << szType << ":\t" << szMessage << endl;
		Logger::close();
	}
}

bool Logger::open(const std::string& sFile)
{
	fout.open(sFile.c_str(), ios::app);
	if (fout.is_open())
	{
		if (LogOpened != TRUE) {
			time_t seconds = time(NULL);
			char* pszTime = ctime(&seconds);
			pszTime[24] = '\0';
			fout << "<MZScript log opened " << pszTime << ">" << endl;
			LogOpened = TRUE;
			g_Logger->close();
		}
		return true;
	}
	else
	{
		return false;
	}
}

bool Logger::close()
{
	if (fout.is_open())
	{
		fout.close();
		if (fout.is_open()) {
			return false;
		} else {
			return true;
		}
	}
	else {
		return true; // inserted to cover all possibilities
	}
}