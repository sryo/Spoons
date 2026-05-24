/*
  NetLoadModule LiteStep Module - version 2.5.0

  Copyright (C) 2002 - 2005 Joshua Seagoe
 
  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.
 
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
 
  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

#include "NetLoadModule.h"

/*
				GetAlias
*/
bool GetAlias(const _TCHAR *name,_TCHAR *buffer,size_t bufferLen)
{
	_TCHAR file[NLM_PATH_LENGTH];
	_TCHAR var[NLM_PATH_LENGTH];

	/* can't really check length of buffer   */ 
	/* because VarExpansion doesn't allow it */ 
  /* TODO: Switch to VarExpansionEx in .24.7 */ 
	ASSERTR(bufferLen>=NLM_PATH_LENGTH,false);

	if (0 != GetPrivateProfileString(
		ALIAS_FILE_SECTION,name,"",var,NLM_PATH_LENGTH,GlobalData.AliasFile))
	{
		VarExpansion(buffer,var);
		/* if it doesn't already have a path, add it */ 
		if ( _tcschr(buffer,_T(':'))==NULL
			&& _tcschr(buffer,_T('\\'))==NULL
			&& _tcschr(buffer,_T('/'))==NULL)
		{
			_TCHAR *ptr = _tcsrchr(buffer,_T('.'));

			if (GlobalData.ModulePathLen+_tcslen(buffer)+MODULE_EXT_LEN >= NLM_PATH_LENGTH)
				return false;

			/* what was I going to say here?                */ 
			_tcscpy(file,GlobalData.ModulePath);
			_tcscpy(file+GlobalData.ModulePathLen,buffer);
			/* only add extension if it's not already there */ 
			if (_tcsicmp(ptr,MODULE_EXT)!=0)
				_tcscat(file+GlobalData.ModulePathLen,MODULE_EXT);
			/* put it back in the output buffer             */ 
			_tcscpy(buffer,file);
		}
		return true;
	}
	return false;
}

bool RemoveAlias(const _TCHAR *modulename)
{
	return 
		(FALSE !=
			WritePrivateProfileString(
				ALIAS_FILE_SECTION,modulename,NULL,GlobalData.AliasFile)
		);
}

// find optimal $var$ path and write an alias to the global alias file
bool AddAlias(const _TCHAR *modulename,const _TCHAR *modulepath)
{
	_TCHAR path[NLM_PATH_LENGTH];

#if (0)
/*  This section is to compress any aliases that are dlls in the NetLoadModulePath
    directory.  That is, a simple name could be used, and the standard method of
		building up a module path from its name would work.

		Originally, this was to allow a module to be renamed more easily, so that the
		alternate name could be used also to form the name of the archive.  Since
		GetAlias doesn't return it that way, this isn't all that useful, and I'm not
		entirely sure it was a good idea in the first place.
*/

	/* see if it's in the module directory */ 
	{
		_TCHAR name[MAX_PATH_LENGTH];
		int len;
		/* strip it down to just the name */ 
		GetRawModuleName(name,modulepath);
		len = _tcslen(name);

		if (GlobalData.ModulePathLen+len+MODULE_EXT_LEN < NLM_PATH_LENGTH)
		{
			/* if it won't fit in the buffer, it definitely won't match */ 
			/* (paths are limited to much shorter anyway,               */ 
			/*  so this shouldn't be an issue)                          */ 

			/* now build back to a full path */ 
			_tcscpy(path,GlobalData.ModulePath);
			_tcscpy(path+GlobalData.ModulePathLen,name);
			_tcscpy(path+GlobalData.ModulePathLen+len,MODULE_EXT);
			/* check if it's the same        */ 
			if (_tcsicmp(path,modulepath)==0)
			{
				/* use just the name as the alias */ 
				return (FALSE!=WritePrivateProfileString(ALIAS_FILE_SECTION,modulename,name,file));
			}
		}
	}
#endif /* (0) */ 

  /* try to replace $NetLoadModulePath$ */ 
/* Ah, but what if they use the default?
	if (_tcsncicmp(GlobalData.ModulePath, modulepath, GlobalData.ModulePathLen)==0)
	{
		_tcscpy(path, PATH_CONF_MODULEDIR);
		_tcscpy(path+PATH_CONF_MODULEDIR_LEN, modulepath+GlobalData.ModulePathLen);
	}
	else
*/
	/* try to replace the litestep dir with a $var$ */ 
	if (_tcsncicmp(GlobalData.LiteStepPath,modulepath,GlobalData.LiteStepPathLen)==0)
	{
		_tcscpy(path, PATH_LITESTEPDIR);
		_tcscpy(path+PATH_LITESTEPDIR_LEN, modulepath+GlobalData.LiteStepPathLen);
	}
	else
	{
		_tcscpy(path, modulepath);
	}

	return 
		(FALSE !=
			WritePrivateProfileString(
				ALIAS_FILE_SECTION,modulename,path,GlobalData.AliasFile)
		);
}
