@echo off
:: ============================================================================
:: Builds SQLite using Microsoft Visual C++ Build Tools (MSVC toolset).
:: MSVC toolset can be installed via a
::   - dedicated installer:
::       https://go.microsoft.com/fwlink/?LinkId=691126
::   - Visual Studio installer (including CE):
::       https://visualstudio.microsoft.com/downloads
:: TCL must also be available, as it is required by the building workflow.
::
:: Usage: run the script with "/?" or see :SHOW_HELP at the end.
:: ============================================================================


:: ============================= BEGIN DISPATCHER =============================
if "/%~1/"=="//?/" call :SHOW_HELP && exit /b 0
call :MAIN %*

exit /b 0
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN
SetLocal

set ERROR_STATUS=0

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set DISTRODIR=%BASEDIR%\sqlite
set STDOUTLOG=%BASEDIR%\stdout.log
set STDERRLOG=%BASEDIR%\stderr.log
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul

set SHOW_HELP=0
call :HELP_CHECK %*
if %SHOW_HELP% EQU 1 (exit /b 0)

call :SET_TARGETS %*
(
  call :ICU_OPTIONS
  call :TCL_OPTIONS
  call :ZLIB_OPTIONS
  call :BUILD_OPTIONS
) 1>"%STDOUTLOG%" 2>"%STDERRLOG%"

call :CHECK_PREREQUISITES
if %ERROR_STATUS% NEQ 0 exit /b 1

call :DOWNLOAD_SQLITE
if %ERROR_STATUS% NEQ 0 exit /b 1
call :EXTRACT_SQLITE
if %ERROR_STATUS% NEQ 0 exit /b 1
if not exist "%DISTRODIR%" (
  echo Distro directory does not exists. Exiting
  exit /b 1
)

if %WITH_EXTRA_EXT% EQU 1 (
  if %USE_ZLIB% EQU 1 (
    call :DOWNLOAD_ZLIB
    if %ERROR_STATUS% NEQ 0 exit /b 1
    call :EXTRACT_ZLIB
    if %ERROR_STATUS% NEQ 0 exit /b 1
  )
)

set BUILDDIR=%BASEDIR%\build
if not exist "%BUILDDIR%" mkdir "%BUILDDIR%"
(
  copy /Y "%BASEDIR%\extra\build\*" "%BUILDDIR%"
  copy /Y "%BASEDIR%\extra\*.tcl" "%BASEDIR%"
  xcopy /H /Y /B /E /Q "%BASEDIR%\extra\sqlite" "%BASEDIR%\sqlite"
  cd /d "%BUILDDIR%
  
  pushd .
  call :MAKEFILE_MSC_TOP_AND_DEBUG
  call :MAKEFILE_MSC_ZLIB_STDCALL
)  1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

if %WITH_EXTRA_EXT% EQU 1 (
  call :EXT_ADD_SOURCES_TO_MAKEFILE_MSC
  call :EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
  popd

  ::TSRC
  nmake /nologo /f Makefile.msc .target_source

  set TARGETDIR=%BUILDDIR%\tsrc
  pushd "%BUILDDIR%\tsrc"
  xcopy /H /Y /B /E /Q "%BASEDIR%\extra\*" "%BASEDIR%"
  call :TEST_MAIN_C_SQLITE3_H
  call :EXT_MAIN
  call :EXT_NORMALIZE
  call :EXT_BASE_PATCH CSV
  call :EXT_BASE_PATCH SERIES
  call :EXT_BASE_PATCH UINT
  call :EXT_BASE_PATCH UUID
  call :EXT_BASE_PATCH SHA sha1.c
  call :EXT_BASE_PATCH SHATHREE
  call :EXT_SHA1_SHATHREE
  if %USE_ZLIB%  EQU 1 (call :EXT_ZIPFILE)
  if %USE_SQLAR% EQU 1 (call :EXT_BASE_PATCH SQLAR)
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

popd
if %USE_ZLIB% EQU 1 nmake /nologo /f Makefile.msc zlib 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
echo ===== Making TARGETS ----- %TARGETS% -----
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
set TARGETS=!TARGETS:"=!
set TARGETS=!TARGETS:####=!
if "/##%TARGETS%##/"=="/####/" (
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
if not defined USE_ICU (set USE_ICU=1)
if not %USE_ICU% EQU 1 (exit /b 0)

if /%Platform%/==/x86/ (set "ARCH=") else (set ARCH=64)
for /f "usebackq" %%I in (`where uconv 2^>nul`) do (set UCONV=%%I)
if not "/%UCONV%/"=="//" (
  if not defined ICU_HOME (set ICU_HOME=%UCONV:\bin!ARCH!\uconv.exe=%)
)
if "/%ICU_HOME%/"=="//" (set ICU_HOME=%ProgramFiles%\icu4c)
if not exist "%ICU_HOME%\bin\uconv.exe" (
  echo ICU binaries not found, disabling the ICU extension.
  set USE_ICU=0
  exit /b 0
) else (echo Found ICU binaries.)

set ICUDIR=%ICU_HOME%
set ICUINCDIR=%ICUDIR%\include
set ICULIBDIR=%ICUDIR%\lib%ARCH%
set ICUBINDIR=%ICUDIR%\bin%ARCH%
set INCLUDE=%ICUINCDIR%;%INCLUDE%
set Path=%ICUBINDIR%;%Path%
set LIB=%ICULIBDIR%;%LIB%

exit /b 0


:: ============================================================================
:ZLIB_OPTIONS
if not defined USE_ZLIB set USE_ZLIB=1
:: Could not get static linking to work
set ZLIBLIB=zdll.lib
set ZLIBDIR=%DISTRODIR%\compat\zlib
set ZLIBLOC="-DZLIB_WINAPI -DZLIB_DLL"
:: USE_SQLAR should not be set if is not set
if %USE_ZLIB% EQU 1 if not defined USE_SQLAR set USE_SQLAR=1

exit /b 0


:: ============================================================================
:TCL_OPTIONS
set NO_TCL=1
where tclshz 1>nul 2>nul && set "TCL_OK=1" || set "TCL_OK=0"
if %TCL_OK% EQU 1 exit /b 0

if defined TCL_HOME (
  set TCL_BIN=%TCL_HOME%\bin
) else (
  set TCL_BIN=%ProgramFiles%\TCL\bin
)
if exist "%TCL_BIN%\tclsh.exe" (
  set TCL_OK=1
  set Path=!TCL_BIN!;%Path%
) else (
  set TCL_BIN=
  set TCL_OK=0
)

exit /b 0


:: ============================================================================
:BUILD_OPTIONS
if not defined USE_STDCALL (
  if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (
    set USE_STDCALL=1
  ) else (
    set USE_STDCALL=0
  )
)
set SESSION=1
set RBU=1
set API_ARMOR=1
if not defined SYMBOLS set SYMBOLS=0
if %SYMBOLS% EQU 1 (
  echo SYMBOLS=1 means the DLL is about 50% larger.
) else if %SYMBOLS% EQU 0 (
  echo With SYMBOLS=0 the ImpEx plugin reported an issue with the DLL.
)

set EXT_FEATURE_FLAGS=^
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

if not defined WITH_EXTRA_EXT set WITH_EXTRA_EXT=1
if %WITH_EXTRA_EXT% EQU 1 (
  echo ========== EXTRA EXTENSIONS ARE ENABLED ==========
  echo ============ TEST FUNCTIONS ARE ENABLED ==========
  if %USE_ZLIB% EQU 1 (
    set EXT_FEATURE_FLAGS=^
      -DSQLITE_ENABLE_ZIPFILE ^
      !EXT_FEATURE_FLAGS!
    if %USE_SQLAR% EQU 1 (
      set EXT_FEATURE_FLAGS=^
        -DSQLITE_ENABLE_SQLAR ^
        !EXT_FEATURE_FLAGS!
    )
  )
  set EXT_FEATURE_FLAGS=^
    -DSQLITE_ENABLE_CSV ^
    -DSQLITE_ENABLE_SERIES ^
    -DSQLITE_ENABLE_SHA ^
    -DSQLITE_ENABLE_SHATHREE ^
    -DSQLITE_ENABLE_UINT ^
    -DSQLITE_ENABLE_UUID ^
    !EXT_FEATURE_FLAGS!
) else (
  echo ========== EXTRA EXTENSIONS ARE DISABLED =========
  echo ============ TEST FUNCTIONS ARE DISABLED =========
  set TARGETDIR=%DISTRODIR%\tool
  set FILENAME=mksqlite3c.tcl
  pushd "!TARGETDIR!"
  if exist "!FILENAME!.bak" (
    echo Resetting !FILENAME!
    copy /Y "!FILENAME!.bak" "!FILENAME!"
  )
  popd
)

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

if %ERROR_STATUS% EQU 0 (
  echo ----- Verified  environment -----
) else (
  echo ----- Environment is NOT OK -----
)

exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD_SQLITE
set DISTRO=sqlite.zip
set URL=https://www.sqlite.org/src/zip/sqlite.zip

if not exist "%DISTRO%" (
  echo ===== Downloading current SQLite release =====
  curl %URL% --output "%DISTRO%"
  if %ErrorLevel% EQU 0 (
    echo ----- Downloaded  current SQLite release -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading SQLite distro.
    echo Errod code: !ERROR_STATUS!
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
  tar -xf "%DISTROFILE%"
  if %ErrorLevel% EQU 0 (
    echo ----- Extracted  SQLite distro -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting SQLite distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously extracted SQLite distro =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:DOWNLOAD_ZLIB
set DISTRO=zlib.zip
set URL=https://zlib.net/zlib1211.zip

if not exist "%DISTRO%" (
  echo ===== Downloading zlib =====
  curl %URL% --output "%DISTRO%"
  if %ErrorLevel% EQU 0 (
    echo ----- Downloaded  ZLIB -----
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error downloading zlib distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (
  echo ===== Using previously downloaded zlib =====
)

exit /b %ERROR_STATUS%


:: ============================================================================
:EXTRACT_ZLIB
set DISTROFILE=zlib.zip
set ZLIBDIR=%DISTRODIR%\compat\zlib

if not exist "%ZLIBDIR%\win32" (
  echo ===== Extracting zlib distro =====
  rmdir /S /Q "%ZLIBDIR%" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
  tar -xf "%DISTROFILE%"
  if %ErrorLevel% EQU 0 (
    echo ----- Extracted  zlib distro -----
    mkdir "%DISTRODIR%\compat" 2>nul
    move /Y zlib-* zlib 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
    move /Y zlib "%DISTRODIR%\compat" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
  ) else (
    set ERROR_STATUS=%ErrorLevel%
    echo Error extracting zlib distro.
    echo Errod code: !ERROR_STATUS!
  )
) else (echo ===== Using previously  extracted zlib =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:MAKEFILE_MSC_TOP_AND_DEBUG
set FILENAME=Makefile.msc
if exist "%FILENAME%" (
  nmake /nologo /f "%FILENAME%" clean
  del "%FILENAME%" 2>nul
)
echo ========== Patching "%FILENAME%" ===========
copy /Y "%DISTRODIR%\%FILENAME%" "%BUILDDIR%"
set OLDTEXT=TOP = .
set NEWTEXT=TOP = %DISTRODIR%
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
type "%FILENAME%.debug" >>"%FILENAME%"
echo ---------- Patched  "%FILENAME%" -----------

exit /b 0


:: ============================================================================
:MAKEFILE_MSC_ZLIB_STDCALL
set FILENAME=Makefile.msc
echo ========== Patching "%FILENAME%" ===========
set OLDTEXT=win32\Makefile.msc clean
set NEWTEXT=win32\Makefile.msc LOC=$(ZLIBLOC) clean
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
type "%FILENAME%.debug" >>"%FILENAME%"
ren "%FILENAME%" "%FILENAME%" 

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MAKEFILE_MSC
set TARGETDIR=%BUILDDIR%
set FILENAME=Makefile.msc
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_ADD_SOURCES_TO_MKSQLITE3C_TCL
set TARGETDIR=%DISTRODIR%\tool
set FILENAME=mksqlite3c.tcl
echo ========== Patching "%FILENAME%" ===========
pushd "%TARGETDIR%"
if not exist "%FILENAME%.bak" (
  copy /Y "%FILENAME%" "%FILENAME%.bak"
) else (
  copy /Y "%FILENAME%.bak" "%FILENAME%"
)
popd
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:TEST_MAIN_C_SQLITE3_H
set FILENAME=main.c
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.test" "%TARGETDIR%"
set FILENAME=sqlite3.h
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.test" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_MAIN
set FILENAME=main.c
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.1.ext" "%TARGETDIR%"
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.2.ext" "%TARGETDIR%"

exit /b 0


:: ============================================================================
:EXT_NORMALIZE
set FILENAME=normalize.c
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\replace.tcl" "int main" "int sqlite3_normalize_main" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "CC_" "CCN_" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "TK_" "TKN_" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "aiClass" "aiClassN" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "sqlite3UpperToLower" "sqlite3UpperToLowerN" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "sqlite3CtypeMap" "sqlite3CtypeMapN" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "sqlite3GetToken" "sqlite3GetTokenN" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "IdChar(" "IdCharN(" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "sqlite3I" "sqlite3NI" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "sqlite3T" "sqlite3NT" "%FILENAME%"
tclsh "%BASEDIR%\replace.tcl" "CCN__" "CC__" "%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_SHA1_SHATHREE
set FILENAME=sha1.c
set OLDTEXT=hash_step_vformat
set NEWTEXT=hash_step_vformat_sha1
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set FILENAME=shathree.c
set NEWTEXT=hash_step_vformat_sha3
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_ZIPFILE
set FLAG=SQLITE_ENABLE_ZIPFILE
set FILENAME=zipfile.c
echo ========== Patching "%FILENAME%" ===========
set OLDTEXT=static int zipfileRegister
set NEWTEXT=int zipfileRegister
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#if defined(%FLAG%)\n\n#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
echo. >>"%FILENAME%"
echo #endif /* defined^(%FLAG%^) */ >>"%FILENAME%"

exit /b 0


:: ============================================================================
:EXT_BASE_PATCH
:: Call this sub with two arguments:
::   - %1 - FLAG suffix
::   - %2 - FILENAME (if omitted, use %1.c)
set FLAG=SQLITE_ENABLE_%~1
if "/%~2/"=="//" (set FILENAME=%~1.c) else (set FILENAME=%~2)
echo ========== Patching "%FILENAME%" ===========
if exist "%FILENAME%.ext" (
  tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" .
)
set OLDTEXT=#include ^<sqlite3ext.h^>
set NEWTEXT=#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#if defined(%FLAG%)\n\n#include \"sqlite3ext.h\"
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
echo. >>"%FILENAME%"
echo #endif /* defined^(%FLAG%^) */ >>"%FILENAME%"

exit /b 0


:: ============================================================================
:COPY_BINARIES
echo ========== Copying binaries ===========
set BINDIR=%~dp0bin
if not exist "%BINDIR%" mkdir "%BINDIR%"
del /Q bin\* 2>nul
copy "%BUILDDIR%\sqlite3.dll" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe" copy "%BUILDDIR%\sqlite3.exe" "%BINDIR%"
if %USE_ICU%  EQU 1 copy /Y "%ICUBINDIR%\icu*.dll" "%BINDIR%"
if %USE_ZLIB% EQU 1 copy /Y "%ZLIBDIR%\zlib1.dll"  "%BINDIR%"
echo ---------- Copied  binaries -----------

exit /b 0


:: ============================================================================
:HELP_CHECK
set ARG1=%~1
if "/%~1/"=="//" (
  set SHOW_HELP=0
  exit /b 0
)
set ARG1=%ARG1:/=-%
set ARG1=%ARG1:--=-%
set ARG1=%ARG1:?=h%
set ARG1=%ARG1:~,2%
if /I "/%ARG1%/"=="/-h/" (
  set SHOW_HELP=1
  call :SHOW_HELP
) else (set SHOW_HELP=0)

exit /b 0


:: ============================================================================
:SHOW_HELP
     ::==============================================================================
echo.
echo //================================== USAGE ===================================\\
echo ^|^|                                                                            ^|^|
echo ^|^| This script builds SQLite from standard source release using Microsoft     ^|^|
echo ^|^| Visual C++ Build Tools (MSVC toolset). The script enables all extensions   ^|^|
echo ^|^| integrated into the official SQLite amalgamtion release. The ICU extension ^|^|
echo ^|^| is enabled by default if ICU binaries are available. Additionaly, several  ^|^|
echo ^|^| extension from ext/misc are also integrated by default. If executed from   ^|^|
echo ^|^| an x32 shell, STDCALL convention is activated by default.                  ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^| Prerequisites:                                                             ^|^|
echo ^|^|   - The script must be exectuted from an appropriate (either x32 or x64)   ^|^|
echo ^|^|     Build Tools shell.                                                     ^|^|
echo ^|^|   - Internet connection must be available, unless the distro archives are  ^|^|
echo ^|^|     placed alongside the script.                                           ^|^|
echo ^|^|   - TCL must be available. Either add TCL binary folder to the Path or set ^|^|
echo ^|^|     TCL_HOME environment variable, so that %%TCL_HOME%%\bin\tclsh.exe points ^|^|
echo ^|^|     to tclsh.exe.                                                          ^|^|
echo ^|^|   - ICU binaries are required for ICU enabled build. Either add ICU binary ^|^|
echo ^|^|     folder to the path or set ICU_HOME environment variable to the root of ^|^|
echo ^|^|     ICU, e.g., ICU_HOME=%%ProgramFiles%%\icu4c. If ICU binaries are not      ^|^|
echo ^|^|     found, ICU is disabled.                                                ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^| Usage:                                                                     ^|^|
echo ^|^|   Place this script and the "extra" folder in an empty folder. It will     ^|^|
echo ^|^|   download the current standard SQLite release and zlib sources. If        ^|^|
echo ^|^|   "sqlite.zip" or "zlib.zip" are in the same folder, the script will use   ^|^|
echo ^|^|   them. Make sure that the archives are good, otherwise the script will    ^|^|
echo ^|^|   fail (e.g., if partially downloaded files are found).                    ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^|   Build targets should be provided as one quoted space separated argument  ^|^|
echo ^|^|   or as individual arguments, e.g.,                                        ^|^|
echo ^|^|     SOMEPATH^> sqlite_MSVC_Cpp_Build_Tools.ext.bat_ "sqlite3.c dll"         ^|^|
echo ^|^|     SOMEPATH^> sqlite_MSVC_Cpp_Build_Tools.ext.bat_ sqlite3.c dll           ^|^|
echo ^|^|   If no build targets are provided, the script will print debugging info   ^|^|
echo ^|^|   to the log file.                                                         ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^|   Additional options should be set in advance, e.g.,                       ^|^|
echo ^|^|     SOMEPATH^> set "USE_ICU=0" ^&^& set "USE_ZLIB=1" ^&^& ^<...^>.ext.bat dll     ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^|   Available options (1 - enable, 0 - disable, not defined - default):      ^|^|
echo ^|^|     USE_ICU (defaults to 1) - ICU support.                                 ^|^|
echo ^|^|     SYMBOLS (defaults to 0) - keep symbols in DLL (see printed warnings).  ^|^|
echo ^|^|     WITH_EXTRA_EXT (defaults to 1) - integrate additional extensions.      ^|^|
echo ^|^|     USE_ZLIB (defaults to 1) - ZLIB support (WITH_EXTRA_EXT must be 1).    ^|^|
echo ^|^|     USE_SQLAR (defaults to 1) - SQLAR support (requires ZLIB support).     ^|^|
echo ^|^|     USE_STDCALL (defaults to 1 for x32) - use STDCALL instead of CDECL.    ^|^|
echo \\============================================================================//
echo.

exit /b 0
