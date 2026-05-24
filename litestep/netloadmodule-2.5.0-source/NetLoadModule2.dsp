# Microsoft Developer Studio Project File - Name="NetLoadModule2" - Package Owner=<4>
# Microsoft Developer Studio Generated Build File, Format Version 6.00
# ** DO NOT EDIT **

# TARGTYPE "Win32 (x86) Dynamic-Link Library" 0x0102

CFG=NetLoadModule2 - Win32 Debug
!MESSAGE This is not a valid makefile. To build this project using NMAKE,
!MESSAGE use the Export Makefile command and run
!MESSAGE 
!MESSAGE NMAKE /f "NetLoadModule2.mak".
!MESSAGE 
!MESSAGE You can specify a configuration when running NMAKE
!MESSAGE by defining the macro CFG on the command line. For example:
!MESSAGE 
!MESSAGE NMAKE /f "NetLoadModule2.mak" CFG="NetLoadModule2 - Win32 Debug"
!MESSAGE 
!MESSAGE Possible choices for configuration are:
!MESSAGE 
!MESSAGE "NetLoadModule2 - Win32 Release" (based on "Win32 (x86) Dynamic-Link Library")
!MESSAGE "NetLoadModule2 - Win32 Debug" (based on "Win32 (x86) Dynamic-Link Library")
!MESSAGE 

# Begin Project
# PROP AllowPerConfigDependencies 0
# PROP Scc_ProjName ""
# PROP Scc_LocalPath ""
CPP=cl.exe
MTL=midl.exe
RSC=rc.exe

!IF  "$(CFG)" == "NetLoadModule2 - Win32 Release"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 0
# PROP BASE Output_Dir "Release"
# PROP BASE Intermediate_Dir "Release"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 0
# PROP Output_Dir "Release"
# PROP Intermediate_Dir "Release"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
# ADD BASE CPP /nologo /MT /W3 /GX /O2 /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /D "_MBCS" /D "_USRDLL" /D "NETLOADMODULE2_EXPORTS" /YX /FD /c
# ADD CPP /nologo /MD /W3 /GX /O1 /Ob2 /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /D "_MBCS" /D "_USRDLL" /D "NETLOADMODULE2_EXPORTS" /D "ZLIB_DLL" /FD /c
# SUBTRACT CPP /Fr /YX
# ADD BASE MTL /nologo /D "NDEBUG" /mktyplib203 /win32
# ADD MTL /nologo /D "NDEBUG" /win32
# SUBTRACT MTL /mktyplib203
# ADD BASE RSC /l 0x409 /d "NDEBUG"
# ADD RSC /l 0x409 /d "NDEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /dll /machine:I386
# ADD LINK32 kernel32.lib user32.lib gdi32.lib zlib1.lib lsapi.lib msvcrt.lib comctl32.lib /nologo /dll /machine:I386 /nodefaultlib /OPT:NOWIN98
# SUBTRACT LINK32 /pdb:none

!ELSEIF  "$(CFG)" == "NetLoadModule2 - Win32 Debug"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 1
# PROP BASE Output_Dir "Debug"
# PROP BASE Intermediate_Dir "Debug"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 1
# PROP Output_Dir "Debug"
# PROP Intermediate_Dir "Debug"
# PROP Ignore_Export_Lib 0
# PROP Target_Dir ""
# ADD BASE CPP /nologo /MTd /W3 /Gm /GX /ZI /Od /D "WIN32" /D "_DEBUG" /D "_WINDOWS" /D "_MBCS" /D "_USRDLL" /D "NETLOADMODULE2_EXPORTS" /YX /FD /GZ /c
# ADD CPP /nologo /MDd /W3 /GX /Zi /Od /Ob2 /D "WIN32" /D "_DEBUG" /D "_WINDOWS" /D "_MBCS" /D "_USRDLL" /D "NETLOADMODULE2_EXPORTS" /D "ZLIB_DLL" /FR /FD /c
# SUBTRACT CPP /YX
# ADD BASE MTL /nologo /D "_DEBUG" /mktyplib203 /win32
# ADD MTL /nologo /D "_DEBUG" /win32
# SUBTRACT MTL /mktyplib203
# ADD BASE RSC /l 0x409 /d "_DEBUG"
# ADD RSC /l 0x409 /d "_DEBUG"
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /dll /debug /machine:I386 /pdbtype:sept
# ADD LINK32 kernel32.lib user32.lib gdi32.lib zlib1d.lib lsapi.lib msvcrtd.lib comctl32.lib /nologo /dll /debug /machine:I386 /nodefaultlib /pdbtype:sept

!ENDIF 

# Begin Target

# Name "NetLoadModule2 - Win32 Release"
# Name "NetLoadModule2 - Win32 Debug"
# Begin Group "Source Files"

# PROP Default_Filter "cpp;c;cxx;rc;def;r;odl;idl;hpj;bat"
# Begin Source File

SOURCE=.\alias.cpp
# End Source File
# Begin Source File

SOURCE=.\bangs.cpp
# End Source File
# Begin Source File

SOURCE=.\debug.cpp
# End Source File
# Begin Source File

SOURCE=.\IBindStatusCallback.cpp
# End Source File
# Begin Source File

SOURCE=.\InstallModule.cpp
# End Source File
# Begin Source File

SOURCE=.\keywords.hash

!IF  "$(CFG)" == "NetLoadModule2 - Win32 Release"

# Begin Custom Build
InputDir=.
ProjDir=.
InputPath=.\keywords.hash

BuildCmds= \
	"$(ProjDir)\makehash.exe" -B "$(InputPath)"

"$(InputDir)\keywords.cpp" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)

"$(InputDir)\keywords.h" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)
# End Custom Build

!ELSEIF  "$(CFG)" == "NetLoadModule2 - Win32 Debug"

# Begin Custom Build
InputDir=.
ProjDir=.
InputPath=.\keywords.hash

BuildCmds= \
	"$(ProjDir)\makehash.exe" -B "$(InputPath)"

"$(InputDir)\keywords.cpp" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)

"$(InputDir)\keywords.h" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)
# End Custom Build

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\lsmod_common.cpp
# End Source File
# Begin Source File

SOURCE=.\ModuleListDlg.cpp
# End Source File
# Begin Source File

SOURCE=.\MultipleDllDlg.cpp
# End Source File
# Begin Source File

SOURCE=.\NetLoadModule.cpp
# End Source File
# Begin Source File

SOURCE=.\NetLoadModule2.rc
# End Source File
# Begin Source File

SOURCE=.\parsers.cpp
# End Source File
# Begin Source File

SOURCE=.\siteoptions.cpp
# End Source File
# End Group
# Begin Group "Header Files"

# PROP Default_Filter "h;hpp;hxx;hm;inl"
# Begin Source File

SOURCE=.\IBindStatusCallback.h
# End Source File
# Begin Source File

SOURCE=.\lsmod_common.h
# End Source File
# Begin Source File

SOURCE=.\NetLoadModule.h
# End Source File
# Begin Source File

SOURCE=.\resource.h
# End Source File
# End Group
# Begin Group "Resource Files"

# PROP Default_Filter "ico;cur;bmp;dlg;rc2;rct;bin;rgs;gif;jpg;jpeg;jpe"
# Begin Source File

SOURCE=.\bitmap1.bmp
# End Source File
# Begin Source File

SOURCE=.\download.ico
# End Source File
# Begin Source File

SOURCE=.\errors.mc

!IF  "$(CFG)" == "NetLoadModule2 - Win32 Release"

# Begin Custom Build
InputDir=.
InputPath=.\errors.mc

BuildCmds= \
	"MC.exe" -h "$(InputDir)" -r "$(InputDir)" "$(InputPath)"

"$(InputDir)\errors.h" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)

"$(InputDir)\errors.rc" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)

"$(InputDir)\MSG00409.bin" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)
# End Custom Build

!ELSEIF  "$(CFG)" == "NetLoadModule2 - Win32 Debug"

# Begin Custom Build
InputDir=.
InputPath=.\errors.mc

BuildCmds= \
	"MC.exe" -h "$(InputDir)" -r "$(InputDir)" "$(InputPath)"

"$(InputDir)\errors.h" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)

"$(InputDir)\errors.rc" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)

"$(InputDir)\MSG00409.bin" : $(SOURCE) "$(INTDIR)" "$(OUTDIR)"
   $(BuildCmds)
# End Custom Build

!ENDIF 

# End Source File
# Begin Source File

SOURCE=.\manyfiles.ico
# End Source File
# Begin Source File

SOURCE=.\MSG00409.bin
# End Source File
# End Group
# Begin Group "Intermediate Files"

# PROP Default_Filter ""
# Begin Source File

SOURCE=.\errors.h
# End Source File
# Begin Source File

SOURCE=.\keywords.cpp
# End Source File
# Begin Source File

SOURCE=.\keywords.h
# End Source File
# End Group
# Begin Group "Common Files"

# PROP Default_Filter ""
# Begin Source File

SOURCE=".\hash-oaat.h"
# End Source File
# Begin Source File

SOURCE=.\hash.h
# End Source File
# Begin Source File

SOURCE=.\unzip\ioapi.c
# End Source File
# Begin Source File

SOURCE=.\unzip\ioapi.h
# End Source File
# Begin Source File

SOURCE=.\unzip\iowin32.c
# End Source File
# Begin Source File

SOURCE=.\unzip\iowin32.h
# End Source File
# Begin Source File

SOURCE=.\unzip\unzip.c
# End Source File
# Begin Source File

SOURCE=.\unzip\unzip.h
# End Source File
# End Group
# End Target
# End Project
