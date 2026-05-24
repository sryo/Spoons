# Microsoft Developer Studio Project File - Name="alias" - Package Owner=<4>
# Microsoft Developer Studio Generated Build File, Format Version 6.00
# ** NICHT BEARBEITEN **

# TARGTYPE "Win32 (x86) Dynamic-Link Library" 0x0102

CFG=alias - Win32 Debug
!MESSAGE Dies ist kein gültiges Makefile. Zum Erstellen dieses Projekts mit NMAKE
!MESSAGE verwenden Sie den Befehl "Makefile exportieren" und führen Sie den Befehl
!MESSAGE 
!MESSAGE NMAKE /f "alias.mak".
!MESSAGE 
!MESSAGE Sie können beim Ausführen von NMAKE eine Konfiguration angeben
!MESSAGE durch Definieren des Makros CFG in der Befehlszeile. Zum Beispiel:
!MESSAGE 
!MESSAGE NMAKE /f "alias.mak" CFG="alias - Win32 Debug"
!MESSAGE 
!MESSAGE Für die Konfiguration stehen zur Auswahl:
!MESSAGE 
!MESSAGE "alias - Win32 Debug" (basierend auf  "Win32 (x86) Dynamic-Link Library")
!MESSAGE "alias - Win32 Release" (basierend auf  "Win32 (x86) Dynamic-Link Library")
!MESSAGE 

# Begin Project
# PROP AllowPerConfigDependencies 0
# PROP Scc_ProjName ""
# PROP Scc_LocalPath ""
CPP=cl.exe
MTL=midl.exe
RSC=rc.exe

!IF  "$(CFG)" == "alias - Win32 Debug"

# PROP BASE Use_MFC 0
# PROP BASE Use_Debug_Libraries 1
# PROP BASE Output_Dir "Debug"
# PROP BASE Intermediate_Dir "Debug"
# PROP BASE Target_Dir ""
# PROP Use_MFC 0
# PROP Use_Debug_Libraries 1
# PROP Output_Dir "Debug"
# PROP Intermediate_Dir "Debug"
# PROP Target_Dir ""
# ADD BASE CPP /nologo /MTd /W3 /Gm /GX /ZI /Od /D "WIN32" /D "_DEBUG" /D "_WINDOWS" /D "_USRDLL" /D "ALIAS_EXPORTS" /D "_MBCS" /GZ PRECOMP_VC7_TOBEREMOVED /c
# ADD CPP /nologo /MTd /W3 /Gm /GX /ZI /Od /D "WIN32" /D "_DEBUG" /D "_WINDOWS" /D "_USRDLL" /D "ALIAS_EXPORTS" /D "_MBCS" /GZ PRECOMP_VC7_TOBEREMOVED /c
# ADD BASE MTL /nologo /win32
# ADD MTL /nologo /win32
# ADD BASE RSC /l 0x409
# ADD RSC /l 0x409
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:windows /dll /debug /machine:IX86 /implib:"$(OutDir)/alias.lib" /pdbtype:sept
# SUBTRACT BASE LINK32 /pdb:none
# ADD LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib /nologo /subsystem:windows /dll /debug /machine:IX86 /implib:"$(OutDir)/alias.lib" /pdbtype:sept
# SUBTRACT LINK32 /pdb:none

!ELSEIF  "$(CFG)" == "alias - Win32 Release"

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
# ADD BASE CPP /nologo /MD /W4 /GX /Ox /Og /Oi /Os /Op /Ob2 /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /D "_USRDLL" /D "ALIAS_EXPORTS" /D "_MBCS" /GT /GA PRECOMP_VC7_TOBEREMOVED /c
# ADD CPP /nologo /MD /W3 /GX /O1 /Op /Ob2 /D "WIN32" /D "NDEBUG" /D "_WINDOWS" /D "_USRDLL" /D "ALIAS_EXPORTS" /D "_MBCS" /GT /GA /c
# ADD BASE MTL /nologo /win32
# ADD MTL /nologo /win32
# ADD BASE RSC /l 0x409
# ADD RSC /l 0x409
BSC32=bscmake.exe
# ADD BASE BSC32 /nologo
# ADD BSC32 /nologo
LINK32=link.exe
# ADD BASE LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib lsapi.lib shutils.lib /nologo /subsystem:windows /dll /debug /machine:IX86 /implib:"$(OutDir)/alias.lib" /pdbtype:sept /opt:ref /opt:icf
# ADD LINK32 kernel32.lib user32.lib gdi32.lib winspool.lib comdlg32.lib advapi32.lib shell32.lib ole32.lib oleaut32.lib uuid.lib odbc32.lib odbccp32.lib lsapi.lib /nologo /subsystem:windows /dll /pdb:none /machine:IX86 /nodefaultlib:"libcmt" /implib:"$(OutDir)/alias.lib" /opt:ref /opt:icf /opt:NOWIN98

!ENDIF 

# Begin Target

# Name "alias - Win32 Debug"
# Name "alias - Win32 Release"
# Begin Group "Source Files"

# PROP Default_Filter "cpp;c;cxx;def;odl;idl;hpj;bat;asm;asmx"
# Begin Source File

SOURCE=.\alias.cpp
DEP_CPP_ALIAS=\
	".\AggressiveOptimize.h"\
	".\alias.hpp"\
	".\common.hpp"\
	".\utility.hpp"\
	{$(INCLUDE)}"boost\assert.hpp"\
	{$(INCLUDE)}"boost\bind\mem_fn_cc.hpp"\
	{$(INCLUDE)}"boost\bind\mem_fn_template.hpp"\
	{$(INCLUDE)}"boost\bind\mem_fn_vw.hpp"\
	{$(INCLUDE)}"boost\config.hpp"\
	{$(INCLUDE)}"boost\config\posix_features.hpp"\
	{$(INCLUDE)}"boost\config\select_compiler_config.hpp"\
	{$(INCLUDE)}"boost\config\select_platform_config.hpp"\
	{$(INCLUDE)}"boost\config\select_stdlib_config.hpp"\
	{$(INCLUDE)}"boost\config\suffix.hpp"\
	{$(INCLUDE)}"boost\current_function.hpp"\
	{$(INCLUDE)}"boost\detail\workaround.hpp"\
	{$(INCLUDE)}"boost\function.hpp"\
	{$(INCLUDE)}"boost\function\detail\maybe_include.hpp"\
	{$(INCLUDE)}"boost\function\detail\prologue.hpp"\
	{$(INCLUDE)}"boost\function\function0.hpp"\
	{$(INCLUDE)}"boost\function\function1.hpp"\
	{$(INCLUDE)}"boost\function\function10.hpp"\
	{$(INCLUDE)}"boost\function\function2.hpp"\
	{$(INCLUDE)}"boost\function\function3.hpp"\
	{$(INCLUDE)}"boost\function\function4.hpp"\
	{$(INCLUDE)}"boost\function\function5.hpp"\
	{$(INCLUDE)}"boost\function\function6.hpp"\
	{$(INCLUDE)}"boost\function\function7.hpp"\
	{$(INCLUDE)}"boost\function\function8.hpp"\
	{$(INCLUDE)}"boost\function\function9.hpp"\
	{$(INCLUDE)}"boost\function\function_base.hpp"\
	{$(INCLUDE)}"boost\function\function_template.hpp"\
	{$(INCLUDE)}"boost\get_pointer.hpp"\
	{$(INCLUDE)}"boost\mem_fn.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\lambda.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\overload_resolution.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\preprocessor.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\static_constant.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\ttp.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\workaround.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\lambda_support.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\preprocessor\params.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\template_arity_fwd.hpp"\
	{$(INCLUDE)}"boost\mpl\bool.hpp"\
	{$(INCLUDE)}"boost\mpl\bool_fwd.hpp"\
	{$(INCLUDE)}"boost\pending\ct_if.hpp"\
	{$(INCLUDE)}"boost\preprocessor\cat.hpp"\
	{$(INCLUDE)}"boost\preprocessor\comma_if.hpp"\
	{$(INCLUDE)}"boost\preprocessor\config\config.hpp"\
	{$(INCLUDE)}"boost\preprocessor\control\iif.hpp"\
	{$(INCLUDE)}"boost\preprocessor\debug\error.hpp"\
	{$(INCLUDE)}"boost\preprocessor\detail\auto_rec.hpp"\
	{$(INCLUDE)}"boost\preprocessor\detail\check.hpp"\
	{$(INCLUDE)}"boost\preprocessor\detail\is_binary.hpp"\
	{$(INCLUDE)}"boost\preprocessor\enum.hpp"\
	{$(INCLUDE)}"boost\preprocessor\enum_params.hpp"\
	{$(INCLUDE)}"boost\preprocessor\inc.hpp"\
	{$(INCLUDE)}"boost\preprocessor\iterate.hpp"\
	{$(INCLUDE)}"boost\preprocessor\list\adt.hpp"\
	{$(INCLUDE)}"boost\preprocessor\list\for_each_i.hpp"\
	{$(INCLUDE)}"boost\preprocessor\logical\bool.hpp"\
	{$(INCLUDE)}"boost\preprocessor\logical\compl.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repeat.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\detail\edg\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\detail\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\detail\msvc\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\eat.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\elem.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\rem.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\to_list.hpp"\
	{$(INCLUDE)}"boost\ref.hpp"\
	{$(INCLUDE)}"boost\throw_exception.hpp"\
	{$(INCLUDE)}"boost\type.hpp"\
	{$(INCLUDE)}"boost\type_traits\add_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\add_reference.hpp"\
	{$(INCLUDE)}"boost\type_traits\arithmetic_traits.hpp"\
	{$(INCLUDE)}"boost\type_traits\broken_compiler_spec.hpp"\
	{$(INCLUDE)}"boost\type_traits\composite_traits.hpp"\
	{$(INCLUDE)}"boost\type_traits\config.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\bool_trait_def.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\bool_trait_undef.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\cv_traits_impl.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\false_result.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_and.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_eq.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_not.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_or.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_function_ptr_helper.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_function_ptr_tester.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_function_type_tester.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_mem_fun_pointer_impl.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_mem_fun_pointer_tester.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\template_arity_spec.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\type_trait_def.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\type_trait_undef.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\wrap.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\yes_no_type.hpp"\
	{$(INCLUDE)}"boost\type_traits\has_trivial_constructor.hpp"\
	{$(INCLUDE)}"boost\type_traits\has_trivial_copy.hpp"\
	{$(INCLUDE)}"boost\type_traits\has_trivial_destructor.hpp"\
	{$(INCLUDE)}"boost\type_traits\ice.hpp"\
	{$(INCLUDE)}"boost\type_traits\intrinsics.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_arithmetic.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_array.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_class.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_convertible.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_empty.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_enum.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_float.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_function.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_fundamental.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_integral.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_member_function_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_member_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_pod.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_reference.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_same.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_scalar.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_stateless.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_union.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_void.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_volatile.hpp"\
	{$(INCLUDE)}"boost\type_traits\remove_cv.hpp"\
	{$(INCLUDE)}"boost\type_traits\remove_reference.hpp"\
	{$(INCLUDE)}"boost\utility\addressof.hpp"\
	{$(INCLUDE)}"litestep\lsapi\lsapi.h"\
	{$(INCLUDE)}"litestep\lsapi\lsapidefines.h"\
	{$(INCLUDE)}"litestep\lsapi\lsmultimon.h"\
	{$(INCLUDE)}"strsafe.h"\
	
# End Source File
# Begin Source File

SOURCE=.\utility.cpp
DEP_CPP_UTILI=\
	".\AggressiveOptimize.h"\
	".\common.hpp"\
	".\utility.hpp"\
	{$(INCLUDE)}"boost\assert.hpp"\
	{$(INCLUDE)}"boost\bind\mem_fn_cc.hpp"\
	{$(INCLUDE)}"boost\bind\mem_fn_template.hpp"\
	{$(INCLUDE)}"boost\bind\mem_fn_vw.hpp"\
	{$(INCLUDE)}"boost\config.hpp"\
	{$(INCLUDE)}"boost\config\posix_features.hpp"\
	{$(INCLUDE)}"boost\config\select_compiler_config.hpp"\
	{$(INCLUDE)}"boost\config\select_platform_config.hpp"\
	{$(INCLUDE)}"boost\config\select_stdlib_config.hpp"\
	{$(INCLUDE)}"boost\config\suffix.hpp"\
	{$(INCLUDE)}"boost\current_function.hpp"\
	{$(INCLUDE)}"boost\detail\workaround.hpp"\
	{$(INCLUDE)}"boost\function.hpp"\
	{$(INCLUDE)}"boost\function\detail\maybe_include.hpp"\
	{$(INCLUDE)}"boost\function\detail\prologue.hpp"\
	{$(INCLUDE)}"boost\function\function0.hpp"\
	{$(INCLUDE)}"boost\function\function1.hpp"\
	{$(INCLUDE)}"boost\function\function10.hpp"\
	{$(INCLUDE)}"boost\function\function2.hpp"\
	{$(INCLUDE)}"boost\function\function3.hpp"\
	{$(INCLUDE)}"boost\function\function4.hpp"\
	{$(INCLUDE)}"boost\function\function5.hpp"\
	{$(INCLUDE)}"boost\function\function6.hpp"\
	{$(INCLUDE)}"boost\function\function7.hpp"\
	{$(INCLUDE)}"boost\function\function8.hpp"\
	{$(INCLUDE)}"boost\function\function9.hpp"\
	{$(INCLUDE)}"boost\function\function_base.hpp"\
	{$(INCLUDE)}"boost\function\function_template.hpp"\
	{$(INCLUDE)}"boost\get_pointer.hpp"\
	{$(INCLUDE)}"boost\mem_fn.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\lambda.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\overload_resolution.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\preprocessor.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\static_constant.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\ttp.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\config\workaround.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\lambda_support.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\preprocessor\params.hpp"\
	{$(INCLUDE)}"boost\mpl\aux_\template_arity_fwd.hpp"\
	{$(INCLUDE)}"boost\mpl\bool.hpp"\
	{$(INCLUDE)}"boost\mpl\bool_fwd.hpp"\
	{$(INCLUDE)}"boost\pending\ct_if.hpp"\
	{$(INCLUDE)}"boost\preprocessor\cat.hpp"\
	{$(INCLUDE)}"boost\preprocessor\comma_if.hpp"\
	{$(INCLUDE)}"boost\preprocessor\config\config.hpp"\
	{$(INCLUDE)}"boost\preprocessor\control\iif.hpp"\
	{$(INCLUDE)}"boost\preprocessor\debug\error.hpp"\
	{$(INCLUDE)}"boost\preprocessor\detail\auto_rec.hpp"\
	{$(INCLUDE)}"boost\preprocessor\detail\check.hpp"\
	{$(INCLUDE)}"boost\preprocessor\detail\is_binary.hpp"\
	{$(INCLUDE)}"boost\preprocessor\enum.hpp"\
	{$(INCLUDE)}"boost\preprocessor\enum_params.hpp"\
	{$(INCLUDE)}"boost\preprocessor\inc.hpp"\
	{$(INCLUDE)}"boost\preprocessor\iterate.hpp"\
	{$(INCLUDE)}"boost\preprocessor\list\adt.hpp"\
	{$(INCLUDE)}"boost\preprocessor\list\for_each_i.hpp"\
	{$(INCLUDE)}"boost\preprocessor\logical\bool.hpp"\
	{$(INCLUDE)}"boost\preprocessor\logical\compl.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repeat.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\detail\edg\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\detail\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\detail\msvc\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\repetition\for.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\eat.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\elem.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\rem.hpp"\
	{$(INCLUDE)}"boost\preprocessor\tuple\to_list.hpp"\
	{$(INCLUDE)}"boost\ref.hpp"\
	{$(INCLUDE)}"boost\throw_exception.hpp"\
	{$(INCLUDE)}"boost\type.hpp"\
	{$(INCLUDE)}"boost\type_traits\add_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\add_reference.hpp"\
	{$(INCLUDE)}"boost\type_traits\arithmetic_traits.hpp"\
	{$(INCLUDE)}"boost\type_traits\broken_compiler_spec.hpp"\
	{$(INCLUDE)}"boost\type_traits\composite_traits.hpp"\
	{$(INCLUDE)}"boost\type_traits\config.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\bool_trait_def.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\bool_trait_undef.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\cv_traits_impl.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\false_result.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_and.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_eq.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_not.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\ice_or.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_function_ptr_helper.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_function_ptr_tester.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_function_type_tester.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_mem_fun_pointer_impl.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\is_mem_fun_pointer_tester.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\template_arity_spec.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\type_trait_def.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\type_trait_undef.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\wrap.hpp"\
	{$(INCLUDE)}"boost\type_traits\detail\yes_no_type.hpp"\
	{$(INCLUDE)}"boost\type_traits\has_trivial_constructor.hpp"\
	{$(INCLUDE)}"boost\type_traits\has_trivial_copy.hpp"\
	{$(INCLUDE)}"boost\type_traits\has_trivial_destructor.hpp"\
	{$(INCLUDE)}"boost\type_traits\ice.hpp"\
	{$(INCLUDE)}"boost\type_traits\intrinsics.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_arithmetic.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_array.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_class.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_convertible.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_empty.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_enum.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_float.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_function.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_fundamental.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_integral.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_member_function_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_member_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_pod.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_pointer.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_reference.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_same.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_scalar.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_stateless.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_union.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_void.hpp"\
	{$(INCLUDE)}"boost\type_traits\is_volatile.hpp"\
	{$(INCLUDE)}"boost\type_traits\remove_cv.hpp"\
	{$(INCLUDE)}"boost\type_traits\remove_reference.hpp"\
	{$(INCLUDE)}"boost\utility\addressof.hpp"\
	{$(INCLUDE)}"litestep\lsapi\lsapi.h"\
	{$(INCLUDE)}"litestep\lsapi\lsapidefines.h"\
	{$(INCLUDE)}"litestep\lsapi\lsmultimon.h"\
	{$(INCLUDE)}"strsafe.h"\
	
# End Source File
# End Group
# Begin Group "Header Files"

# PROP Default_Filter "h;hpp;hxx;hm;inl;inc;xsd"
# Begin Source File

SOURCE=.\alias.hpp
# End Source File
# Begin Source File

SOURCE=.\common.hpp
# End Source File
# Begin Source File

SOURCE=.\utility.hpp
# End Source File
# End Group
# Begin Group "Resource Files"

# PROP Default_Filter "rc;ico;cur;bmp;dlg;rc2;rct;bin;rgs;gif;jpg;jpeg;jpe;resx"
# Begin Source File

SOURCE=.\alias.rc
# End Source File
# Begin Source File

SOURCE=.\resource.h
# End Source File
# End Group
# End Target
# End Project
