mzScript 1.0.4 (alurcard2) (June 10 2010)
-------------

- *Script refresh lines no longer cause errors on startup

mzScript 1.0.3 (phil) (February 17 2007)
--------------

- Defining a new, undefined list variable directly would cause the list separator to be defined before the first element, such that all array elements were offset by +1. Nasty bug. Sorry.

mzScript 1.0.2 (jugg via phil) (July 27 2006)
--------------

- jugg seems to have fixed the major error that was triggered by using null separators in arrays.
 - This bug has been present since 1.0RC2.
 - jugg's fix was to replace the %f by %c in line 206 of utility.hpp

mzScript 1.0.1 (phil) (November 08 2005)
--------------

- Some log events were not adjusted to the new format. Fixed.
- Added the AggressiveOptimise header to see if it improves speed/size at all.
- Revised some of the internal log level handling code to eliminate false warnings when using the LS log file.
- New approach to log filtering to make it more efficient and far more logical (in source code terms). Operation should be unaffected.
- Moved the log level checking code out to the mzscript.cpp file - easier and better to keep file-specific checks in one place.

mzscript 1.0 (phil) (November 04 2005)
------------

The 1.0 release changes the internals for logging and the error message dialog. By doing this, it becomes much easier to handle future expansion and to implement the filtering of logging events. Externally, very little will seem to have changed as a result of this, so don't worry :) The internals may be slightly less than optimal, but I'll leave that to more talented folks to sort out. It works; that's fine by me.

The other change, revived from the 0.9 releases of mzScript, is transparent evaluation of LS Evars. If you reference %{variable} and it doesn't exist, mzScript will attempt to evaluate $variable$. Note that this is an experimental feature that needs to be activated by setting mzEvaluateEVars in your theme .rc code. This was included to prevent the simultaneous release of 1.0 and 1.1 alpha.

Any further changes beyond minor fixes to the stable 1.0 code will go into 1.1 - this includes the Evar mapping system and the timer implementation (especially since there is no perceivable speed loss under LDE(X) with the current approaches in place). I'm fairly confident that LDE(X) is the most intensive test for scripting code under LS :b

[Internal LDE(X) dev team '1.0' release.]

mzscript 1.0 RC4 (phil) (October 14 2005)
----------------

The logger has seen some changes to improve its flexibility. The log level now, like LS, allows info/warn/error messages to be filtered from the log. This is only partially implemented in the source at the time of writing and requires a legacy wrapper to flag older log syntax. Old log messages will be written irrespective of the current log level.

RC3 may have been shipped with the wrong setting named for the maximum log file size - MaxLogFileSize is correct, but was discovered to be wrong in the code.

An attempt has been made to close the log at the end of every write, but this will impact performance. The end implementation will be to close the log after a period of time, giving maximum performance for sequential writes, but allowing the log to be manipulated during quiet time.

The next build will be 1.0 as far as LDE(X) is concerned - the timer implementation is the only thing missing.

mzscript 1.0 RC3 (phil) (October 03 2005)
----------------

The logger seemed to be producing poor layout and wasn't being used to full advantage. Logging is designed to allow you to hide debug output from your users - not to deluge them with message boxes. That's all now been taken care of. The internals are also slightly more efficient, centralising message box/log output in ErrorMessage() for error and warning reports. Information reports need to directly hit the logger or message box, but that's fine.

In addition, you can now set an upper limit to the log file size. LDE(X) was producing extremely large logs and this was causing us some trouble, so we made the changes to fix this up as well.

!VarRemove [variable][another variable] has returned as well. This was missing in previous RCx releases, so it's been good to get that support back in the module.

All this and the module size has also dropped by around 2KB.

	Changed:
		- ErrorMessage function to only show message boxes when logging is not enabled. This makes sense given that you are logging errors.
		- Error handling - now every warning/error is reported through ErrorMessage(). Informational reports get to use the logger directly.
		- If mzScript's own logging is inactive, but LS logging is enabled, try and use the LS log file.
		- Logging output. Too many new lines and tabs were causing readability problems. Eventually, it would be good to have warning/error/information handlers to more easily standardise the output format. Localisation support would be good as well, but is currently unavailable.
		- gLogger->close now returns a boolean so errors can be reported related to this file system action.

	Added:
		- Code to publicise the logging support across the module so that suppression of undesirable behaviour is possible in these situations.
		- Support for MaxLogFileSize to keep logs to a manageable size. The hard-coded behaviour is to delete the old log file create a one. This only happens at startup due to overhead anticipated from doing the checks at every log event. The LSLogMaxFileSize setting is also supported, but MaxLogFileSize will be used if both are defined.

	Fixed:
		- !varremove [variable][variable2].... now works as before. Major thanks to the xStep team for the source to xLabel - I used it as a referenced to sort out this problem in mzScript.
		- You can now compile against different LiteStep-based projects more easily - path references to /litestep/ have been removed. Set up the include paths in your dev environment to look in the folder below the 'litestep' source folder and the 'litestep' source folder itself. Same for the library paths. Job done.

mzscript 1.0 RC2

Changes in mzscript 1.0 RC2 build (May 15, 2005):
	-changed: varfiles read in and store as is, as apposed to expanding then saving. 
		This is how it was before RC1, and it seems to be the best way todo it.
		This should fix some saving problems.		
			EX.where before RC1 it'd save a
			>var like: "$styledir$test\"
			>but in RC1 it expands to "c:\litestep\theme\themename\style\test\"
			now once again in RC2 it will save like : "$styledir$test\"			
	-Fixed: some problems with if else endif statements in varfiles
	-Fixed: varfiles now accept elseif statements
	-Fixed: varfiles lost formatting when variables were saved
	-Fixed: a couple major problems that should not have made it as far as they did
	-Added: mzlogfile now has timestamps


Changes in mzscript 1.0 RC1 build (May 7, 2005):
This build brings alot of changes, some that might break scripts 
from past builds, so read carefully. 
(I know its alot to read and understand. I am working on a brand 
new readme, but with RL getting in the way it might take a while.)

	-New readme started. Any contributions of spelling and grammer checking or
		example scripts would be greatly appreciated. Actually any contributions 
		to this readme AT ALL would be greatly appreciated. This is the first 
		release candidate. If all seems to work well, this will become the first 
		true release of 1.0.

	-[]'s can now be used in many places they could not be used before.
			This allows performing tasks like setting variables to hold 
			quotes to be done much easier.
			EX.
			!varset myvar ["abc" 'def']
			would yeild
			%{myvar}="abc" 'def'
			This also allows you to use [] around variables that might 
			hold quotes, without having to worry about the quotes in 
			the variable messing up your script.
			EX.
			if %{var1}="
			
	-added new escape character combo.
			"%-" now expands into "'" (single quote aka. apostrophe)
			
	-var:count now equals 0 when var is empty
	
	-the separator now separates even if it is between quotes
			so [a:"b:c":d] would be separated into [a], ["b], [c"], and [d]
			
	-var:sep can now be more than one character long
			EX.
			!varset var:sep "<br>"
			
	-var:sep can now be set to a special case: token
			EX
			!varset var:sep token
			This will use standard litestep tokenization (whitespace, ", ', and [])
			to seperate the variable. Read on about args to understand more.
			
	-the args variable is now split up based on standard 
			litestep tokenization (using whitespace, ", ', and [])
			EX:
			if %{args}=abc "def" 'ghi' [jkl]
			%{args:1}=abc
			%{args:2}=def
			%{args:3}=ghi
			%{args:4}=jkl
			(this is the same thing as var:sep=token)
	-NOTE:each script also has a %{script} variable that equals the name of the script. 
			This has always been implemented but never noted in documentation.
			
	-mzvarfiles now support IF Else EndIf statements when reading in AND saving 
			(i think... this is gunna take alot of testing to make sure though)
			
	-new way of reading in and saving variables-
			when read in, everything after the variable name is stored in var:line. It 
			can be accessed and set like var:sep. Then, when !varset is called, the 
			value AND the line is changed, then when you save, the var:line is saved, 
			not just the value. This actually allows you to work with multitoken 
			variables like labelBorders 1 2 3 4. It just takes a bit of work.
			Also, when you alter var:line it  is retokenized to find the actual value 
			of var. If var:line has no token, then the var becomes empty. 
			If you perform a remove on var:line, the var also becomes empty.
			The main reason i did this is so that saving doesn't just add quotes.
			Instead, it uses what was there when the variable was read in.
			EX.
			(from some mzvarfile)
			myvar "c:\music\" 3
			(after reading in)
			%{myvar}=c:\music\
			%{myvar:line}= "c:\music\" 3
			(then if i do)
			!varset myvar "c:\games\"
			(then this will be true)
			%{myvar}=c:\games\
			%{myvar:line}= "c:\games\" 3
			and of course i can do this:
			!varset myvar:line [ "c:\appz\" 2]
			(then this will be true)
			%{myvar}=c:\appz\
			%{myvar:line}= "c:\appz\" 2
			NOTE:var:line uses the token separator, 
			so if this is true:
			%{var:line}= "c:\games\" 3 5
			so you can do:
			!varset var:line:1 "c:\music\"
			and then this would be true:
			%{var:line}= "c:\music\" 3 5
			%{var}=c:\music\
			
	-updated !varshow and !vardump to include var:line
	
	-added a new inline if using %{?[conditional][replace_if_true][replace_if_false]}
			EX.
			%{?[%{var1} = %{var2}] [%{var3}] [%{var4}]}
			%{?[%{var1:sep} = token] [token] [not token]}
			
		
//New readme follows. It is a work in progress.

=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
								  mzscript 1.0
					An advanced script module for LiteStep
						 	Current maintainer: SMaddox
							Last Modified: May 15, 2005
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

================================================================================
	TABLE OF CONTENTS
================================================================================

 1. About
 2. Installation
 x. Step.rc Commands
 x. Bang Commands
 x. Script Commands
 x. Variables
 x. Misc.
 x. Examples
 x. Conversion Guide (to ease the transition to 1.0)
 x. Known Issues
 x. Version History
 x. Contact Information

================================================================================
	1. About
================================================================================

 mzscript.dll is an advanced scripting module for LiteStep.
 Use at your own risk (shouldn't be any trouble though).

 Compatibility ---- Tested under LiteStep 0.24.7

 !Refresh support - Fully reloads configuration.

 Threading -------- mzscript itself should work fine if loaded "threaded", but
                    if other modules' !bangs are called inside scripts you might
                    get unexpected results.
                    
================================================================================
	2. Installation
================================================================================
In order to run this dll, you need msvcr71.dll and msvcp71.dll on the system.
These can be optained by either installing the Microsoft .NET Foundation 1.1, or 
through various websites that distrubute them for free (use google).

 Option 1:       
	Put mzscript.dll in a directory of your choice, e.g. C:\Litestep\Modules\.
	Open your step.rc and add a LoadModule line pointing to the dll, for example:

	LoadModule "C:\Litestep\Modules\mzscript.dll"
	
Option 2:
	*NetLoadModuleSite "http://www.ls-universe.info/download/modules/"
	*NetLoadModule mzscript-1.0
	
================================================================================
	4. Step.rc Commands
================================================================================
	include "Path-To-mzscriptfile"
		new (or really old) way to load scripts. 
		There is no *mzScriptFile command.
	
	*mzVarFile "Path-To-mzvarfile"
		load a var file
	
	mzLogFile "Path-To-mzLogfile"
		set a mzlog file (useful for debugging scripts)
	
	mzAutoSaveVars
		Either true or false. 
		If true, variables will be saved on !recycle, !reload, and !quit.		
	
================================================================================
	5. Bang Commands
================================================================================
	Arguments surrounded by ()'s are optional.

	!varSet MZVAR VALUE
		Sets variable MZVAR to VALUE. 
		Be sure to surround VALUE with ',",or [] if has spaces in it.
		Example: !varset myVar "Hello World"
		
	!varRemove MZVAR
		Removes (a.k.a deletes) MZVAR
		Example: !varRemove myVar
	
	!varShow MZVAR
		Show context of MZVAR in a message box
		Example: !varShow myVar
	
	!varRun MZVAR
		execute the contents of MZVAR
		Example: !varRun myVar
	
	!varAdd MZVAR VALUE
		adds VALUE to MZVAR and stores the result back in MZVAR
		Example: !varAdd myVar 5
	
	!varMul MZVAR VALUE
		multiplies VALUE by MZVAR and stores the result back in MZVAR
		Example: !varAdd myVar 5
	
	!varInt MZVAR
		rounds MZVAR to the nearest integer value and stores the result 
		back in MZVAR
		
	!varMod MZVAR VALUE
		divides MZVAR by VALUE and stores remainder back in MZVAR
		Module(Mod) is the operation that gives the remainder of a division 
		of two integer values. Note that if either MZVAR or VALUE are decimals, 
		they will be truncated before the operation.
	
	!varRnd MZVAR (VALUE)
		generates a random number and stores it in MZVAR
		If VALUE is provided, then the number is an integer between 1 and VALUE.
		If it is not provided, then the number is a decimal between 0 and 1.
	
	!varDump FILE_PATH
		appends data of all current mzvars to FILE_PATH
	
	!varSave MZVAR
		saves MZVAR to the file it was read in from
	
	!varSaveAll
		saves all mzvars to the file they were read in from
	
	!ifExist MZVAR [COMMAND_IF_TRUE] ([COMMAND_IF_FALSE])
		if MZVAR is defined, COMMAND_IF_TRUE is executed
		if not, COMMAND_IF_FALSE is executed
	
	!if [CONDITION] [COMMAND_IF_TRUE] ([COMMAND_IF_FALSE])
		if CONDITION evaluates to true, COMMAND_IF_TRUE is executed
		if not, COMMAND_IF_FALSE is executed
		
		Example of [CONDITION]:
		["%{color}" = blue] (use quotes or brackets around expressions with spaces)
		
		Valid comparisons are:
		"<" less than
		"<=" less or equal to
		">" greater than
		">=" greater or equal to
		"=" equal to
		"<>" not equal to
	
	!exec COMMAND
		executes COMMAND with var substitution. 
		this is useful for using %{mzvar} outside of a script.
	
	!msgbox TEXT
		pops up a message box with TEXT in it (var substitution takes place)
		
	!mzLoadVarFile FILE_PATH
		loads mzvars from FILE_PATH. This can be used to refresh variables 
		that have been changed since they were last read in.
	
	!pause INT
		pauses the script for INT milliseconds (1/1000 th of a second)
		
================================================================================
	x. Script Commands
================================================================================

	*Script start COMMAND
		Executes command on startup (doesn't include !refresh)
		
	*Script refresh COMMAND
		Executes command on !refresh

	*Script bang !BANG_NAME
		Start of a bangscript that will be connected to !BANG_NAME

	*Script exec COMMAND
		Part of a bangscript that executes COMMAND when the bang is invoked

	*Script exit
		Exits a bangscript

	*Script label LABEL
		Used with goto and gotoif

	*Script goto LABEL
		Jumps to LABEL in bangscript. If LABEL is not found then 
		the script is aborted.

	*Script gotoif [CONDITION] [LABEL_IF_TRUE] ([LABEL_IF_FALSE])
		If CONDITION is true jumps to LABEL_IF_TRUE, otherwise jumps 
		to LABEL_IF_FALSE. If the label is not found then the bangscript 
		is aborted. See !if for valid CONDITIONs.

	*Script ~bang
		Declares the end of a bangscript.			
		
	Each script has its own "args" and "script" variables that can only be used 
	in that bangscript. 
		The "args" variable holds the arguments passed in with the bang command,
			and it uses the special token separator.
		The "script" variable simply holds the name of the bangscript.
		
================================================================================
	x. Variables
================================================================================
	
	Variables in MzScript 1.0 have several special properties. They include:
	
		var:sep (read/write)
			Each variable in MzScript 1.0 has its own separator, which is stored 
			in var:sep. The default value is ':' (colon). 
			There are two special case separators. They are the null 
			separator (""), and the token separator ("token"). 
				The null separator separates each character as an element. 
				The token separator uses standard litestep tokenization to split 
				up the elements.
			
		var:N (read/write) where N is a whole number (integer)
			This is the Nth Element of the value stored in var.
			Elements are split up by the variables separator.
				Example 1: for %{var}=c:\my music\author:title.mp3 and %{var:sep}=:
					%{var:1}=c
					%{var:2}=\my music\author
					%{var:3}=title.mp3
					
				Example 2: for %{var}=litestep and %{var:sep}=
					%{var:1}=l
					%{var:2}=i
					%{var:3}=t
					%{var:4}=e
					%{var:5}=s
					%{var:6}=t
					%{var:7}=e
					%{var:8}=p
				
				Example 3: for %{args}=abc "def" 'ghi' [jkl] and %{args:sep}=token
					%{args:1}=abc
					%{args:2}=def
					%{args:3}=ghi
					%{args:4}=jkl
					
		var:count (read)
			This is the number of elements in the value stored in var.
				Example: for %{var}=c:\my music\author:title.mp3 and %{var:sep}=:
					%{var:count}=3
					
		Note: The rest of the properties are only used when the variable was read in 
			from an mzvarfile.
		
		var:line (read/write)
			when var is read in from the mzvarfile, everything after the variable name 
			is stored in var:line, and the first token of var:line is set as the value 
			of var. Then anytime you change the value of var, var:line is updated with 
			the new contents. You can also change var:line directly, and the value of 
			var will be updated. When var is saved, it replaces the line that is in the 
			file with var:line. This allows direct control of how the variable will be 
			save for when more control is needed.
		
		var:line:N (read/write)
			This is the same as var:N from above, except for var:line.
			Note that the separator for var:line is the special token separator.
		
		
		var:line:count (read)
			This is the same as var:count from above, except for var:line.
		
		
		var:file (read)
			This holds the path to the file from which var was read in.
		
	They can be accessed using substitutions. Substitution is similar to litestep 
	substitution, except it uses %{VAR} instead of $VAR$. The different 
	substitutions are as follows:
	
		%{VAR}
			This is replaced with the value of VAR. If VAR is a property, 
			like in %{var:1}, then the value of that property is returned.
			
		%{?[CONDITION] [SUB_IF_TRUE] ([SUB_IF_FALSE])}
			This is basicly an inline if statement. If CONDITION is true, 
			SUB_IF_TRUE is substituted in, otherwise SUB_IF_FALSE is.
			
		%#
			This is replaced with a $
			This required if you want to use $vars$ in your scripts, because 
			litestep will try to expand them when it reads them in, but we dont
			want them expanded until the script is executed.	
				Example:
				*Script exec !varset mavar "$var$"
				should be
				*Script exec !varset mavar "%#var%#"
				
			This will replace %#var%# with $var$ when the script is called, 
			and then $var$ will be replaced with the current value of $var$.
			
		%=
			This is replaced with a " (double quote)
			
		%-
			This is replaced with a ' (single quote aka. apostrophe)
			
	Variables can be read in from a *mzvarfile. There is also the !mzloadvarfile 
	bang that can be used to load a file on the fly, or refresh variables that 
	might have changed. The mzvarfile has the same layout as a standard litestep 
	file. If you want the variable to be accessible with $var$ as well as %{var},
	add an include to the step.rc in addition to the *mzvarfile line.
	
	One additional note about var files is that you can actually set variable 
	properties directly from the file. These lines cannot be changed with 
	saving however.
		Example:
		
		myVar "abc def" 'ghi'
		myVar:sep token
		myVar:3 '"jkl"'
		
		this would yeild:
		%{myVar}=abc def "jkl"
		%{myVar:line}= "abc def "jkl"" 'ghi'
		
		Note that this would actually cause an unintended result for myVar:line.
		If myVar was saved and then read in again (or if myVar:line:1 was altered,
		thereby reseting myVar's value to hold the first token of myVar:line),
		then it would actually contain abc def , as apposed to abc def "jkl".
		
		
	
================================================================================
	x. Examples
================================================================================
	----------------------------------------------------------------------------
	Example 1:
	----------------------------------------------------------------------------
		##### mzvars.rc:

		vwm shown
		bar shown

		##### :

		*Script start notepad

		;First bangscript
		*Script bang !togglebar
		*Script exec !if ["%{bar}" = "shown"] [!varset bar hidden][!varset bar shown]
		*Script exec !toggleslider [1]
		*Script exec !ToggleShortcutGroup 1
		*Script exec !ToggleCommand 
		*Script exec !SystrayToggle 
		*Script exec !if ["%{vwm}" = "shown"] [!VWMRollup]
		*Script ~bang

		;Second bangscript
		*Script bang !togglevwm
		*Script exec !if ["%{vwm}" = "shown"] [!varset vwm hidden] [!varset vwm shown]
		*Script exec !if ["%{bar}" = "hidden"] [!varset vwm shown]
		*Script exec !if ["%{bar}" <> "hidden"] [!VWMRollup]
		*Script exec !if ["%{bar}" = "hidden"] !togglebar
		*Script ~bang
		
	----------------------------------------------------------------------------
	Example 2:
	----------------------------------------------------------------------------

		

================================================================================
	x. Conversion Guide (to ease the transition to 1.0)
================================================================================
	
	MzScript 1.0 is not syntax compatible with any earlier releases of mzScript. A 
	brief guide to help you migrate code from earlier releases follows. 

		A. In order to load a script file use include (no mzScriptUseStep necessary)
		----------------------------------------------------------------------------
			
		Example:
			include "$configdir$mzscript.rc"


		B. !ifeval and !ifeq are no longer available; conditional syntax has changed
		----------------------------------------------------------------------------

		Use !if with the following syntax :

			!if [conditional] [command_if_true][command_if_false]
			!ifExist mzVar [command_if_true][command_if_false]
			*Script gotoif [conditional] label
			
		Brackets are required around command_if_true even if command_if_false is not present.

			Example 1:
			
				!if ["%{xres}" < "1024"] [!msgbox Resolution in X is too low]

				OR
				
				!if ["%{xres}" >= "1024"] [][!msgbox Resolution in X is too low]
						
			Example 2:
			
				!ifExist mzVar [!msgbox true][!msgbox false]

			Example 3:

				To jump to a specific location defined by a label, based on a 
				condition being true (in this case the label is xresolutionOK).

				*Script gotoif ["%{xres}" >= "1024"] xresolutionOK

		C. There is no support for the old %[variable] syntax
		-----------------------------------------------------

		Convert all such usage to the new syntax %{variable}

		D. You can recursively evalute variables
		----------------------------------------

		You previously had to use loops and temporary variables to do this, but mzScript
		now allows this natively, as seen below.

			Example 1: %{my%{variablename}} will first evaluate %{variablename} and
				then evaluate the 'top level' variable. This means that you can greatly
				increase the amount of code reuse in your theme.
				
		However, there are limitations in combination with substituting $vars$.
			
			Example: %{myMusic}="MusicDir" , %{mzVar}="Music" , $MusicDir$="c:\my music\"
				%#%{my%{mzVar}}%#
					Would be valid, because it would expand like so:
						1 - %#%{my%{mzVar}}$
						2 - %#%{myMusic}$
						3 - %#MusicDir$
						4 - $MusicDir$
						5 - c:\my music\
					
				%{my%#%{mzVar}%#}
					Would not be valid, because it would expand like so:
						1 - %{my%#%{mzVar}%#}
						2 - %{my%#%{mzVar}$}
						3 - %{my%#Music$}
						4 - %{my$Music$}
						5 - (nothing, because there is no my$Music$ variable)
						
		So You must remember that $vars$ are always substituted last.
				

		E. Lists have properties that can be queried
		--------------------------------------------

		With this release, mzScript has properties assigned to lists. You access them
		like an element within the list - with the exception of the separator property,
		all are read-only.

			sep - the separator for the list (can be read as %{list:sep})
					this can also be set with !varset var:sep "separator"
			
			count - the number of list elements (can be read as %{list:count})
			
			file - the file from which the variable was loaded (can be read as %{list:file})
					This will return an empty string if the variable is internal
			
			line - This stores all the text after the variable read in from the varFile.
					It can be read and set, and has its own properties.
					It also uses the special token separator.
						line:count
						line:n			Ex. !varset var:line:3 "20"

		F. Lists now have their own separators
		--------------------------------------

		There is no global separator for lists in this release. The default separator
		remains ":"

		If you set the list separator to "" for any variable, you can find the length of
		that variable via the count property and access/set specific parts of that
		variable as shown below.

			Example 1: for %{mystring} = "litestep"

				!VarSet mystring:sep ""
				; mystringlength would be 8 for the number of letters in %{mystring}
				!VarSet mystringlength "%{mystring:count}"
				; use the below two actions to change from litestep to LiteStep
				!VarSet mystring:1 "L"
				!VarSet mystring:5 "S"

		G. Argument handling is via a new list-style %{args} variable
		-------------------------------------------------------------

		In previous argument-supporting mzScript releases, the arguments were accessed
		with %{\2} or similar references. This is no longer the case. Each script has
		its own %{args} variable that functions like any other list variable in the 1.0
		release.

		Arguments use the special token separator explained in the Variables section.

			Example 1:

				!myfunction "myvalue1" "%{myvariable}"

				Within the code for myfunction, you will then have the following :

					%{args} = "myvalue1" "%{myvariable}"
					%{args:1} = myvalue1
					%{args:2} = %{myvariable}

				You can also check how many arguments there are with args:count.
					
					!if [%{args:count} >= 1] [!dosomething] [!msgbox not enough arguments]

		H. Maths calculations use floating point calculations
		-----------------------------------------------------

		The maths system in mzScript now works out everything using floating point. If
		a calculation results in a float that is directly able to be represented as an
		integer, though, the module will return an integer value. Otherwise, you will
		get back a floating point value and can convert this, with appropriate rounding
		up or down, to an integer using !VarInt <variablename> as shown below.

			Example 1:

				!VarSet number1 "0.5"
				!VarSet number2 "2"
				!VarMul number2 %{number1} ; will return integer 1, not 1.00000
				!VarMul number2 %{number1} ; will return float 0.5, not 1
				!VarInt number2		   ; will return integer 1, not 0 or 0.5

		Note 1) We use doubles rather than integers internally, which greatly increases
			the range of numbers that you can use reliably.

		Note 2) See known issues later in this document for some issues to be aware of
			when using the maths system.
			
		I. New way of reading in and saving variables 
		---------------------------------------------
		when read in, everything after the variable name is stored in var:line. It 
		can be accessed and set like var:sep. Then, when !varset is called, the 
		value AND the line is changed, then when you save, the var:line is saved, 
		not just the value. This actually allows you to work with multitoken 
		variables like labelBorders 1 2 3 4. It just takes a bit of work.
		Also, when you alter var:line it  is retokenized to find the actual value 
		of var. If var:line has no token, then the var becomes empty. 
		If you perform a remove on var:line, the var also becomes empty.
		The main reason i did this is so that saving doesn't just add quotes.
		Instead, it uses what was there when the variable was read in.
			Example:
			(from some mzvarfile)
				myvar "c:\music\" 3
			(after reading in)
				%{myvar}=c:\music\
				%{myvar:line}= "c:\music\" 3
			(then if i do)
				!varset myvar "c:\games\"
			(then this will be true)
				%{myvar}=c:\games\
				%{myvar:line}= "c:\games\" 3
			and of course i can do this:
				!varset myvar:line [ "c:\appz\" 2]
				(then this will be true)
				%{myvar}=c:\appz\
				%{myvar:line}= "c:\appz\" 2
			NOTE:var:line uses the token separator, 
			so if this is true:
				%{var:line}= "c:\games\" 3 5
			so you can do:
				!varset var:line:1 "c:\music\"
			and then this would be true:
				%{var:line}= "c:\music\" 3 5
				%{var}=c:\music\
		
================================================================================	
	x. Known Issues
================================================================================
	1.0 : Mathematical operations will only work for values between +/- 1E10. You 
		can store larger values, but any maths operations will cause an overflow and 
		you will get incorrect values back without any notification of an error.

	1.0 : Very large numbers from mathematical operations will tend to be returned
		as floats because of errors introduced within the calculation. To workaround
		this, a call to !VarInt should be used.

	1.0 : Floating point calculations can see errors introduced that mean that you
		may not always get back the value you expect. For example, applying an overall
		unity multiplication to 5 may return 4.9999 or 5.00001 depending on how many
		calculations were performed before the final value was obtained. More
		calculations presents more opportunity for errors to creep in that can become
		significant. !VarInt may resolve situations like this where an integer value is
		needed.
		
	1.0 : Recursing mzscriptbangs several times, or even just calling mzscriptbangs 
		from other mzscriptbangs from other mzscriptbangs (etc.) will cause litestep to 
		crash because of a stack overflow. As far as I know there is no way to change 
		this, so instead, it must be avoided. (In testing it took upwards near 50 recurses 
		to cause a crash, so a little recursion is ok, but try to avoid it.)
================================================================================
	x. Version History
================================================================================
	mzscript 1.0 (?) / SMaddox
		-Since this is the first non-beta release, I am starting with a fresh slate. I redid 
		the readme, and cleared out old info. For this version, I am also restarting the 
		version history to cut down on file length. Anyone who wants to know previous history 
		can download an older version.

================================================================================
	8. Contact Information
================================================================================
	Feel free to contact me with bug reports and feature suggestions. -SMaddox

	Current maintainer(s): SMaddox
	Authors in order of appearance.

	- Name:    Marcus Westerlund (maze)
	Email:   marcus_AT_cs_DOT_umu_DOT_se
	Website: http://www.acc.umu.se/~macce
	IRC/IM:  ?

	- Name:    Karl-Henrik Henriksson (qwilk)
	Email:   qwilk_AT_desktopian_DOT_org
	Website: http://desktopian.org/
	IRC/IM:  ?

	- Name:    Brian Hartvigsen (Tres`ni)
	Email:   tresni_AT_coreshell_DOT_info
	Website: http://tresni.coreshell.info/
	IRC/IM:  ?

	- Name:    Phil Stopford (LDEPhil)
	Email:   ?
	Website: http://ldex.terica.net
	IRC/IM:  ?

	- Name:    Simon (ilmcuts)
	Email:   ilmcuts_AT_gmx_DOT_net
	Website: none
	IRC/IM:  #litestep, #lsdev on irc.freenode.net
	   
	- Name:    SMaddox
	Email:   SMaddox_AT_gmail_DOT_com
	Website: ?
	IRC/IM:  ?