@echo off
:: =============================================================================
:: SCRIPT
::   sqlite_msbuild.bat
::
:: PURPOSE
::   Builds and packages a customized SQLite distribution on Windows using
::   MSVC and SQLite's Makefile.msc.
::
::   The workflow manages SQLite and optional dependency downloads, x86/x64
::   builds, ZLIB integration, ICU integration, stock SQLite ext/misc modules,
::   DLL export/import-library generation, and final artifact collection.
::
::   Conda ICU is staged into the same compatibility-tree include, library,
::   and binary directories used by source-built ICU, so the downstream SQLite
::   build and packaging logic is provider-independent. The active Conda and
::   MSVC environments must target the same architecture.
::
::   Principal outputs are written under:
::
::     out\bin
::     out\include
::     out\lib\import
::     out\lib\static
::
::   Build behavior is controlled primarily by:
::
::     USE_ICU
::     USE_ZLIB
::     SQLITE_EXTRA
::
::   Run from an initialized MSVC x86 or x64 developer command prompt.
::
:: DOCUMENTATION
::   See sqlite_msbuild.md for the complete build-system documentation.
:: =============================================================================

:: ============================================================================ DISPATCHTER BEGIN
:: ============================================================================
call :MAIN %*

exit /b %ERRORLEVEL%
:: ============================================================================  
:: ============================================================================ DISPATCHTER END


:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

SetLocal EnableExtensions EnableDelayedExpansion

set "ERROR_STATUS=0"

call :COLOR_SCHEME

call :CORE_ENV                || exit /b !ERRORLEVEL!

call "%~dp0msbuild_check.bat" || exit /b !ERRORLEVEL!

if "%USE_ICU%"=="1" (
    call :ICU_OPTIONS         || exit /b !ERRORLEVEL!
)

if "%USE_ZLIB%"=="1" (
    call :ZLIB_OPTIONS        || exit /b !ERRORLEVEL!
)

call :BUILD_OPTIONS           || exit /b !ERRORLEVEL!

call :MAKE_DEBUG %*           || exit /b !ERRORLEVEL!

call :SQLITE_DOWNLOAD         || exit /b !ERRORLEVEL!
call :SQLITE_EXTRACT          || exit /b !ERRORLEVEL!

if "%USE_ZLIB%"=="1" (
    call :ZLIB_DOWNLOAD       || exit /b !ERRORLEVEL!
    call :ZLIB_EXTRACT        || exit /b !ERRORLEVEL!
    call :ZLIB_BUILD          || exit /b !ERRORLEVEL!
)

if "%USE_ICU%"=="1" (
    call :ICU_CONDA           || exit /b !ERRORLEVEL!
)

call :SQLITE_BUILD_INIT       || exit /b !ERRORLEVEL!

if "%SQLITE_EXTRA%"=="1" (
    call :EXTRA_SRC_STOCK     || exit /b !ERRORLEVEL!
)

call :SQLITE_BUILD %*         || exit /b !ERRORLEVEL!
call :COLLECT_BINARIES

echo:
echo %OKOK% Completed SQLite built.
echo:

endlocal && exit /b 0
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ MKDIR__DIR BEGIN
:: ============================================================================
:MKDIR__DIR

:: Creates directory or fails with feedback.
::
:: %~1 - Full target directory path.
::
:: Attempts creating target directory if not exist.
:: Fails if creation fails or directory does not exist after creation.

setlocal
set "SECTION=MKDIR__DIR"

if "%~1"=="" (
    set "ERROR_STATUS=1"
    echo %ERROR% Missing required target directory.
    echo %INFO%  USAGE: call :MKDIR__DIR "{FULL TARGET DIRECTORY PATH}"
    goto :MKDIR__DIR_EXIT
)

set "TARGETDIR=%~1"
set "MKDIR_FAILED="
set "ERROR_STATUS=0"

if exist "%TARGETDIR%" (
    echo %INFO% "%TARGETDIR%" already exists.
    goto :MKDIR__DIR_EXIT
)

cmd /c mkdir "%TARGETDIR%" || set "MKDIR_FAILED=1"
if not exist "%TARGETDIR%"   (set "MKDIR_FAILED=1")

if defined MKDIR_FAILED (
    set "ERROR_STATUS=1"
    echo %ERROR% Failed to create "%TARGETDIR%"
    goto :MKDIR__DIR_EXIT
)

echo %INFO% Created "%TARGETDIR%".

:MKDIR__DIR_EXIT

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ MKDIR__DIR END


:: ============================================================================ CORE_ENV BEGIN
:: ============================================================================
:CORE_ENV

set "SECTION=CORE_ENV"

set "TAR=%windir%\System32\tar.exe"

set "TOOLDIR="
if exist "%~dp0patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0"
    set "TOOLDIR=%TOOLDIR:~0,-1%"
) else if exist "%~dp0tool\patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0tool"
) else if exist "%~dp0tools\patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0tools"
) else if exist "%~dp0extra\patch_sqlite_misc_autoext.tcl" (
    set "TOOLDIR=%~dp0extra"
)
if not defined TOOLDIR (
    echo %ERROR% Failed to locate patch_sqlite_misc_autoext.tcl.
    exit /b 1
)
echo %INFO% TOOLDIR: %TOOLDIR%.

cd /d "%TOOLDIR%\.."
set "PROJDIR=%CD%"
echo %INFO% PROJDIR: %PROJDIR%.

set "OPT_XTRA="
if not defined USE_ICU       (set "USE_ICU=1")
if not defined USE_ZLIB      (set "USE_ZLIB=1")
if not defined SQLITE_EXTRA  (set "SQLITE_EXTRA=1")
if not "%SQLITE_EXTRA%"=="0" (set "USE_ZLIB=1")

set "MSG=USE_ICU:       %USE_ICU% - ICU is"
if "%USE_ICU%"=="1" (
    set "MSG=%MSG% ON."
) else (
    set "MSG=%MSG% OFF."
)
echo %MSG%

set "MSG=USE_ZLIB:      %USE_ZLIB% - ZLIB is"
if "%USE_ZLIB%"=="1" (
    set "MSG=%MSG% ON."
) else (
    set "MSG=%MSG% OFF."
)
echo %MSG%

set "MSG=SQLITE_EXTRA:  %SQLITE_EXTRA% - Misc SQLite Extensions Extra is"
if "%SQLITE_EXTRA%"=="1" (
    set "MSG=%MSG% ON."
) else (
    set "MSG=%MSG% OFF."
)
echo %MSG%

set "OUT=%PROJDIR%\out"
call :MKDIR__DIR "%OUT%" || exit /b !ERRORLEVEL!
set "STDOUTLOG=%OUT%\stdout.log"
set "STDERRLOG=%OUT%\stderr.log"
del /Q "%STDOUTLOG%" 2>nul
del /Q "%STDERRLOG%" 2>nul
set "CACHEDIR=%OUT%\cache"
call :MKDIR__DIR "%CACHEDIR%" || exit /b !ERRORLEVEL!
set "SQLITEDIR=%OUT%\sqlite"
call :MKDIR__DIR "%SQLITEDIR%" || exit /b !ERRORLEVEL!
set "THIRDDIR=%SQLITEDIR%\compat"
call :MKDIR__DIR "%THIRDDIR%" || exit /b !ERRORLEVEL!
set "BUILDDIR=%OUT%\build"
call :MKDIR__DIR "%BUILDDIR%" || exit /b !ERRORLEVEL!
set "TSRC=%BUILDDIR%\tsrc"
call :MKDIR__DIR "%TSRC%" || exit /b !ERRORLEVEL!
set "INCDIR=%OUT%\include"
call :MKDIR__DIR "%INCDIR%" || exit /b !ERRORLEVEL!
set "LIBDIR_IMPORT=%OUT%\lib\import"
call :MKDIR__DIR "%LIBDIR_IMPORT%" || exit /b !ERRORLEVEL!
set "LIBDIR_STATIC=%OUT%\lib\static"
call :MKDIR__DIR "%LIBDIR_STATIC%" || exit /b !ERRORLEVEL!
set "BINDIR=%OUT%\bin"
call :MKDIR__DIR "%BINDIR%" || exit /b !ERRORLEVEL!

set "TCLSH_CMD=%BUILDDIR%\jimsh0.exe"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0
:: ============================================================================
:: ============================================================================ CORE_ENV END


:: ============================================================================ ZLIB_OPTIONS BEGIN
:: ============================================================================
:ZLIB_OPTIONS

set "SECTION=ZLIB_OPTIONS"

set "ZLIBDIR=%THIRDDIR%\zlib"
echo %INFO% ZLIBDIR="%ZLIBDIR%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0
:: ============================================================================
:: ============================================================================ ZLIB_OPTIONS END


:: ============================================================================ ICU_OPTIONS BEGIN
:: ============================================================================
:ICU_OPTIONS

set "SECTION=ICU_OPTIONS"

if /I "%VSCMD_ARG_TGT_ARCH%"=="x64" (set "ARCH=64") else (set "ARCH=")
set "ICUDIR=%THIRDDIR%\icu"
set "ICUINCDIR=%ICUDIR%\include"
set "ICULIBDIR=%ICUDIR%\lib%ARCH%"
set "ICUBINDIR=%ICUDIR%\bin%ARCH%"

set OPT_XTRA=%OPT_XTRA% -DSQLITE_ENABLE_ICU_COLLATIONS

echo %INFO% ICUDIR="%ICUDIR%"
echo %INFO% ICUINCDIR="%ICUINCDIR%"
echo %INFO% ICULIBDIR="%ICULIBDIR%"
echo %INFO% ICUBINDIR="%ICUBINDIR%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0
:: ============================================================================
:: ============================================================================ ICU_OPTIONS END


:: ============================================================================ BUILD_OPTIONS BEGIN
:: ============================================================================
:BUILD_OPTIONS

set "SECTION=BUILD_OPTIONS"

set "SQLITE_MAKEFILE=%SQLITEDIR%\Makefile.msc"
set "SESSION=1"
set "RBU=1"
set "API_ARMOR=1"
set "SYMBOLS=0"
rem set "WITHOUT_JIMSH=1"
set "EXTRA_SRC="

set OPT_XTRA=%OPT_XTRA% ^
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
    -DSQLITE_MAX_ATTACHED=100 ^
    -DSQLITE_OMIT_DEPRECATED ^
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1 ^
    -DSQLITE_DEFAULT_SYNCHRONOUS=1 ^
    -DSQLITE_USE_URI=1 ^
    -DSQLITE_SOUNDEX

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0
:: ============================================================================
:: ============================================================================ BUILD_OPTIONS END


:: ============================================================================ MAKE_DEBUG BEGIN
:: ============================================================================
:MAKE_DEBUG

setlocal
set "SECTION=MAKE_DEBUG"

set "TARGET="
if "%~1"=="env"      (set "TARGET=%~1")
if "%~1"=="tcl-test" (set "TARGET=%~1")
if "%~1"=="tcl-env"  (set "TARGET=%~1")

if defined TARGET (
    nmake "TOP=%SQLITEDIR%" /f "%SQLITEDIR%\Makefile.msc" %TARGET%
    exit /b 100
)

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b 0
:: ============================================================================
:: ============================================================================ MAKE_DEBUG END


:: ============================================================================ SQLITE_DOWNLOAD BEGIN
:: ============================================================================
:SQLITE_DOWNLOAD

setlocal DisableDelayedExpansion
set "SECTION=SQLITE_DOWNLOAD"

set "NAME=SQLite"
set "DISTRO=%CACHEDIR%\sqlite.zip"
set "URL=https://sqlite.org/src/zip/sqlite.zip"

set "DOWNLOADER=%~dp0download_file.bat"
call "%%DOWNLOADER%%" "%%NAME%%" "%%DISTRO%%" "%%URL%%" "sqlite/Makefile.msc"
set "ERROR_STATUS=%ERRORLEVEL%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ SQLITE_DOWNLOAD END


:: ============================================================================ SQLITE_EXTRACT BEGIN
:: ============================================================================
:SQLITE_EXTRACT

setlocal DisableDelayedExpansion
set "SECTION=SQLITE_EXTRACT"

set "NAME=SQLite"
set "FLAG=%SQLITEDIR%\.sqlite-extracted"
set "SRC=%CACHEDIR%\sqlite.zip"
set "DST=%OUT%"

call "%~dp0extract_archive.bat" "%NAME%" "%FLAG%" "%SRC%" "%DST%" || exit /b 1
if exist "%FLAG%\" goto :SQLITE_EXTRACT_INCOMPLETE
if not exist "%SQLITE_MAKEFILE%" goto :SQLITE_EXTRACT_INCOMPLETE
if exist "%SQLITE_MAKEFILE%\" goto :SQLITE_EXTRACT_INCOMPLETE
if exist "%FLAG%" goto :SQLITE_EXTRACT_DONE
echo complete >"%FLAG%" || exit /b 1

:SQLITE_EXTRACT_DONE
set "ERROR_STATUS=0"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b %ERROR_STATUS%

:SQLITE_EXTRACT_INCOMPLETE
echo %ERROR% Expected "%SQLITE_MAKEFILE%" after SQLite extraction. Move aside the incomplete tree and retry.
exit /b 1
:: ============================================================================
:: ============================================================================ SQLITE_EXTRACT END


:: ============================================================================ ZLIB_DOWNLOAD BEGIN
:: ============================================================================
:ZLIB_DOWNLOAD

setlocal DisableDelayedExpansion
set "SECTION=ZLIB_DOWNLOAD"

set "NAME=ZLIB"
set "DISTRO=%CACHEDIR%\zlib.tar.gz"
set "MEMBER=zlib-*/win32/Makefile.msc"
if not exist "%DISTRO%" goto :ZLIB_DOWNLOAD_LATEST
"%TAR%" -tf "%DISTRO%" -- "%MEMBER%" >nul
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Invalid cache entry: "%DISTRO%". Move it aside before retrying.
    exit /b 1
)
echo %OKOK% Using previously downloaded ZLIB: "%DISTRO%"
exit /b 0

:ZLIB_DOWNLOAD_LATEST
rem set "URL=https://zlib.net/current/zlib.tar.gz"
set "URL_PREFIX=https://github.com/madler/zlib/releases"

set "URL_LOG=%CACHEDIR%\zlib-release-url.txt"
curl.exe -fsSL -o NUL -w "%%{url_effective}\n" -- "%URL_PREFIX%/latest" >"%URL_LOG%"
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Failed to resolve the latest ZLIB release.
    exit /b 1
)
:: Accept only dotted numeric versions, such as v1.4 or v1.3.1; reject empty components.
set "TAG=https://github[.]com/madler/zlib/releases/tag/v[0-9][0-9.]*[.][0-9][0-9]*"
set "ZLIB_VERSION="
for /f "usebackq tokens=7 delims=/" %%V in (
    `findstr /r /x /c:"%TAG%" "%URL_LOG%" ^| findstr /l /v /c:".."`
) do set "ZLIB_VERSION=%%V"
if not defined ZLIB_VERSION (
    echo %ERROR% Unexpected ZLIB release URL. See "%URL_LOG%".
    exit /b 1
)
set "URL=%URL_PREFIX%/download/%ZLIB_VERSION%/zlib-%ZLIB_VERSION:~1%.tar.gz"

set "DOWNLOADER=%~dp0download_file.bat"
call "%%DOWNLOADER%%" "%%NAME%%" "%%DISTRO%%" "%%URL%%" "%%MEMBER%%"
set "ERROR_STATUS=%ERRORLEVEL%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ ZLIB_DOWNLOAD END


:: ============================================================================ ZLIB_EXTRACT BEGIN
:: ============================================================================
:ZLIB_EXTRACT

setlocal DisableDelayedExpansion
set "SECTION=ZLIB_EXTRACT"

set "NAME=ZLIB"
set "FLAG=%ZLIBDIR%\.zlib-staged"
set "SRC=%CACHEDIR%\zlib.tar.gz"
set "DST=%ZLIBDIR%.stage"
if exist "%ZLIBDIR%" (
    if not exist "%FLAG%" goto :ZLIB_EXTRACT_INCOMPLETE
    if exist "%FLAG%\" goto :ZLIB_EXTRACT_INCOMPLETE
    if not exist "%ZLIBDIR%\win32\Makefile.msc" goto :ZLIB_EXTRACT_INCOMPLETE
    if exist "%ZLIBDIR%\win32\Makefile.msc\" goto :ZLIB_EXTRACT_INCOMPLETE
    echo %OKOK% ===== Using previously extracted ZLIB =====
    exit /b 0
)
mkdir "%DST%" || goto :ZLIB_EXTRACT_FAILED
call "%~dp0extract_archive.bat" "%NAME%" "%FLAG%" "%SRC%" "%DST%" || goto :ZLIB_EXTRACT_FAILED

set "ROOT="
for /f "usebackq eol=| delims=" %%D in (`dir /b /a "%DST%"`) do (
    if defined ROOT goto :ZLIB_EXTRACT_BAD_ROOT
    set "ROOT=%%D"
)
set "VERSION=zlib-[0-9][0-9.]*[.][0-9][0-9]*"
dir /b /a:d "%DST%" | findstr /r /x /c:"%VERSION%" | findstr /l /v /c:".." >nul || goto :ZLIB_EXTRACT_BAD_ROOT
if not exist "%DST%\%ROOT%\win32\Makefile.msc" goto :ZLIB_EXTRACT_BAD_ROOT
if exist "%DST%\%ROOT%\win32\Makefile.msc\" goto :ZLIB_EXTRACT_BAD_ROOT
echo complete >"%DST%\%ROOT%\.zlib-staged" || goto :ZLIB_EXTRACT_FAILED
if exist "%ZLIBDIR%" goto :ZLIB_EXTRACT_INCOMPLETE
move "%DST%\%ROOT%" "%ZLIBDIR%" || goto :ZLIB_EXTRACT_FAILED
if not exist "%FLAG%" goto :ZLIB_EXTRACT_INCOMPLETE
if not exist "%ZLIBDIR%\win32\Makefile.msc" goto :ZLIB_EXTRACT_INCOMPLETE
rd "%DST%" || goto :ZLIB_EXTRACT_FAILED
echo %OKOK% Staged "%ROOT%" in "%ZLIBDIR%".

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b 0

:ZLIB_EXTRACT_BAD_ROOT
echo %ERROR% Expected one versioned zlib directory containing win32\Makefile.msc.
:ZLIB_EXTRACT_FAILED
echo %ERROR% Could not stage ZLIB. Inspect "%DST%" and move it aside before retrying.
exit /b 1

:ZLIB_EXTRACT_INCOMPLETE
echo %ERROR% Incomplete ZLIB tree at "%ZLIBDIR%". Move it aside before retrying.
exit /b 1
:: ============================================================================
:: ============================================================================ ZLIB_EXTRACT END


:: ============================================================================ ZLIB_BUILD BEGIN
:: ============================================================================
:ZLIB_BUILD

setlocal
set "SECTION=ZLIB_BUILD"

echo:
if not exist "%ZLIBDIR%\zlib1.dll" (
    echo %INFO% ===== Building ZLIB =====
    cd /d "%SQLITEDIR%"
    nmake /nologo "TOP=%SQLITEDIR%" "ZLIBLIB=all" /f "%SQLITE_MAKEFILE%" zlib
    set "ERROR_STATUS=!ERRORLEVEL!"
    if "!ERROR_STATUS!"=="0" (
        echo %INFO% ----- Built ZLIB -----
    ) else (
        echo %ERROR% Failed to build ZLIB. Error Code: !ERROR_STATUS!.
    )
) else (
    echo %INFO% ===== Using previously built ZLIB =====
)

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ ZLIB_BUILD END


:: ============================================================================ ICU_CONDA BEGIN
:: ============================================================================
:ICU_CONDA

setlocal DisableDelayedExpansion
set "SECTION=ICU_CONDA"

set "ERROR_STATUS=0"
set "STAGE=%ICUDIR%.stage"
set "ROOT=%STAGE%"
if exist "%ICUDIR%" (
    if not exist "%ICUDIR%\.icu-staged" goto :ICU_CONDA_INCOMPLETE
    if exist "%ICUDIR%\.icu-staged\" goto :ICU_CONDA_INCOMPLETE
    set "ROOT=%ICUDIR%"
    goto :ICU_CONDA_VALIDATE
)
set "PREREQ=%CONDA_PREFIX%\python.exe"
if not exist "%PREREQ%" (
    set "ERROR_STATUS=1"
    echo %ERROR% Conda ICU is selected, but "%PREREQ%" does not exist.
    goto :ICU_CONDA_EXIT
)
set "PREREQ=%CONDA_PREFIX%\Library\bin\icuinfo.exe"
if not exist "%PREREQ%" (
    set "ERROR_STATUS=1"
    echo %ERROR% Conda ICU is selected, but "%PREREQ%" does not exist.
    goto :ICU_CONDA_EXIT
)

mkdir "%STAGE%" || goto :ICU_CONDA_FAILED
mkdir "%STAGE%\lib%ARCH%" || goto :ICU_CONDA_FAILED
mkdir "%STAGE%\bin%ARCH%" || goto :ICU_CONDA_FAILED
xcopy /E /H /I /Y "%CONDA_PREFIX%\Library\include\unicode" "%STAGE%\include\unicode" || goto :ICU_CONDA_FAILED
copy /Y "%CONDA_PREFIX%\Library\lib\icu??.lib" "%STAGE%\lib%ARCH%\" || goto :ICU_CONDA_FAILED
copy /Y "%CONDA_PREFIX%\Library\bin\icu*.dll" "%STAGE%\bin%ARCH%\" || goto :ICU_CONDA_FAILED
copy /Y "%CONDA_PREFIX%\Library\bin\icuinfo.exe" "%STAGE%\bin%ARCH%\" || goto :ICU_CONDA_FAILED
for %%F in ("%STAGE%\bin%ARCH%\icu??.dll" "%STAGE%\bin%ARCH%\icutest*.dll") do (
    del /q "%%~fF"
    if exist "%%~fF" goto :ICU_CONDA_FAILED
)

:ICU_CONDA_VALIDATE
set "COMMON="
for /f "usebackq delims=" %%F in (`dir /b /a:-d "%ROOT%\bin%ARCH%\icuuc*.dll" 2^>nul ^| findstr /i /r /x "icuuc[0-9][0-9]*\.dll"`) do (
    if defined COMMON goto :ICU_CONDA_BAD_VERSION
    set "COMMON=%%F"
)
if not defined COMMON goto :ICU_CONDA_BAD_VERSION
:: All runtime components must have the same version suffix as the common DLL.
set "SUFFIX=%COMMON:~5%"
for %%F in ("%ROOT%\include\unicode\utypes.h" "%ROOT%\include\unicode\ucol.h"
            "%ROOT%\include\unicode\uregex.h" "%ROOT%\include\unicode\ustring.h"
            "%ROOT%\lib%ARCH%\icudt.lib" "%ROOT%\lib%ARCH%\icuuc.lib" "%ROOT%\lib%ARCH%\icuin.lib"
            "%ROOT%\bin%ARCH%\icuinfo.exe" "%ROOT%\bin%ARCH%\%COMMON%"
            "%ROOT%\bin%ARCH%\icuin%SUFFIX%" "%ROOT%\bin%ARCH%\icudt%SUFFIX%") do (
    set "REQUIRED=%%~fF"
    if not exist "%%~fF" goto :ICU_CONDA_BAD_FILE
    if exist "%%~fF\" goto :ICU_CONDA_BAD_FILE
    if "%%~zF"=="0" goto :ICU_CONDA_BAD_FILE
)
if "%ROOT%"=="%ICUDIR%" (
    echo %OKOK% Using previously staged ICU: "%ICUDIR%\bin%ARCH%\%COMMON%".
    goto :ICU_CONDA_EXIT
)
echo complete >"%STAGE%\.icu-staged" || goto :ICU_CONDA_FAILED
ren "%STAGE%" "icu" || goto :ICU_CONDA_FAILED
echo %OKOK% Staged ICU from "%CONDA_PREFIX%" in "%ICUDIR%".
goto :ICU_CONDA_EXIT

:ICU_CONDA_BAD_VERSION
echo %ERROR% Expected one versioned ICU common DLL in "%ROOT%\bin%ARCH%".
goto :ICU_CONDA_INVALID
:ICU_CONDA_BAD_FILE
echo %ERROR% Missing or invalid ICU file: "%REQUIRED%".
:ICU_CONDA_INVALID
if "%ROOT%"=="%ICUDIR%" goto :ICU_CONDA_INCOMPLETE
:ICU_CONDA_FAILED
echo %ERROR% Could not stage ICU. Inspect "%STAGE%" and move it aside before retrying.
exit /b 1

:ICU_CONDA_INCOMPLETE
echo %ERROR% Incomplete ICU tree at "%ICUDIR%". Move it aside before retrying.
exit /b 1

:ICU_CONDA_EXIT

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ ICU_CONDA END


:: ============================================================================ SQLITE_BUILD_INIT BEGIN
:: ============================================================================
:SQLITE_BUILD_INIT

set "SECTION=SQLITE_BUILD_INIT"

cd /d "%BUILDDIR%" || exit /b !ERRORLEVEL!

nmake /nologo "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" .target_source
set "ERROR_STATUS=%ERRORLEVEL%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ SQLITE_BUILD_INIT END


:: ============================================================================ EXTRA_SRC_STOCK BEGIN
:: ============================================================================
:EXTRA_SRC_STOCK

set "SECTION=EXTRA_SRC_STOCK"

set OPT_XTRA=%OPT_XTRA%^
    -DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit ^
    -DSQLITE_ENABLE_COMPRESS ^
    -DSQLITE_ENABLE_CSV      ^
    -DSQLITE_ENABLE_DECIMAL  ^
    -DSQLITE_ENABLE_FUZZER   ^
    -DSQLITE_ENABLE_NOOP     ^
    -DSQLITE_ENABLE_PREFIXES ^
    -DSQLITE_ENABLE_REGEXP   ^
    -DSQLITE_ENABLE_REMEMBER ^
    -DSQLITE_ENABLE_ROT      ^
    -DSQLITE_ENABLE_SERIES   ^
    -DSQLITE_ENABLE_SHA      ^
    -DSQLITE_ENABLE_SHATHREE ^
    -DSQLITE_ENABLE_SQLAR    ^
    -DSQLITE_ENABLE_UINT     ^
    -DSQLITE_ENABLE_UUID

cd /d "%SQLITEDIR%\ext\misc"

set MISC_EXT=^
    "compress.c"  ^
    "csv.c"       ^
    "decimal.c"   ^
    "fuzzer.c"    ^
    "noop.c"      ^
    "prefixes.c"  ^
    "regexp.c"    ^
    "remember.c"  ^
    "rot13.c"     ^
    "series.c"    ^
    "sha1.c"      ^
    "shathree.c"  ^
    "sqlar.c"     ^
    "uint.c"      ^
    "uuid.c"

echo %INFO% ========== Copy MISC_EXT ===========
"%TCLSH_CMD%" "%SQLITEDIR%\tool\cp.tcl" %MISC_EXT% "%TSRC%" || exit /b !ERRORLEVEL!

echo:
echo %INFO% ========== Patch MISC_EXT ===========
echo:
cd /d "%TSRC%"
"%TCLSH_CMD%" "%TOOLDIR%\patch_sqlite_misc_autoext.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo:
echo %INFO% ========== Bundle MISC_EXT ===========
echo:
"%TCLSH_CMD%" "%TOOLDIR%\bundle_extra_src.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo:
echo %INFO% ========== Set EXTRA_SRC for extended SQLite build ===========
echo:

set EXTRA_SRC=%EXTRA_SRC% ^
    ""%TSRC%\compress.c""      ^
    ""%TSRC%\csv.c""           ^
    ""%TSRC%\decimal.c""       ^
    ""%TSRC%\fuzzer.c""        ^
    ""%TSRC%\noop.c""          ^
    ""%TSRC%\prefixes.c""      ^
    ""%TSRC%\regexp.c""        ^
    ""%TSRC%\remember.c""      ^
    ""%TSRC%\rot13.c""         ^
    ""%TSRC%\series.c""        ^
    ""%TSRC%\sha1.c""          ^
    ""%TSRC%\shathree.c""      ^
    ""%TSRC%\sqlar.c""         ^
    ""%TSRC%\uint.c""          ^
    ""%TSRC%\uuid.c""          ^
    ""%TSRC%\misc_ext_init.c""

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERRORLEVEL%
:: ============================================================================
:: ============================================================================ EXTRA_SRC_STOCK END


:: ============================================================================ SQLITE_BUILD BEGIN
:: ============================================================================
:SQLITE_BUILD

set "SECTION=SQLITE_BUILD"

cd /d "%BUILDDIR%" || exit /b !ERRORLEVEL!

nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" sqlite3.def
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Error creating sqlite3.def
    exit /b %ERRORLEVEL%
)

:: ----- Replace sqlite3.def -----

echo EXPORTS >"%BUILDDIR%\sqlite3.def"

set "PATTERN=^[ ]*[0-9][0-9]*[ ]*[A-Za-z0-9][A-Za-z0-9]*_"
for /f "usebackq tokens=2 delims=@ " %%A in (
    `dumpbin /linkermember:2 libsqlite3.lib ^| findstr /R /C:"%PATTERN%"`
) do (
    echo %%A
) >>"%BUILDDIR%\exports.txt"
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Error updating sqlite3.def
    exit /b %ERRORLEVEL%
)
type "%BUILDDIR%\exports.txt" | sort >>"%BUILDDIR%\sqlite3.def"
del /Q "%BUILDDIR%\exports.txt"

nmake /nologo "EXTRA_SRC=%EXTRA_SRC%" "TOP=%SQLITEDIR%" /f "%SQLITE_MAKEFILE%" %*
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Error building SQLite.
    exit /b %ERRORLEVEL%
)

:: ----- Replace sqlite3.lib -----

lib /def:"%BUILDDIR%\sqlite3.def" /out:"%BUILDDIR%\sqlite3.lib" /machine:%VSCMD_ARG_TGT_ARCH%
if not "%ERRORLEVEL%"=="0" (
    echo %ERROR% Error updating static SQLite lib.
    exit /b %ERRORLEVEL%
)

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERRORLEVEL%
:: ============================================================================
:: ============================================================================ SQLITE_BUILD END


:: ============================================================================ COLLECT_BINARIES BEGIN
:: ============================================================================
:COLLECT_BINARIES

set "SECTION=COLLECT_BINARIES"

echo ========== Collecting binaries ===========
del /Q "%BINDIR%\*" 2>nul
if exist "%BUILDDIR%\sqlite3.dll"    copy /Y "%BUILDDIR%\sqlite3.dll"    "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.exe"    copy /Y "%BUILDDIR%\sqlite3.exe"    "%BINDIR%"
if exist "%BUILDDIR%\sqlite3.def"    copy /Y "%BUILDDIR%\sqlite3.def"    "%LIBDIR_IMPORT%"
if exist "%BUILDDIR%\sqlite3.lib"    copy /Y "%BUILDDIR%\sqlite3.lib"    "%LIBDIR_IMPORT%"
if exist "%BUILDDIR%\libsqlite3.lib" copy /Y "%BUILDDIR%\libsqlite3.lib" "%LIBDIR_STATIC%"
copy /Y "%BUILDDIR%\sqlite3*.h" "%INCDIR%"
if "%USE_ICU%"=="1" (copy /Y "%ICUBINDIR%\icu*.dll" "%BINDIR%")
if "%USE_ZLIB%"=="1" (if exist "%ZLIBDIR%\zlib1.dll" copy /Y "%ZLIBDIR%\zlib1.dll" "%BINDIR%")
echo ---------- Copied  binaries -----------

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0
:: ============================================================================
:: ============================================================================ COLLECT_BINARIES  END


:: ============================================================================ COLOR_SCHEME BEGIN
:: ============================================================================
:COLOR_SCHEME
:: ---------------------------------------------------------------------
:: Color Scheme (with NOCOLOR fallback)
:: ---------------------------------------------------------------------

if defined _ARG_NOCOLOR set "NOCOLOR=1"
if defined NO_COLOR set "NOCOLOR=1"
if defined NOCOLOR (
    set  "INFO= [INFO]  "
    set  "OKOK= [-OK-]  "
    set  "WARN= [WARN]  "
    set "ERROR= [ERROR] "
) else (
    set  "INFO=[100;92m [INFO]  [0m"
    set  "OKOK=[103;94m [-OK-]  [0m"
    set  "WARN=[106;35m [WARN]  [0m"
    set "ERROR=[105;34m [ERROR] [0m"
)

exit /b 0
:: ============================================================================
:: ============================================================================ COLOR_SCHEME END
