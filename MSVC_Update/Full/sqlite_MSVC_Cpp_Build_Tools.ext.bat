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
:: ===========================================================================



:: ============================= BEGIN DISPATCHER =============================
if "/%~1/"=="//?/" call :SHOW_HELP && exit /b 0
call :MAIN %*

exit /b 0
:: ============================= END   DISPATCHER =============================


:: ================================ BEGIN MAIN ================================
:MAIN

SetLocal EnableExtensions EnableDelayedExpansion

set "ERROR_STATUS=0"

set "TAR=%windir%\System32\tar.exe"
set "BASEDIR=%~dp0"
set "BASEDIR=%BASEDIR:~0,-1%"
set "DISTRODIR=%BASEDIR%\sqlite"
set "SQLITE_MAKEFILE=%DISTRODIR%\Makefile.msc"
set "TOP=%DISTRODIR%"
set "BUILDDIR=%BASEDIR%\build"
set "STDOUTLOG=%BASEDIR%\stdout.log"
set "STDERRLOG=%BASEDIR%\stderr.log"
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul

set "SHOW_HELP=0"
call :HELP_CHECK %*
if "%SHOW_HELP%"=="1" (exit /b 0)

(
    call :ICU_OPTIONS
    call :TCL_OPTIONS
    call :ZLIB_OPTIONS
    call :BUILD_OPTIONS
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

call :SQLITE_DOWNLOAD
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :SQLITE_EXTRACT
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :ZLIB_DOWNLOAD
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :ZLIB_EXTRACT
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :ZLIB_BUILD
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :ICU_DOWNLOAD
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :ICU_EXTRACT
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :ICU_BUILD
if not "%ERROR_STATUS%"=="0" (exit /b 1)

call :SQLITE_BUILD_INIT
if not "%ERROR_STATUS%"=="0" (exit /b 1)

exit /b 0

(
  copy /Y "%BASEDIR%\extra\build\*" "%BUILDDIR%"
  copy /Y "%BASEDIR%\extra\*.tcl" "%BASEDIR%"
  xcopy /H /Y /B /E /Q "%BASEDIR%\extra\sqlite" "%BASEDIR%\sqlite"
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
  call :EXT_REGEXP
  call :EXT_SHA1
  call :EXT_BASE_PATCH CSV
  call :EXT_BASE_PATCH SERIES
  call :EXT_BASE_PATCH FILEIO
  call :EXT_BASE_PATCH UINT
  call :EXT_BASE_PATCH UUID
  call :EXT_BASE_PATCH SHATHREE
  if %USE_ZLIB%  EQU 1 (call :EXT_ZIPFILE)
  if %USE_SQLAR% EQU 1 (call :EXT_BASE_PATCH SQLAR)
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

popd
echo ===== Making TARGETS ----- %TARGETS% -----
nmake /nologo /f Makefile.msc sqlite3.c 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

:: There is a problem with integration of fileio properly resulting in
:: '_stat' related errors. But bypassing the amalgmation generation tool
:: works.
if %WITH_EXTRA_EXT% EQU 1 (
  call :EXT_WINDIRENT
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

nmake /nologo /f Makefile.msc %TARGETS% 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
cd ..
rem Leave BUILDDIR

set COPY_BINARIES=0
if exist "%BUILDDIR%\sqlite3.dll" (set COPY_BINARIES=1)
if exist "%BUILDDIR%\sqlite3.exe" (set COPY_BINARIES=1)
if %COPY_BINARIES% EQU 1 (call :COLLECT_BINARIES) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

EndLocal

exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:ICU_OPTIONS

if not defined USE_ICU (set "USE_ICU=1")
if "%USE_ICU%"=="1" (
    if "/%VSCMD_ARG_TGT_ARCH%/" == "/x64/" (set "ARCHX=64") else (set "ARCHX=")
    set "ICUDIR=%~dp0sqlite\compat\icu"
    set "ICUINCDIR=!ICUDIR!\include"
    set "ICULIBDIR=!ICUDIR!\lib!ARCH!"
    set "ICUBINDIR=!ICUDIR!\bin!ARCH!"
)

exit /b 0


:: ============================================================================
:ZLIB_OPTIONS

if not defined USE_ZLIB (set "USE_ZLIB=1")
if not defined USE_SQLAR (set "USE_SQLAR=1")

exit /b 0


:: ============================================================================
:TCL_OPTIONS

set "TCL_OK=0"
where tclsh 1>nul 2>nul && exit /b 0 || set "TCL_OK=1"
if not defined TCL_HOME (set "TCL_HOME=%ProgramFiles%\TCL")
if exist "%TCL_HOME%\bin\tclsh.exe" (set "TCL_OK=0")

if "%TCL_OK%"=="0" (
    set "Path=%TCL_HOME%\bin;%Path%"
    echo TCL found.
) else (
    echo TCL not found.
)

exit /b %TCL_OK%


:: ============================================================================
:BUILD_OPTIONS

set "SESSION=1"
set "RBU=1"
set "API_ARMOR=1"
set "SYMBOLS=0"
set "NO_TCL=1"

set OPT_XTRA=^
    -DSQLITE_ENABLE_NORMALIZE ^
    -DSQLITE_ENABLE_FTS4=1 ^
    -DSQLITE_ENABLE_FTS3_PARENTHESIS ^
    -DSQLITE_ENABLE_FTS3_TOKENIZER ^
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS=1 ^
    -DSQLITE_ENABLE_OFFSET_SQL_FUNC=1 ^
    -DSQLITE_ENABLE_QPSG ^
    -DSQLITE_ENABLE_STAT4 ^
    -DSQLITE_DQS=0 ^
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS ^
    -DSQLITE_MAX_EXPR_DEPTH=100 ^
    -DSQLITE_OMIT_DEPRECATED ^
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1 ^
    -DSQLITE_DEFAULT_SYNCHRONOUS=1 ^
    -DSQLITE_USE_URI=1 ^
    -DSQLITE_SOUNDEX


exit /b 0


:: ============================================================================
:CHECK_PREREQUISITES

echo ===== Verifying environment =====

if "/%VisualStudioVersion%/"=="//" (
    echo %%VisualStudioVersion%% is not set. Run this script from an MSVC shell.
  set "ERROR_STATUS=1"
)   else (
  echo VisualStudioVersion=%VisualStudioVersion%
)

if "/%VSINSTALLDIR%/"=="//" (
    echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
  set "ERROR_STATUS=1"
) else (
    echo VSINSTALLDIR=%VSINSTALLDIR%
)

if "/%VCINSTALLDIR%/"=="//" (
    echo %%VSINSTALLDIR%% is not set. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo VCINSTALLDIR=%VCINSTALLDIR%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where cl.exe 2^>nul`) do (
    if "/!CommandLocation!/"=="//" (set "CommandLocation=%%~I")
)
if "/%CommandLocation%/"=="//" (
    echo cl.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo CL_EXE=%CommandLocation%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where nmake.exe 2^>nul`) do (
    if "/!CommandLocation!/"=="//" (set "CommandLocation=%%~i")
)
if "/%CommandLocation%/"=="//" (
    echo nmake.exe is not found. Run this script from an MSVC shell.
    set "ERROR_STATUS=1"
) else (
    echo NMAKE_EXE=%CommandLocation%
)

set "CommandLocation="
for /f "usebackq delims=" %%I in (`where tclsh.exe 2^>nul`) do (
    if "/!CommandLocation!/"=="//" (set "CommandLocation=%%I")
)
if "/%CommandLocation%/"=="//" (
    echo tclsh.exe is not found. TCL is required and must be in the path.
    set "ERROR_STATUS=1"
) else (
    echo TCLSH_EXE=%CommandLocation%
)

if "%ERROR_STATUS%"=="0" (
    echo ----- Verified  environment -----
) else (
    echo ----- Environment is NOT OK -----
)

exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_DOWNLOAD

set "DISTRO=sqlite.zip"
set "URL=https://sqlite.org/src/zip/sqlite.zip"

if not exist "%BASEDIR%\%DISTRO%" (
    echo ===== Downloading current SQLite release =====
    curl.exe -fL --retry 3 --output "%BASEDIR%\%DISTRO%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Downloaded current SQLite release -----
    ) else (
        echo Error downloading SQLite.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously downloaded SQLite =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_EXTRACT

set "DISTROFILE=sqlite.zip"

if not exist "%DISTRODIR%\Makefile.msc" (
    echo ===== Extracting SQLite =====
    "%TAR%" -xf "%BASEDIR%\%DISTROFILE%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Extracted SQLite -----
    ) else (
        echo Error extracting SQLite.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously extracted SQLite =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_DOWNLOAD

set "DISTRO=zlib.tar.gz"
set "URL=https://zlib.net/current/zlib.tar.gz"

if not exist "%BASEDIR%\%DISTRO%" (
    echo ===== Downloading ZLIB =====
    curl.exe -fL --retry 3 --output "%BASEDIR%\%DISTRO%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Downloaded ZLIB -----
    ) else (
        echo Error downloading ZLIB.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously downloaded ZLIB =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_EXTRACT

set "DISTROFILE=zlib.tar.gz"
set "ZLIBDIR=%DISTRODIR%\compat\zlib"

if not exist "%ZLIBDIR%\win32\Makefile.msc" (
    echo ===== Extracting ZLIB =====
    cmd /c rmdir /S /Q "%ZLIBDIR%" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
    "%TAR%" -xf "%BASEDIR%\%DISTROFILE%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Extracted ZLIB -----
        mkdir "%DISTRODIR%\compat" 2>nul
        move /Y "%BASEDIR%\zlib-*" "%BASEDIR%\zlib" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
        move /Y "%BASEDIR%\zlib" "%DISTRODIR%\compat" 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"
    ) else (
        echo Error extracting ZLIB.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously extracted ZLIB =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:ZLIB_BUILD

if not exist "%ZLIBDIR%\zlib1.dll" (
    echo ===== Building ZLIB =====
    cd /d "%DISTRODIR%"
    nmake /nologo "TOP=%DISTRODIR%" "ZLIBLIB=all" /f "%SQLITE_MAKEFILE%" zlib
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Built ZLIB -----
    ) else (
        echo Error building ZLIB.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously built ZLIB =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_DOWNLOAD

set "DISTRO=icu4c-X-sources.zip"
set "URL="

set "ICU_RELEASE_META=%BASEDIR%\icu_release_meta.json"
if not exist "%ICU_RELEASE_META%" (
    curl.exe -s https://api.github.com/repos/unicode-org/icu/releases/latest >"%ICU_RELEASE_META%"
)
set "ERROR_STATUS=%ERRORLEVEL%"
if "!ERROR_STATUS!"=="0" (
    echo ----- Downloaded ICU release meta -----
) else (
    del /Y /Q "%ICU_RELEASE_META%"
    echo Error downloading ICU release meta.
    exit /b %ERROR_STATUS%
)

for /f "usebackq tokens=2" %%I in (`findstr /R /C:"browser_download_url.*icu4c-.*-sources.zip" "%ICU_RELEASE_META%"`) do (
    set "BUFFER=%%~I"
    if "!BUFFER:~-3!"=="zip" (set "URL=!BUFFER!")
    set "BUFFER="
)
if defined URL (
    echo {INFO} ICU release URL: %URL%
) else (
    set "ERROR_STATUS=1"
    echo {ERROR} Failed to locate ICU release URL.
    exit /b %ERROR_STATUS%
)

if not exist "%BASEDIR%\%DISTRO%" (
    echo ===== Downloading ICU =====
    curl.exe -fL --retry 3 --output "%BASEDIR%\%DISTRO%" %URL%
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Downloaded ICU -----
    ) else (
        echo Error downloading ICU.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously downloaded ICU =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_EXTRACT

set "DISTROFILE=icu4c-X-sources.zip"
set "ICUDIR=%DISTRODIR%\compat\icu"

if not exist "%ICUDIR%\source\allinone\allinone.sln" (
    echo ===== Extracting ICU =====
    cd /d "%DISTRODIR%\compat"
    "%TAR%" -xf "%BASEDIR%\%DISTROFILE%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Extracted ICU -----
    ) else (
        echo Error extracting ICU.
        echo Errod code: !ERROR_STATUS!
    )
) else (echo ===== Using previously extracted ICU =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:ICU_BUILD

if not exist "%ICUDIR%\bin%ARCHX%\icuinfo.exe" (
    echo ===== Building ICU =====
    cd /d "%ICUDIR%"
    msbuild "%ICUDIR%\source\allinone\allinone.sln" /m /p:Configuration=Release /p:SkipUWP=true
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo ----- Built ICU -----
    ) else (
        echo Error building ICU.
        echo Errod code: !ERROR_STATUS!
        if exist "%ICUDIR%\bin%ARCHX%\icuinfo.exe" (
           echo ----- Built ICU -----
           set "ERROR_STATUS=0"
        )
    )
) else (echo ===== Using previously built ICU =====)

exit /b %ERROR_STATUS%


:: ============================================================================
:SQLITE_BUILD_INIT

set "ERROR_STATUS=0"

if not exist "%BUILDDIR%" mkdir "%BUILDDIR%" || exit /b %ERRORLEVEL%
cd /d "%BUILDDIR%" || exit /b %ERRORLEVEL%

:: Instead of patching Makefile.msc to copy extra/misc extension source files or
:: doing so explictly, set SRC12. SRC12 is used for generated Tcl header files
:: when building for WIN10 and USE_STDCALL. This use is irrelevant, so the macro
:: can be safely overwritten.

set SRC12=^
    ""%DISTRODIR%\ext\misc\windirent.h"" ^
    ""%DISTRODIR%\ext\misc\csv.c""       ^
    ""%DISTRODIR%\ext\misc\regexp.c""    ^
    ""%DISTRODIR%\ext\misc\mmapwarm.c""  ^
    ""%DISTRODIR%\ext\misc\normalize.c"" ^
    ""%DISTRODIR%\ext\misc\series.c""    ^
    ""%DISTRODIR%\ext\misc\sha1.c""      ^
    ""%DISTRODIR%\ext\misc\shathree.c""  ^
    ""%DISTRODIR%\ext\misc\uint.c""      ^
    ""%DISTRODIR%\ext\misc\uuid.c""      ^
    ""%DISTRODIR%\ext\misc\zipfile.c""   ^
    ""%DISTRODIR%\ext\misc\sqlar.c"" 


nmake /nologo "SRC12=%SRC12%" "TOP=%DISTRODIR%" /f "%DISTRODIR%\Makefile.msc" .target_source
set "ERROR_STATUS=!ERRORLEVEL!"

exit /b %ERROR_STATUS%


:: ============================================================================
:EXT_ADD_SOURCES_TO_MAKEFILE_MSC
set TARGETDIR=%BUILDDIR%
set FILENAME=Makefile.msc
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\addlines.tcl" "%FILENAME%" "%FILENAME%.ext" "%TARGETDIR%"
ren "%FILENAME%" "%FILENAME%" 

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
:EXT_SHA1
set FILENAME=sha1.c
set OLDTEXT=hash_step_vformat
set NEWTEXT=hash_step_vformat_sha1
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
call :EXT_BASE_PATCH SHA sha1.c

exit /b 0


:: ============================================================================
:EXT_REGEXP
set FILENAME=regexp.c
set OLDTEXT=#include ^<string.h^>
set NEWTEXT=#include ^<sqlite3ext.h^>
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
set OLDTEXT=#include \"sqlite3ext.h\"
set NEWTEXT=#include ^<string.h^>
tclsh "%BASEDIR%\replace.tcl" "%OLDTEXT%" "%NEWTEXT%" "%FILENAME%"
call :EXT_BASE_PATCH REGEXP

exit /b 0


:: ============================================================================
:EXT_WINDIRENT
if %USE_LIBSHELL% EQU 0 (
  copy tsrc\test_windirent.c .
  copy tsrc\test_windirent.h .
  copy tsrc\fileio.c .
  set FILENAME=test_windirent.c
  echo ========== Patching "!FILENAME!" ===========
  tclsh "%BASEDIR%\expandinclude.tcl" "!FILENAME!" "test_windirent.h" .
  (
    echo #include "test_windirent.c"
    echo #include "fileio.c"
  ) >>sqlite3.c
  tclsh "%BASEDIR%\expandinclude.tcl" "sqlite3.c" "test_windirent.c" .
  tclsh "%BASEDIR%\expandinclude.tcl" "sqlite3.c" "fileio.c" .
)

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
:COLLECT_BINARIES
echo ========== Collecting binaries ===========
set BINDIR=%~dp0bin
if not exist "%BINDIR%" mkdir "%BINDIR%"
del /Q bin\* 2>nul
if exist "%BUILDDIR%\sqlite3.dll" move "%BUILDDIR%\sqlite3.dll" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe" move "%BUILDDIR%\sqlite3.exe" "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.def" move "%BUILDDIR%\sqlite3.def" "%BINDIR%"
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
echo ^|^|     ICU, e.g., ICU_HOME=%%ProgramFiles%%\icu4c (spaces in Path are not       ^|^|
echo ^|^|     allowed). If ICU binaries are not found, ICU is disabled.              ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^| Usage:                                                                     ^|^|
echo ^|^|   Place this script and the "extra" folder in an empty folder (no spaces   ^|^|
echo ^|^|   in path). It will download the current standard SQLite release and zlib  ^|^|
echo ^|^|   sources. If "sqlite.zip" or "zlib.zip" are in the same folder, the       ^|^|
echo ^|^|   script will use them. Make sure that the archives are good, otherwise    ^|^|
echo ^|^|   the script will fail (e.g., if partially downloaded files are found).    ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^|   Because some of the extra extensions are included in the shell, extra    ^|^|
echo ^|^|   extension must be disabled when building the shell (WITH_EXTRA_EXT=0).   ^|^|
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
echo ^|^|                                                                            ^|^|
echo ^|^|     Presently, USE_ZLIB/USE_SQLAR should not be used. Either all extras    ^|^|
echo ^|^|     should be activated or none; otherwise, build process may fail.        ^|^|
echo ^|^|                                                                            ^|^|
echo ^|^|   Build shell:                                                             ^|^|
echo ^|^|   set WITH_EXTRA_EXT=0 ^&^& sqlite_MSVC_Cpp_Build_Tools.ext.bat sqlite3.exe  ^|^|
echo ^|^|   Build dll with all extras and symbols:                                   ^|^|
echo ^|^|   set SYMBOLS=1 ^&^& sqlite_MSVC_Cpp_Build_Tools.ext.bat dll                 ^|^|
echo ^|^|                                                                            ^|^|
echo \\============================================================================//
echo.
            
exit /b 0
