#ifndef MZSCRIPT_COMMON_HPP_INCLUDED
#define MZSCRIPT_COMMON_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  common.hpp
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

#define ASSERT assert
#define ASSERT_ISSTRING(psz)     ASSERT(!IsBadStringPtr(psz, UINT_MAX))
#define ASSERT_ISREADPTR(p)      ASSERT(!IsBadReadPtr(p, sizeof(*p)))
#define ASSERT_ISWRITEPTR(p)     ASSERT(!IsBadWritePtr(p, sizeof(*p)))
#define ASSERT_ISWRITEDATA(a, l) ASSERT(!IsBadWritePtr(a, l))
#define ASSERT_ISREADDATA(a, l)  ASSERT(!IsBadReadPtr(a, l))
#include <assert.h>
// LS headers
#include <lsapi/lsapi.h>
#include "namedvalue.hpp"
//#include "debug.hpp"

// M$ headers
#include <windows.h>

// #pragma warning(push)
#pragma warning(disable: 4097 4710) // for warning level 4
#pragma warning(disable: 4702) // unreachable code - not reliable with MSVC6

// standard headers
#include <stdexcept>

// STL
#include <map>
#include <string>
#include <utility>
#include <vector>
#include <list>
#include <fstream>
#include <stack>


// boost.org
#include <boost/bind.hpp>
#include <boost/function.hpp>
#include <boost/optional.hpp>
#include <boost/shared_ptr.hpp>
#include <boost/utility.hpp>

// safe(r) string functions
// http://msdn.microsoft.com/library/en-us/dnsecure/html/strsafe.asp
#define STRSAFE_NO_DEPRECATE
#include <tchar.h>
#include <strsafe.h>
// #pragma warning(pop)

//
#include "logger.hpp"

#endif // !defined(MZSCRIPT_BANGS_HPP_INCLUDED)
