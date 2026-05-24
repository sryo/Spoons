#ifndef MZSCRIPT_BANGS_HPP_INCLUDED
#define MZSCRIPT_BANGS_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  bangs.hpp
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

using std::string;


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// typedef mzBangCommand
//
typedef void (*mzBangCommand)(const std::string& sArgs);


//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
// Function prototypes
//
void RegisterBangs();
void UnregisterBangs();

void BangThunk(HWND /* hCaller */, LPCSTR pszName, LPCSTR pszArgs);

void mzBangSetVar(const std::string& sArgs);
void mzBangAddVar(const std::string& sArgs);
void mzBangMulVar(const std::string& sArgs);
void mzBangShowVar(const std::string& sArgs);
void mzBangMsgBox(const std::string& sArgs);
void mzBangRemoveVar(const std::string& sArgs);
void mzBangRunVar(const std::string& sArgs);
void mzBangSaveVar(const std::string& sArgs);
void mzBangReplaceVar(const std::string& sArgs);
void mzBangSaveAllVars(const std::string& sArgs);
void mzBangIfExist(const std::string& sArgs);
void mzBangIf(const std::string& sArgs);
void mzBangExec(const std::string& sArgs);
void mzBangLoadVarFile(const std::string& sArgs);
void mzBangLoadScript(const std::string& sArgs);
void mzBangRemoveScript(const std::string& sArgs);
void mzBangPause(const std::string& sArgs);
void mzBangVarDump(const std::string& sArgs);
void mzBangModVar(const std::string& sArgs);
void mzBangRndVar(const std::string& sArgs);
void mzBangIntVar(const std::string& sArgs);


#endif // !defined(MZSCRIPT_BANGS_HPP_INCLUDED)
