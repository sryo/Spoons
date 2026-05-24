//=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//
//  common.hpp
//  This is a part of the alias source code.
//
//  Copyright (C) 2004-2008 ilmcuts
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
#ifndef ALIAS_COMMON_HPP_INCLUDED
#define ALIAS_COMMON_HPP_INCLUDED

#if _MSC_VER > 1020
#  pragma once
#endif // _MSC_VER

#include "AggressiveOptimize.h"

// LS headers
#include "../litestep/lsapi/lsapi.h"

// M$ headers
#include <windows.h>

#pragma warning(push)
#pragma warning(disable: 4097 4710) // for warning level 4
#pragma warning(disable: 4702) // unreachable code - not reliable with MSVC6

// STL
#include <algorithm>
#include <map>
#include <string>
#include <utility>
#include <vector>

// safe(r) string functions
// http://msdn.microsoft.com/library/en-us/dnsecure/html/strsafe.asp
#define STRSAFE_NO_DEPRECATE
#include <strsafe.h>
#pragma warning(pop)


#endif // !defined(ALIAS_COMMON_HPP_INCLUDED)
