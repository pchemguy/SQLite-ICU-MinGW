@echo off
:: ============================================================================
:: Builds SQLite using Microsoft Visual C++ Build Tools (MSVC toolset).
:: MSVC toolset can be installed via a
::   - dedicated installer:
::       https://go.microsoft.com/fwlink/?LinkId=691126
::   - Visual Studio installer (including CE):
::       https://visualstudio.microsoft.com/downloads
:: TCL must also be available, as it is required by the building workflow.
:: ===========================================================================

:: ============================= BEGIN DISPATCHER =============================
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

(
    call :ICU_OPTIONS   || exit /b !ERRORLEVEL!
    call :TCL_OPTIONS   || exit /b !ERRORLEVEL!
    call :ZLIB_OPTIONS  || exit /b !ERRORLEVEL!
    call :BUILD_OPTIONS || exit /b !ERRORLEVEL!
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

call :SQLITE_DOWNLOAD || exit /b %ERRORLEVEL%
call :SQLITE_EXTRACT  || exit /b %ERRORLEVEL%
call :ZLIB_DOWNLOAD   || exit /b %ERRORLEVEL%
call :ZLIB_EXTRACT    || exit /b %ERRORLEVEL%
call :ZLIB_BUILD      || exit /b %ERRORLEVEL%
call :ICU_DOWNLOAD    || exit /b %ERRORLEVEL%
call :ICU_EXTRACT     || exit /b %ERRORLEVEL%
call :ICU_BUILD       || exit /b %ERRORLEVEL%
call :SQLITE_BUILD    || exit /b %ERRORLEVEL%

exit /b 0

set COPY_BINARIES=0
if exist "%BUILDDIR%\sqlite3.dll" (set COPY_BINARIES=1)
if exist "%BUILDDIR%\sqlite3.exe" (set COPY_BINARIES=1)
if %COPY_BINARIES% EQU 1 (call :COLLECT_BINARIES) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

EndLocal

exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:ICU_OPTIONS

rem set "USE_ICU=0"
if not defined USE_ICU (set "USE_ICU=1")
if "/%VSCMD_ARG_TGT_ARCH%/" == "/x64/" (set "ARCHX=64") else (set "ARCHX=")
set "ICUDIR=%DISTRODIR%\compat\icu"
set "ICUINCDIR=!ICUDIR!\include"
set "ICULIBDIR=!ICUDIR!\lib!ARCH!"
set "ICUBINDIR=!ICUDIR!\bin!ARCH!"

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
set "SQLITE_EXTRA=1"
if not defined SQLITE_EXTRA (set "SQLITE_EXTRA=0")

set OPT_XTRA=^
    -DSQLITE_ENABLE_NORMALIZE ^
    -DSQLITE_ENABLE_ICU_COLLATIONS ^
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

if "%SQLITE_EXTRA%"=="1" (
    set OPT_XTRA=%OPT_XTRA%^
        -DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit ^
        -DSQLITE_ENABLE_CSV      ^
        -DSQLITE_ENABLE_DECIMAL  ^
        -DSQLITE_ENABLE_REGEXP   ^
        -DSQLITE_ENABLE_SERIES   ^
        -DSQLITE_ENABLE_SHA      ^
        -DSQLITE_ENABLE_SHATHREE ^
        -DSQLITE_ENABLE_SQLAR    ^
        -DSQLITE_ENABLE_UINT     ^
        -DSQLITE_ENABLE_UUID     
)

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
:SQLITE_BUILD

set "ERROR_STATUS=0"

if not exist "%BUILDDIR%" mkdir "%BUILDDIR%" || exit /b %ERRORLEVEL%
cd /d "%BUILDDIR%" || exit /b %ERRORLEVEL%

:: Instead of patching Makefile.msc to copy extra/misc extension source files or
:: doing so explictly, set SRC12. SRC12 is used for generated Tcl header files
:: when building for WIN10 and USE_STDCALL. This use is irrelevant, so the macro
:: can be safely overwritten.

set SRC12=^
    ""%DISTRODIR%\ext\misc\csv.c""       ^
    ""%DISTRODIR%\ext\misc\decimal.c""   ^
    ""%DISTRODIR%\ext\misc\normalize.c"" ^
    ""%DISTRODIR%\ext\misc\regexp.c""    ^
    ""%DISTRODIR%\ext\misc\series.c""    ^
    ""%DISTRODIR%\ext\misc\sha1.c""      ^
    ""%DISTRODIR%\ext\misc\shathree.c""  ^
    ""%DISTRODIR%\ext\misc\sqlar.c""     ^
    ""%DISTRODIR%\ext\misc\uint.c""      ^
    ""%DISTRODIR%\ext\misc\uuid.c""

:: Initialize SQLite build directory

nmake /nologo "SRC12=%SRC12%" "TOP=%DISTRODIR%" /f "%DISTRODIR%\Makefile.msc" .target_source
set "ERROR_STATUS=%ERRORLEVEL%"
if not "%ERROR_STATUS%"=="0" (exit /b %ERROR_STATUS%)

:: Patch misc extensions as AutoExtensions

cd /d "%BUILDDIR%\tsrc"

set TARGETS=^
    "csv.c"       ^
    "decimal.c"   ^
    "regexp.c"    ^
    "series.c"    ^
    "sha1.c"      ^
    "shathree.c"  ^
    "sqlar.c"     ^
    "uint.c"      ^
    "uuid.c"

tclsh "%BASEDIR%\extra\patch_sqlite_misc_autoext.tcl" %TARGETS%
set "ERROR_STATUS=%ERRORLEVEL%"
if not "%ERROR_STATUS%"=="0" (exit /b %ERROR_STATUS%)

:: Patch normalize.c

set "FILENAME=%BUILDDIR%\tsrc\normalize.c"
echo ========== Patching "%FILENAME%" ===========
tclsh "%BASEDIR%\extra\replace.tcl" "int main" "int sqlite3_normalize_main" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "CC_" "CCN_" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "TK_" "TKN_" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "aiClass" "aiClassN" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "sqlite3UpperToLower" "sqlite3UpperToLowerN" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "sqlite3CtypeMap" "sqlite3CtypeMapN" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "sqlite3GetToken" "sqlite3GetTokenN" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "IdChar(" "IdCharN(" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "sqlite3I" "sqlite3IN" "%FILENAME%"
tclsh "%BASEDIR%\extra\replace.tcl" "sqlite3T" "sqlite3TN" "%FILENAME%"
rem tclsh "%BASEDIR%\extra\replace.tcl" "CCN__" "CC__" "%FILENAME%"

set "ERROR_STATUS=%ERRORLEVEL%"
if not "%ERROR_STATUS%"=="0" (exit /b %ERROR_STATUS%)

:: Make SQLite

cd /d "%BUILDDIR%"

set EXTRA_SRC=^
    ""%BUILDDIR%\tsrc\csv.c""           ^
    ""%BUILDDIR%\tsrc\decimal.c""       ^
    ""%BUILDDIR%\tsrc\normalize.c""     ^
    ""%BUILDDIR%\tsrc\regexp.c""        ^
    ""%BUILDDIR%\tsrc\series.c""        ^
    ""%BUILDDIR%\tsrc\sha1.c""          ^
    ""%BUILDDIR%\tsrc\shathree.c""      ^
    ""%BUILDDIR%\tsrc\sqlar.c""         ^
    ""%BUILDDIR%\tsrc\uint.c""          ^
    ""%BUILDDIR%\tsrc\uuid.c""          ^
    ""%BUILDDIR%\tsrc\misc_ext_init.c""

nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%DISTRODIR%" /f "%DISTRODIR%\Makefile.msc" %*
set "ERROR_STATUS=%ERRORLEVEL%"

exit /b %ERROR_STATUS%


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
