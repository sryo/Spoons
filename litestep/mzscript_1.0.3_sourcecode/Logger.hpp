#ifndef MZSCRIPT_Logger_HPP_INCLUDED
#define MZSCRIPT_Logger_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  Logger.hpp
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
#include <ctime>

class Logger : public boost::noncopyable
{
public:
    typedef boost::shared_ptr<Logger> LogPtr;
    
    explicit Logger(){}
    ~Logger(){fout.close();}

	void logl(LPCSTR pszType, LPCSTR pszFormat, ...);

	bool open(const std::string& sFile);

	bool close();
    
private:
	std::ofstream fout;
};


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// "exports"
//
extern Logger::LogPtr g_Logger;


#endif // !defined(MZSCRIPT_Logger_HPP_INCLUDED)
