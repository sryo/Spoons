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
#include "IBindStatusCallback.h"
#include <zlib/zlib.h>
#include "unzip/unzip.h"

//			DownloadModule, ExtractFile, InstallModule



/*

  Safe delayload for URLMON, so NLM doesn't load all those extra DLLs unless they're needed.

*/
static HRESULT (STDAPICALLTYPE *pURLDownloadToCacheFile)(LPUNKNOWN,LPCTSTR,LPTSTR,DWORD,DWORD,LPBINDSTATUSCALLBACK) = NULL;
static HMODULE hURLMON = NULL;

void LoadDownloadProcs(void)
{
  if (pURLDownloadToCacheFile)
    return;

  hURLMON = LoadLibrary("URLMON.DLL");

  if (hURLMON)
  {
#ifdef UNICODE
    pURLDownloadToCacheFile = (HRESULT (STDAPICALLTYPE *)(LPUNKNOWN,LPCTSTR,LPTSTR,DWORD,DWORD,LPBINDSTATUSCALLBACK))
      GetProcAddress(hURLMON, _T("URLDownloadToCacheFileW"));
#else
    pURLDownloadToCacheFile = (HRESULT (STDAPICALLTYPE *)(LPUNKNOWN,LPCTSTR,LPTSTR,DWORD,DWORD,LPBINDSTATUSCALLBACK))
      GetProcAddress(hURLMON, _T("URLDownloadToCacheFileA"));
#endif
  }

  if (!pURLDownloadToCacheFile)
  {
    _TCHAR message[NLM_PATH_LENGTH];
    LoadString(GlobalData.hInstance, IDS_ERROR_URLMON, message, NLM_PATH_LENGTH);
    MessageBox(GlobalData.hMainDlg, message, TITLE, ERROR_MESSAGE_FLAGS);
    UnloadDownloadProcs();
  }
}

void UnloadDownloadProcs(void)
{
  pURLDownloadToCacheFile = NULL;
  if (hURLMON) FreeLibrary(hURLMON);
}

/*

          DownloadModule

*/
bool DownloadModule(s_Module *pMod, _TCHAR *tempfilename, size_t tfnmaxlen)
{
	_TCHAR url[NLM_PATH_LENGTH];
	const _TCHAR *ptr;
	s_Site *pSite;
	int i;
  bool bFoundBadCopy = false;
  bool bSkippedDownload = false;

	ASSERT(pMod!=NULL);
	ASSERT(tempfilename!=NULL);

	/* see if it's in the zip directory */ 
	if (GlobalData.ZipPath && 
		(GlobalData.ZipPathLen+pMod->NameLen+ARCHIVE_EXT_LEN)<NLM_PATH_LENGTH)
	{
		_tcscpy(url, GlobalData.ZipPath);
		_tcscpy(url+GlobalData.ZipPathLen, pMod->Name);
		_tcscpy(url+GlobalData.ZipPathLen+pMod->NameLen, ARCHIVE_EXT);
		if (GetFileAttributes(url)!=INVALID_FILE_ATTRIBUTES
			&& _tcslen(url)<tfnmaxlen)
		{
			/* use local copy               */ 
			_tcscpy(tempfilename,url);
			TRACE("Found local copy:");
			TRACE(url);
			return true;
		}
  }

  /* load URLMON.DLL if we haven't already */ 
  if (!pURLDownloadToCacheFile)
    LoadDownloadProcs();

	/* now try each archive site        */ 
	pSite = GlobalData.pNextSite;
  /* note: the conditions in these should be flipped to simplify the */ 
  /* code but I don't want to risk breaking anything right now.      */ 
	for (i=GlobalData.nSites;i>0;--i)
	{
		/* wrap back around if we reach the end */ 
		if (pSite==NULL) pSite=GlobalData.pSites;

		ASSERT(pSite->Prefix!=NULL);
		ASSERT(pSite->Suffix!=NULL);

		/* skip if it won't fit in the buffer   */ 
		if (pSite->PrefixLen+pMod->NameLen+pSite->SuffixLen < NLM_PATH_LENGTH)
		{
      /* ignore foreign addresses if we only want local stuff */ 
      if (!GlobalData.bNoDownloadStep || _tcsnicmp(pSite->Prefix, _T("file://"), 7)==0)
      {
			  /* form the address                   */ 
			  _tcscpy(url, pSite->Prefix);
			  _tcscpy(url+pSite->PrefixLen, pMod->Name);
			  _tcscpy(url+pSite->PrefixLen+pMod->NameLen, pSite->Suffix);
			  /* try it                             */ 
			  if (pURLDownloadToCacheFile(NULL, url, tempfilename, (DWORD)tfnmaxlen, 0, &NLMStatusCallback)==S_OK)
			  {
          /* check for loose-screws */ 
          WIN32_FIND_DATA fd = { 0 };
          /* not using GetFileSize, because that needs a handle and we have a name */ 
          FindClose(FindFirstFile(tempfilename, &fd));
          if (fd.nFileSizeLow != 0 || fd.nFileSizeHigh != 0)
          {
            /* make sure the file is good       */ 
            unzFile zipfile = NULL;
#ifndef NLM_IGNORE_EXCEPTIONS
#ifdef _MSC_VER
            __try
#else
            try
#endif
#endif
            {
              zipfile = unzOpen(tempfilename);
            }
#ifndef NLM_IGNORE_EXCEPTIONS
#ifdef _MSC_VER
            __except (EXCEPTION_EXECUTE_HANDLER)
#else
            catch (...)
#endif
            {
              /* error in zlib -- let's just say it didn't work. */ 
            }
#endif
            if (zipfile != NULL)
            {
              unzClose(zipfile);
			  	    /* this site worked, next time      */ 
				      /* start trying here                */ 
				      GlobalData.pNextSite = pSite;
				      TRACE("Download from site OK:");
				      TRACE(url);
				      return true;
            }
            TRACE("Download succeeded, but file was bad.");
				    TRACE(url);
            bFoundBadCopy = true;
          }
          else
          {
  				  TRACE("Download returned empty file:");
	  			  TRACE(url);
          }
			  }
			  else
			  {
				  TRACE("Download from site failed:");
				  TRACE(url);
			  }
      }
      else
      {
        TRACE("No download step.");
			  TRACE(pSite->Prefix);
        bSkippedDownload = true;
      }
		}
		else
		{
			TRACE("Site too long:");
			TRACE(pSite->Prefix);
		}

		pSite = pSite->pNext;
	}

  /* -> after using archives 2003-09-03          */ 
  /* Primary sites are likely to be the author's */ 
  /* site, which may not want all the traffic.   */ 
  /* This also reduces a security risk, in that  */ 
  /* a theme can't supply a fake version of a    */ 
  /* legit module.                               */ 

	/* try all primary sites in order   */ 
	ptr = pMod->PrimarySite;
	while (GetToken(ptr,url,&ptr,FALSE)==TRUE)
	{
    /* ignore foreign addresses if we only want local stuff */ 
    if (!GlobalData.bNoDownloadStep || _tcsnicmp(url, _T("file://"), 7)==0)
    {
		  /* quit if any succeeds                 */ 
		  if (pURLDownloadToCacheFile(NULL, url, tempfilename, (DWORD)tfnmaxlen, 0, &NLMStatusCallback)==S_OK)
		  {
        /* make sure the file is good       */ 
        unzFile zipfile;
        zipfile = unzOpen(tempfilename);
        if (zipfile != NULL)
        {
          unzClose(zipfile);
			    TRACE("Download from primary OK:");
				  TRACE(url);
				  return true;
        }
        TRACE("Download from primary succeeded, but file was bad.");
			  TRACE(url);
        bFoundBadCopy = true;
		  }
		  else
		  {
			  TRACE("Download from primary failed:");
			  TRACE(url);
		  }
    }
    else
    {
      TRACE("No download step.");
      TRACE(url);
      bSkippedDownload = true;
    }
	}

	/* unable to download module        */ 
  UINT uError = IDS_ERROR_CANT_DOWNLOAD;
  if (bSkippedDownload)
    uError = IDS_ERROR_NO_DOWNLOAD_STEP;
  if (bFoundBadCopy)
    uError = IDS_ERROR_NO_GOOD_DOWNLOAD;
  SetModuleError(pMod, uError);

	return false;
}


#define FILE_MODULE     0
#define FILE_DOC        1
#define FILE_HTML       2
#define FILE_NLMI       3
#define FILE_TYPE_COUNT 4



/*
	      ExtractFile
*/
void ExtractFile(unzFile zip,const _TCHAR *file,DWORD size)
{
	void *data = new NLM_NOTHROW BYTE[size];
#ifdef NLM_IGNORE_EXCEPTIONS
  if (!data)
    return;
#endif
	HANDLE hFile;
	DWORD ignored;
	/* extract it       */ 
	unzOpenCurrentFile(zip);
	unzReadCurrentFile(zip,data,size);
	unzCloseCurrentFile(zip);
	/* write it to disk */ 
	hFile = CreateFile(file,
		GENERIC_WRITE,0,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_ARCHIVE,NULL);
	/* as documented, CREATE_ALWAYS + FILE_ATTRIBUTE_NORMAL fails, but */ 
	/* I have no idea why.  Archive is always set anyway, so use that. */ 
	WriteFile(hFile,data,size,&ignored,NULL);
	CloseHandle(hFile);
	/* free memory      */ 
	delete[] data;
}

/*
	      InstallModule

 pMod -> Module structure
 Archive -> temporary file name

	this doesn't check for buffer overflows as often as other bits

  This function is too huge; it really wants to be a nice functor class.
*/
bool InstallModule(HWND hDlg,s_Module *pMod,const _TCHAR *Archive)
{
	_TCHAR filename[NLM_PATH_LENGTH];
	_TCHAR extname[NLM_PATH_LENGTH];
	_TCHAR doc[NLM_PATH_LENGTH];
	_TCHAR *filetype,*nopathname,*nopathname2;
	int Files[FILE_TYPE_COUNT]; bool bHasHTML;
	unzFile zipfile;
	unz_file_info info;
  bool bFoundLoadFile = false;

	_TCHAR *dlllist = NULL; /* list of dll files, separated by '|'s */ 
	size_t dlllistlen = 0;
	_TCHAR *temp;

#ifndef NLM_IGNORE_EXCEPTIONS
#ifdef _MSC_VER
  __try
#else
  try
#endif
#endif
  {
	  ZeroMemory(Files,sizeof(Files));
	  bHasHTML = false;
	  zipfile = unzOpen(Archive);
	  if (zipfile==NULL)
    {
      /* This should never happen because we tried in DownloadModule  */ 
      /* but maybe somebody's messing with us and it doesn't work now */ 
      TRACE("Couldn't open archive.");
      TRACE(Archive);
      SetModuleError(pMod, IDS_ERROR_CANT_OPEN_ARCHIVE);
      return false; /* couldn't open downloaded file */ 
    }

  /*
			  first pass through zip file: count file types
  */
	  unzGoToFirstFile(zipfile);
	  while (UNZ_OK==unzGetCurrentFileInfo(zipfile,
		  &info,filename,NLM_PATH_LENGTH,NULL,0,NULL,0))
	  {
		  /* check file type */ 
		  filetype = _tcsrchr(filename,_T('.'));
		  if (filetype)
		  {
			  if (_tcsicmp(filetype,MODULE_EXT)==0)
			  {
				  ++Files[FILE_MODULE];
				  /* add it to the list of dll files */ 
				  temp = new NLM_NOTHROW _TCHAR[_tcslen(filename)+1+dlllistlen];
#ifdef NLM_IGNORE_EXCEPTIONS
          if (!temp)
          {
            delete[] dlllist;
            unzClose(zipfile);
            return false;
          }
#endif
				  *temp = 0;
				  if (dlllist!=NULL)
				  {
					  CopyMemory(temp,dlllist,dlllistlen);
					  delete[] dlllist;
					  _tcscat(temp,_T("|"));
				  }
				  _tcscat(temp,filename);
				  dlllistlen += 1+_tcslen(filename);
				  dlllist = temp;

          if (pMod->sLoadFile && _tcsicmp(filename, pMod->sLoadFile)==0)
            bFoundLoadFile = true;
			  }
			  else if (_tcsicmp(filetype,_T(".txt"))==0 || _tcsicmp(filetype,_T(".chm"))==0)
			  {
				  ++Files[FILE_DOC];
			  }
			  else if (_tcsicmp(filetype,_T(".html"))==0 || _tcsicmp(filetype,_T(".htm"))==0
          || _tcsicmp(filetype,_T(".xml"))==0 || _tcsicmp(filetype,_T(".lsmd"))==0)
			  {
				  ++Files[FILE_DOC];
				  bHasHTML = true;
			  }
			  else if (_tcsicmp(filetype,_T(".gif"))==0 || _tcsicmp(filetype,_T(".jpg"))==0
				  || _tcsicmp(filetype,_T(".png"))==0 || _tcsicmp(filetype,_T(".css"))==0
          || _tcsicmp(filetype,_T(".xsl"))==0)
			  {
				  /* file potentially included by html */ 
				  /* need to extract all of these,     */ 
				  /* but only if there's an html       */ 
				  ++Files[FILE_HTML];
			  }
        else if (_tcsicmp(filetype,_T(".nlmi"))==0)
        {
          /* (currently unimplemented) install script */ 
          ++Files[FILE_NLMI];
        }
		  }
		  /* always remember this bit */ 
		  if (unzGoToNextFile(zipfile)==UNZ_END_OF_LIST_OF_FILE) break;
	  }

	  /* fail if there is no module in this archive */ 
	  if (Files[FILE_MODULE]<1)
	  {
		  const _TCHAR *args[4];
		  args[0] = Archive;
		  args[1] = pMod->OrigName;
		  if (args[1]==NULL) args[1] = pMod->Name;
		  FormatMessage(
			  FORMAT_MESSAGE_FROM_HMODULE|FORMAT_MESSAGE_ARGUMENT_ARRAY,
			  GlobalData.hInstance, NLM_MESSAGE_MULTIPLE, 0,
			  filename, NLM_PATH_LENGTH,
			  (va_list *)args);
		  /* let the user know             */ 
		  MessageBox(NULL,filename,TITLE,ERROR_MESSAGE_FLAGS);
      ASSERT(dlllist==NULL);
      delete[] dlllist; /* does nothing */ 
		  unzClose(zipfile);

      TRACE("No modules in archive.");
      SetModuleError(pMod, IDS_ERROR_NO_MODULES_IN_ARCHIVE);
		  return false;
	  }

    /* we are still saving the zip to the zip path, so we */ 
    /* had to make sure it was somewhat valid, now skip   */ 
    /* the actual extract/install step                    */ 
    if (GlobalData.bNoInstallStep)
    {
      TRACE("Not installing: no install step");
      SetModuleError(pMod, IDS_ERROR_NO_INSTALL_STEP);
    }
    else
    {
    /*
		    second pass through zip file: extract documentation
		    (so it will be there for the multiple dll dialog)
    */
	    if (Files[FILE_DOC]>0 && GlobalData.DocPath!=NULL)
	    {

		    /* build doc path name           */ 
		    _tcscpy(extname,GlobalData.DocPath);
		    _tcscpy(extname+GlobalData.DocPathLen,pMod->Name);

		    unzGoToFirstFile(zipfile);

		    if (GlobalData.bAlwaysUseFolders ||
          Files[FILE_DOC]>1 || (bHasHTML && Files[FILE_HTML]>0))
		    {
			    /* need to create a folder & extract multiple items */ 
			    CreateDirectory(extname,NULL);
			    *(extname+GlobalData.DocPathLen+pMod->NameLen) = _T('\\');

			    while (UNZ_OK==unzGetCurrentFileInfo(zipfile,
				    &info,filename,NLM_PATH_LENGTH,NULL,0,NULL,0))
			    {
				    /* Collapse path in zip file.        */ 
				    /* This may pose a problem if there  */ 
				    /* are duplicates, but saves us from */ 
				    /* having to worry about creating    */ 
				    /* every directory along the way.    */ 
				    nopathname = _tcsrchr(filename,_T('\\'));
				    nopathname2 = _tcsrchr(filename,_T('/'));
				    if (nopathname2>nopathname) nopathname = nopathname2;
				    if (nopathname==NULL) nopathname = filename;

				    /* check file type                   */ 
				    filetype = _tcsrchr(filename,_T('.'));
				    if (filetype)
				    {
					    if (_tcsicmp(filetype,_T(".txt"))==0 || _tcsicmp(filetype,_T(".chm"))==0)
					    {
						    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen+1,nopathname);
						    ExtractFile(zipfile,extname,info.uncompressed_size);
					    }
					    else if (bHasHTML)
					    {
			          if (_tcsicmp(filetype,_T(".html"))==0 || _tcsicmp(filetype,_T(".htm"))==0
                  || _tcsicmp(filetype,_T(".xml"))==0 || _tcsicmp(filetype,_T(".lsmd"))==0)
						    {
							    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen+1,nopathname);
							    _tcscpy(doc,extname);
							    ExtractFile(zipfile,extname,info.uncompressed_size);
						    }
						    else if (_tcsicmp(filetype,_T(".gif"))==0 || _tcsicmp(filetype,_T(".jpg"))==0
				          || _tcsicmp(filetype,_T(".png"))==0 || _tcsicmp(filetype,_T(".css"))==0
                  || _tcsicmp(filetype,_T(".xsl"))==0)
						    {
							    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen+1,nopathname);
							    ExtractFile(zipfile,extname,info.uncompressed_size);
						    }
					    }
				    }
				    if (unzGoToNextFile(zipfile)==UNZ_END_OF_LIST_OF_FILE) break;
			    }
			    /* now set extname to something appropriate for view docs */ 
			    if (bHasHTML) _tcscpy(extname,doc);
		    }
		    else
		    {
			    /* extract one item, flat */ 
			    while (UNZ_OK==unzGetCurrentFileInfo(zipfile,
				    &info,filename,NLM_PATH_LENGTH,NULL,0,NULL,0))
			    {
				    /* check file type      */ 
				    filetype = _tcsrchr(filename,_T('.'));
				    if (filetype)
				    {
					    if (_tcsicmp(filetype,_T(".txt"))==0)
					    {
						    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen,_T(".txt"));
						    ExtractFile(zipfile,extname,info.uncompressed_size);
					    }
					    else if (_tcsicmp(filetype,_T(".html"))==0 || _tcsicmp(filetype,_T(".htm"))==0)
					    {
						    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen,_T(".html"));
						    ExtractFile(zipfile,extname,info.uncompressed_size);
					    }
              else if (_tcsicmp(filetype,_T(".xml"))==0)
					    {
						    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen,_T(".xml"));
						    ExtractFile(zipfile,extname,info.uncompressed_size);
					    }
              else if (_tcsicmp(filetype,_T(".lsmd"))==0)
					    {
						    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen,_T(".lsmd"));
						    ExtractFile(zipfile,extname,info.uncompressed_size);
					    }
              else if (_tcsicmp(filetype,_T(".chm"))==0)
					    {
						    _tcscpy(extname+GlobalData.DocPathLen+pMod->NameLen,_T(".chm"));
						    ExtractFile(zipfile,extname,info.uncompressed_size);
					    }
				    }
				    if (unzGoToNextFile(zipfile)==UNZ_END_OF_LIST_OF_FILE) break;
			    }
		    }
      } /* extract documentation */ 

	    /* complain if there are multiple DLLs */ 
	    s_Archive arc;
	    arc.bCreateDllFolder = GlobalData.bAlwaysUseFolders;
	    arc.DllNames = dlllist;
      if (bFoundLoadFile)
      {
        _tcscpy(dlllist, pMod->sLoadFile);
        /* always create a folder if "load nnn.dll" is specified */ 
        arc.bCreateDllFolder = true;
      }
      else if (Files[FILE_MODULE]>1)
	    {
		    arc.pModule = pMod;
		    arc.pName = Archive;
		    arc.bHasDocs = Files[FILE_DOC]>0;
		    arc.nDlls = Files[FILE_MODULE];
		    arc.pDocPath = extname;

		    if (IDCANCEL ==
			    DialogBoxParam(
				    GlobalData.hInstance,
				    MAKEINTRESOURCE(IDD_MULTIPLE_DLL),
				    hDlg,
				    MultiDllDlgProc,
            reinterpret_cast<LPARAM>(&arc)))
		    {
          delete[] dlllist;
			    unzClose(zipfile);
          TRACE("Multiple DLLs: user cancelled.");
          SetModuleError(pMod, IDS_ERROR_MULTIPLE_CANCELLED);
			    return false;
		    }
	    }

    /*
			    third pass through zip file: extract module
    */

	    /* build module path name */ 
	    _tcscpy(extname,GlobalData.ModulePath);
	    _tcscpy(extname+GlobalData.ModulePathLen, pMod->Name);

	    if (arc.bCreateDllFolder)
	    {
		    CreateDirectory(extname,NULL);
		    *(extname+GlobalData.ModulePathLen+pMod->NameLen) = _T('\\');
	    }

	    unzGoToFirstFile(zipfile);
	    while (UNZ_OK == unzGetCurrentFileInfo(zipfile,
		    &info,filename, NLM_PATH_LENGTH, NULL, 0, NULL, 0))
	    {
		    if (arc.bCreateDllFolder)
		    {
			    /* Collapse path in zip file.        */ 
			    /* This may pose a problem if there  */ 
			    /* are duplicates, but saves us from */ 
			    /* having to worry about creating    */ 
			    /* every directory along the way.    */ 
			    nopathname = _tcsrchr(filename,_T('\\'));
			    nopathname2 = _tcsrchr(filename,_T('/'));
			    if (nopathname2>nopathname) nopathname = nopathname2;
			    if (nopathname==NULL) nopathname = filename;

			    /* extract it if it's a dll          */ 
			    filetype = _tcsrchr(filename,_T('.'));
			    if (filetype && _tcsicmp(filetype,MODULE_EXT)==0)
			    {
				    _tcscpy(extname+GlobalData.ModulePathLen+pMod->NameLen+1, nopathname);
				    ExtractFile(zipfile,extname, info.uncompressed_size);
			    }
		    }
		    else
		    {
			    /* is it the one dll we want? */ 
			    if (_tcsicmp(filename,dlllist)==0)
			    {
				    _tcscpy(extname+GlobalData.ModulePathLen+pMod->NameLen, MODULE_EXT);
				    ExtractFile(zipfile,extname, info.uncompressed_size);
			    }
		    }
		    if (unzGoToNextFile(zipfile) == UNZ_END_OF_LIST_OF_FILE) break;
	    }

	    /* get the path to the one that    */ 
	    /* needs loading and set the alias */ 
	    if (arc.bCreateDllFolder)
	    {
		    nopathname = _tcsrchr(arc.DllNames,_T('\\'))+1;
		    nopathname2 = _tcsrchr(arc.DllNames,_T('/'))+1;
		    if (nopathname2>nopathname) nopathname = nopathname2;
		    if (nopathname-1==NULL) nopathname = arc.DllNames;

        _tcscpy(extname+GlobalData.ModulePathLen+pMod->NameLen+1, nopathname);
		    /* save to alias list           */ 
		    AddAlias(pMod->Name, extname);
	    }
	    else
	    {
		    /* if we install it in the right place,  */ 
		    /* don't let an alias tell you otherwise */ 
		    RemoveAlias(pMod->Name);
        bool bItBetterNotHaveAnAlias;
        GetModulePath(pMod->Name, pMod->NameLen, extname, NLM_PATH_LENGTH, bItBetterNotHaveAnAlias);
        ASSERT(bItBetterNotHaveAnAlias == false);
	    }

      /* make sure it's using the most recent path */ 
      if (_tcscmp(extname, pMod->DllPath)!=0)
      {
        /* TODO: make sure this succeeds */ 
        ReplaceWithDup(pMod->DllPath, extname);
      }
    } /* (GlobalData.bNoInstallStep) */ 

	  /* save the zip file */ 
	  if (GlobalData.ZipPath)
	  {
		  _tcscpy(extname,GlobalData.ZipPath);
		  *(extname+GlobalData.ZipPathLen) = _T('\\');
		  _tcscpy(extname+GlobalData.ZipPathLen+1,pMod->Name);
		  _tcscpy(extname+GlobalData.ZipPathLen+1+pMod->NameLen,ARCHIVE_EXT);
		  CopyFile(Archive,extname,TRUE);
	  }

    delete[] dlllist;
	  unzClose(zipfile);
  }
#ifndef NLM_IGNORE_EXCEPTIONS
#ifdef _MSC_VER
  __except (EXCEPTION_EXECUTE_HANDLER)
#else
  catch (...)
#endif
  {
    SetModuleError(pMod, IDS_ERROR_EXCEPTION_WHILE_EXTRACTING);
    return false;
  }
#endif

	return !GlobalData.bNoInstallStep;
}
