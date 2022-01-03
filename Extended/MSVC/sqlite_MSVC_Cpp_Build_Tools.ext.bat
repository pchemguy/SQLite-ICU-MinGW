@echo off
:: ============================================================================
:: Builds SQLite using Microsoft Visual C++ Build Tools (MSVC toolset).
:: MSVC toolset can be installed via a
::   - dedicated installer:
::       https://go.microsoft.com/fwlink/?LinkId=691126
::   - Visual Studio installer (including CE):
::       https://visualstudio.microsoft.com/downloads
:: TCL must also be available, as it is required by the building workflow.
:: ============================================================================


:: ============================= BEGIN DISPATCHER =============================
call :MAIN %*
exit /b 0
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN
SetLocal

set ERROR_STATUS=0

set STDOUTLOG=%~dp0stdout.log
set STDERRLOG=%~dp0stderr.log

(
  call :SET_TARGETS %*
  call :BUILD_OPTIONS
  call :ICU_OPTIONS
  call :TCL_OPTIONS 
) 1>"%STDOUTLOG%" 2>"%STDERRLOG%"

call :CHECK_PREREQUISITES
if %ERROR_STATUS%==1 exit /b 1

set DISTRODIR=%~dp0sqlite
call :DOWNLOAD_SQLITE
if %ERROR_STATUS%==1 exit /b 1
call :EXTRACT_SQLITE
if %ERROR_STATUS%==1 exit /b 1
if not exist "%DISTRODIR%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

set BUILDDIR=%~dp0build
if not exist "%BUILDDIR%" mkdir "%BUILDDIR%"

(call :GENERATE_SPLITLINE_BAT) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Failed to generate "splitline.bat"
  echo Errod code: !ERROR_STATUS!
  exit /b !ERROR_STATUS!
)

rem Enter BUILDDIR
cd /d "%BUILDDIR%" 2>nul
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Cannot enter directory "%BUILDDIR%"
  echo Errod code: !ERROR_STATUS!
  exit /b !ERROR_STATUS!
)

if exist "Makefile.msc" (
  nmake /nologo /f Makefile.msc clean
  del Makefile.msc 2>nul
)
(call :PATCH_MAKEFILE_MSC) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
if %ErrorLevel% NEQ 0 (
  set ERROR_STATUS=%ErrorLevel%
  echo Make file patch error.
  echo Errod code: !ERROR_STATUS!
  exit /b !ERROR_STATUS!
)

(call :GENERATE_ADDLINES_TCL) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

pushd .
(
 call :EXT_ADD_SOURCES_TO_MAKEFILE_MSC
 call :EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
popd

::TSRC
nmake /nologo /f Makefile.msc .target_source 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

pushd .
(
 xcopy /H /Y /B /E /Q "%~dp0extra\*" "%~dp0"
 call :EXT_PATCH_MAIN_C
 call :EXT_PATCH_CSV_C
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
popd

nmake /nologo /f Makefile.msc %TARGETS% 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
cd ..
rem Leave BUILDDIR

if exist "%BUILDDIR%\sqlite3.dll" (call :COPY_BINARIES) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

EndLocal
exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:SET_TARGETS
echo ===== Setting targets =====
set TARGETS=####%*
set TARGETS=%TARGETS:"=%
set TARGETS=%TARGETS:####=%
echo on
@if "/##%TARGETS%##/"=="/####/" (
  echo.
  echo WARNING: no targets have been specified. Expected
  echo a space-separated list of targets as the first quoted
  echo script parameter. Nmake will produce debug output only.
  pause
  set TARGETS=echoconfig
)
@echo off
echo ----- Set     targets -----

exit /b 0


:: ============================================================================
:ICU_OPTIONS
:: In VBA6, it might be necessary to load individual libraries explicitly in the
:: correct order (dependencies must be loaded before the depending libraries.
set USE_ICU=1
if %USE_ICU%==1 (
  if /%Platform%/==/x86/ (
    set ARCH=
  ) else (
    set ARCH=64
  )
  set ICUDIR=%ProgramFiles%\icu4c
  set ICUDIR=!ICUDIR: =!
  set ICUINCDIR=!ICUDIR!\include
  set ICULIBDIR=!ICUDIR!\lib!ARCH!
  set ICUBINDIR=!ICUDIR!\bin!ARCH!
)

set INCLUDE=%ICUINCDIR%;%INCLUDE%
set Path=%ICUBINDIR%;%Path%
set LIB=%ICULIBDIR%;%LIB%

set USE_ZLIB=0
if %USE_ZLIB%==1 (
  set ZLIBDIR=..\zlib
)

exit /b 0


:: ============================================================================
:TCL_OPTIONS
set Path=%ProgramFiles%\TCL\bin;%Path%

exit /b 0


:: ============================================================================
:BUILD_OPTIONS
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (
  set USE_STDCALL=1
) else (
  set USE_STDCALL=0
)
set SESSION=1
set RBU=1
set NO_TCL=1

set EXT_FEATURE_FLAGS=^
-DSQLITE_ENABLE_CSV ^
-DSQLITE_ENABLE_NORMALIZE ^
-DSQLITE_ENABLE_FTS3_PARENTHESIS ^
-DSQLITE_ENABLE_FTS3_TOKENIZER ^
-DSQLITE_ENABLE_FTS4=1 ^
-DSQLITE_ENABLE_FTS5=1 ^
-DSQLITE_SYSTEM_MALLOC=1 ^
-DSQLITE_OMIT_LOCALTIME=1 ^
-DSQLITE_DQS=0 ^
-DSQLITE_LIKE_DOESNT_MATCH_BLOBS ^
-DSQLITE_MAX_EXPR_DEPTH=100 ^
-DSQLITE_OMIT_DEPRECATED ^
-DSQLITE_DEFAULT_FOREIGN_KEYS=1 ^
-DSQLITE_DEFAULT_SYNCHRONOUS=1 ^
-DSQLITE_ENABLE_EXPLAIN_COMMENTS ^
-DSQLITE_ENABLE_OFFSET_SQL_FUNC=1 ^
-DSQLITE_ENABLE_QPSG ^
-DSQLITE_ENABLE_STMTVTAB ^
-DSQLITE_ENABLE_STAT4 ^
-DSQLITE_ENABLE_SESSION ^
-DSQLITE_ENABLE_PREUPDATE_HOOK ^
-DSQLITE_USE_URI=1 ^
-DSQLITE_SOUNDEX

exit /b 0


:: ============================================================================
:CHECK_PREREQUISITES
echo ===== Verifying environment =====
if "/%VisualStudioVersion%/"=="//" (
  echo %%VisualStudioVersion%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VisualStudioVersion=%VisualStudioVersion%
)
if "/%VSINSTALLDIR%/"=="//" (
  echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VSINSTALLDIR=%VSINSTALLDIR%
)
if "/%VCINSTALLDIR%/"=="//" (
  echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo VCINSTALLDIR=%VCINSTALLDIR%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where cl.exe 2^>nul`) do (
  if "/!CommandLocation!/"=="//" (
    set CommandLocation=%%i
  )
)
if "/%CommandLocation%/"=="//" (
  echo cl.exe is not found. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo CL_EXE=%CommandLocation%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where nmake.exe 2^>nul`) do (
  if "/!CommandLocation!/"=="//" (
    set CommandLocation=%%i
  )
)
if "/%CommandLocation%/"=="//" (
  echo nmake.exe is not found. Run this script from an MSVC shell.
  set ERROR_STATUS=1
) else (
  echo NMAKE_EXE=%CommandLocation%
)

set CommandLocation=
for /f "Usebackq delims=" %%i in (`where tclsh.exe 2^>nul`) do (
  if "/!CommandLocation!/"=="//" (
    set CommandLocation=%%i
  )
)
if "/%CommandLocation%/"=="//" (
  echo tclsh.exe is not found. TCL is required and must be in the path.
  set ERROR_STATUS=1
) else (
  echo TCLSH_EXE=%CommandLocation%
)

if %ERROR_STATUS%==0 (
  echo ----- Verified  environment -----
) else (
  echo ----- Environment is NOT OK -----
)

exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD_SQLITE
set DISTRO=sqlite.zip
set URL=https://www.sqlite.org/src/zip/sqlite.zip

if not exist %DISTRO% (
  echo ===== Downloading current SQLite release =====
  curl %URL% --output "%DISTRO%"
  :: set PSCMD=Invoke-WebRequest -Uri '%URL%' -OutFile '%DISTRO%'
  :: PowerShell -Command "& {!PSCMD!}"
  if %ErrorLevel% NEQ 0 (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading SQLite distro.
    echo Errod code: !ERROR_STATUS!
  ) else (
    echo ----- Downloaded  current SQLite release -----
  )
) else (
  echo ===== Using previously downloaded SQLite distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRACT_SQLITE
set DISTROFILE=sqlite.zip

if not exist "%DISTRODIR%" (
  echo ===== Extracting SQLite distro =====
  tar -xf %DISTROFILE%
  if %ErrorLevel% NEQ 0 (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting SQLite distro.
    echo Errod code: !ERROR_STATUS!
  ) else (
    echo ----- Extracted  SQLite distro -----
  )
) else (
  echo ===== Using previously extracted SQLite distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:GENERATE_SPLITLINE_BAT
:: Generates "splitline.bat" script.
:: "splitline.bat" takes one quoted argument, splits it on the
:: space character, and outputs each part on a separate line.
echo ========== Generating "splitline.bat" ==========
set OUTPUT=splitline.bat
(
  echo @echo off
) 1>%OUTPUT%
(
  echo.
  echo set ARGS=%%~1
  echo :NEXT_ARG
  echo   for /F "tokens=1* delims= " %%%%G in ^("%%ARGS%%"^) do ^(
  echo     echo %%%%G
  echo     set ARGS=%%%%H
  echo   ^)
  echo if defined ARGS goto NEXT_ARG
) 1>>%OUTPUT%
echo ---------- Generated  "splitline.bat" ----------

exit /b 0


:: ============================================================================
:GENERATE_ADDLINES_TCL
:: Generates "addlines.tcl" script.
:: "addlines.tcl" takes three arguments: name of the source file, name of the
:: file with new lines, starting with a unique line in the source file, after
:: which the new lines are added, and the destination dir.
echo ========== Generating "addlines.tcl" ==========
set OUTPUT="addlines.tcl"
(
  echo #^^!/usr/bin/tclsh
) 1>"%~dp0%OUTPUT%"
(
  echo. 
  echo set SourceName [lindex $argv 0]
  echo set NewLinesName [lindex $argv 1]
  echo cd [lindex $argv 2]
  echo. 
  echo set fd [open $SourceName rb]
  echo set Source [read -nonewline $fd]
  echo close $fd
  echo. 
  echo set fd [open $NewLinesName rb]
  echo set NewLines [split [read -nonewline $fd] "\n"]
  echo close $fd
  echo. 
  echo set AddLinesAfter [lindex $NewLines 0]
  echo set Patched  [string map -nocase [list $AddLinesAfter [join $NewLines "\n"]] $Source]
  echo. 
  echo set fd [open "${SourceName}.tmp" wb]
  echo puts $fd $Patched
  echo close $fd
  echo. 
  echo file rename -force "${SourceName}.tmp" "${SourceName}"
) 1>>"%~dp0%OUTPUT%"
echo ---------- Generated  "addlines.tcl" ----------

exit /b 0


:: ============================================================================
:PATCH_MAKEFILE_MSC
set FILENAME=Makefile.msc
echo ========== Patching "%FILENAME%" ===========
del "%FILENAME%" 1>nul 2>nul
copy /Y "%DISTRODIR%\%FILENAME%" "%FILENAME%" 1>nul
set OUTPUT=Makefile.tcl
del "%OUTPUT%" 1>nul 2>nul

set TARGETDIR=%BUILDDIR%
set TARGETDIR=%TARGETDIR:\=/%
(
  echo set fd [open "%TARGETDIR%/%FILENAME%" rb]                     
  echo set orig [read -nonewline $fd]                      
  echo close $fd                                           
  echo.                                                     
  echo set match {TOP = .}                                 
  echo set replacement {TOP = %DISTRODIR%}                               
  echo regsub $match $orig $replacement patched            
  echo.                                                     
  echo set fd [open "%TARGETDIR%/%FILENAME%.tmp" wb]                 
  echo puts $fd $patched                                   
  echo close $fd                                           
) 1>>%OUTPUT%
tclsh "%OUTPUT%"
del "%OUTPUT%" 2>nul
move /Y "%FILENAME%.tmp" "%FILENAME%"

set OUTPUT=%FILENAME%
set "TAB=	"
(
  echo.
  echo echoconfig:
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo REQ_FEATURE_FLAGS
  echo %TAB%@..\splitline.bat "$(REQ_FEATURE_FLAGS)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo OPT_FEATURE_FLAGS
  echo %TAB%@..\splitline.bat "$(OPT_FEATURE_FLAGS)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo EXT_FEATURE_FLAGS
  echo %TAB%@..\splitline.bat "$(EXT_FEATURE_FLAGS)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo TCC
  echo %TAB%@..\splitline.bat "$(TCC)"
  echo %TAB%@echo --------------------------------
  echo %TAB%@echo USE_STDCALL=$^(USE_STDCALL^)
  echo %TAB%@echo USE_ZLIB=$^(USE_ZLIB^)
  echo %TAB%@echo USE_ICU=$^(USE_ICU^)
  echo %TAB%@echo FOR_WIN10=$^(FOR_WIN10^)
  echo %TAB%@echo DEBUG=$^(DEBUG^)
  echo %TAB%@echo SESSION=$^(SESSION^)
  echo %TAB%@echo RBU=$^(RBU^)
  echo %TAB%@echo ICUDIR=$^(ICUDIR^)
  echo %TAB%@echo ICUINCDIR=$^(ICUINCDIR^)
  echo %TAB%@echo ICULIBDIR=$^(ICULIBDIR^)
  echo %TAB%@echo ZLIBDIR=$^(ZLIBDIR^)
) 1>>%OUTPUT%
echo ---------- Patched  "%FILENAME%" -----------

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MAKEFILE_MSC
set FILENAME=Makefile.msc
set OUTPUT=Makefile.tcl
del "%OUTPUT%" 1>nul 2>nul

set TARGETDIR=%BUILDDIR%
set TARGETDIR=%TARGETDIR:\=/%
(
  echo #^^!/usr/bin/tclsh
  echo. 
  echo set fd [open "%FILENAME%" rb]
  echo set Source [read -nonewline $fd]
  echo close $fd
  echo. 
  echo set NewCs {
  echo   "  $(TOP)\\ext\\misc\\json1.c \\"
  echo   "  $(TOP)\\ext\\misc\\csv.c \\"
  echo }
  echo set AddCsAfter [lindex $NewCs 0]
  echo set Patched  [string map -nocase [list $AddCsAfter [join $NewCs "\n"]] $Source]
  echo. 
  echo set fd [open "%FILENAME%.tmp" wb]
  echo puts $fd $Patched
  echo close $fd
) 1>>%OUTPUT%
tclsh "%OUTPUT%"
del "%OUTPUT%" 2>nul
move /Y "%FILENAME%.tmp" "%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
set TARGETDIR=%DISTRODIR%\tool
cd /d "%TARGETDIR%"
set FILENAME=mksqlite3c.tcl
set OUTPUT=%FILENAME%.tcl
if not exist %FILENAME%.bak (copy %FILENAME% %FILENAME%.bak)
del "%OUTPUT%" 1>nul 2>nul

(
  echo #^^!/usr/bin/tclsh
  echo. 
  echo set fd [open "%FILENAME%.bak" rb]
  echo set Source [read -nonewline $fd]
  echo close $fd
  echo. 
  echo set NewCs {
  echo   "   json1.c"
  echo   "   csv.c"
  echo }
  echo set AddCsAfter [lindex $NewCs 0]
  echo set Patched  [string map -nocase [list $AddCsAfter [join $NewCs "\n"]] $Source]
  echo. 
  echo set fd [open "%FILENAME%.tmp" wb]
  echo puts $fd $Patched
  echo close $fd
) 1>>%OUTPUT%
tclsh "%OUTPUT%"
del "%OUTPUT%" 2>nul
move /Y "%FILENAME%.tmp" "%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_PATCH_MAIN_C
set TARGETDIR=%BUILDDIR%\tsrc
cd /d "%TARGETDIR%"
set FILENAME=main.c
set OUTPUT=%FILENAME%.tcl
if not exist %FILENAME%.bak (copy %FILENAME% %FILENAME%.bak)
del "%OUTPUT%" 1>nul 2>nul

(
  echo #^^!/usr/bin/tclsh
  echo. 
  echo set fd [open "%FILENAME%.bak" rb]
  echo set Source [read -nonewline $fd]
  echo close $fd
  echo. 
  echo set NewCs {
  echo   "  sqlite3Json1Init,"
  echo   "#endif"
  echo   "#ifdef SQLITE_ENABLE_CSV"
  echo   "  sqlite3CsvInit,"
  echo }
  echo set AddCsAfter [lindex $NewCs 0]
  echo set NewCs1 {
  echo   "int sqlite3Json1Init(sqlite3*);"
  echo   "#endif"
  echo   "#ifdef SQLITE_ENABLE_CSV"
  echo   "int sqlite3CsvInit(sqlite3*);"
  echo }
  echo set AddCsAfter1 [lindex $NewCs1 0]
  echo.
  echo set replacements [list \
  echo   $AddCsAfter [join $NewCs "\n"] \
  echo   $AddCsAfter1 [join $NewCs1 "\n"] \
  echo ]
  echo set Patched [string map -nocase $replacements $Source]
  echo. 
  echo set fd [open "%FILENAME%.tmp" wb]
  echo puts $fd $Patched
  echo close $fd
) 1>>%OUTPUT%
tclsh "%OUTPUT%"
::del "%OUTPUT%" 2>nul
move /Y "%FILENAME%.tmp" "%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_PATCH_CSV_C
set TARGETDIR=%BUILDDIR%\tsrc
cd /d "%TARGETDIR%"
set FILENAME=csv.c
if not exist "%FILENAME%.bak" (copy "%FILENAME%" "%FILENAME%.bak")
copy /Y "%FILENAME%.bak" "%FILENAME%"
tclsh "%~dp0addlines.tcl" "%FILENAME%" "%FILENAME%.init" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:COPY_BINARIES
echo ========== Copying binaries ===========
set BINDIR=%~dp0bin
if not exist "%BINDIR%" mkdir "%BINDIR%"
del bin\*.dll 2>nul
copy "%BUILDDIR%\sqlite3.dll" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe" copy "%BUILDDIR%\sqlite3.exe" "%BINDIR%"
if exist "%ICUBINDIR%\icuinfo.exe" copy "%ICUBINDIR%\icu*.dll" "%BINDIR%"
echo ---------- Copied  binaries -----------

exit /b 0
