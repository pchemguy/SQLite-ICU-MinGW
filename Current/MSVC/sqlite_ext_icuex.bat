@echo off

:: https://github.com/pchemguy/SQLiteICUex

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

set "EXIT_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Preparing SQLite ICUex.
echo:

if "%SQLITE_ENABLE_ICUEX%"=="0" (
    echo %INFO% ICUex extension is disabled via SQLITE_ENABLE_ICUEX=0, skipping.
    exit /b 0
)

call :ICUEX_DOWNLOAD    || exit /b !ERRORLEVEL!
call :EXTRA_SRC_THIRD   || exit /b !ERRORLEVEL!

echo:
echo %WARN% Completed SQLite ICUex preparation.
echo --------------------------------------------------------------------------------
echo:

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ ICUEX_DOWNLOAD BEGIN
:: ============================================================================
:ICUEX_DOWNLOAD

setlocal
set "SECTION=ICUEX_DOWNLOAD"

call :MKDIR__DIR "%CACHEDIR%\SQLiteICUex\src"

set "NAME=ICUex"
set "DISTRO=%CACHEDIR%\SQLiteICUex\src\icuex.c"
set "URL=https://raw.githubusercontent.com/pchemguy/SQLiteICUex/refs/heads/main/src/icuex.c"

call "%~dp0download_file.bat" "%NAME%" "%DISTRO%" "%URL%"
set "EXIT_STATUS=%ERRORLEVEL%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ ICUEX_DOWNLOAD END


:: ============================================================================ EXTRA_SRC_THIRD BEGIN
:: ============================================================================
:EXTRA_SRC_THIRD

set "SECTION=EXTRA_SRC_THIRD"

set OPT_XTRA=%OPT_XTRA% -DSQLITE_ENABLE_ICUEX

set SOURCES=^
    "%CACHEDIR%\SQLiteICUex\src\icuex.c"

set MISC_EXT=^
    "icuex.c"

echo %INFO% ========== Copy MISC_EXT ===========
"%TCLSH_CMD%" "%SQLITEDIR%\tool\cp.tcl" %SOURCES% "%TSRC%" || exit /b !ERRORLEVEL!

echo:

echo %INFO% ========== Patch MISC_EXT ===========
cd /d "%TSRC%"
"%TCLSH_CMD%" "%TOOLDIR%\patch_sqlite_misc_autoext.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo:

echo %INFO% ========== Bundle MISC_EXT ===========
"%TCLSH_CMD%" "%TOOLDIR%\bundle_extra_src.tcl" %MISC_EXT% || exit /b !ERRORLEVEL!

echo %INFO% ========== Set EXTRA_SRC for extended SQLite build ===========

set EXTRA_SRC=%EXTRA_SRC% ^
    ""%TSRC%\icuex.c""

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b 0
:: ============================================================================
:: ============================================================================ EXTRA_SRC_THIRD END


:: ============================================================================ MKDIR__DIR BEGIN
:: ============================================================================
:MKDIR__DIR

:: Creates the target directory if the path does not exist.
::
:: %~1 - Full target directory path.
::
:: Accepts an existing path without checking its type.
:: Fails if mkdir fails or the path is still missing.

setlocal
set "SECTION=MKDIR__DIR"
set "EXIT_STATUS=0"

if "%~1"=="" (
    set "EXIT_STATUS=1"
    echo %ERROR% Missing required target directory.
    echo %INFO%  USAGE: call :MKDIR__DIR "{FULL TARGET DIRECTORY PATH}"
    goto :MKDIR__DIR_EXIT
)

set "TARGETDIR=%~1"

if exist "%TARGETDIR%" (
    echo %INFO% "%TARGETDIR%" already exists.
    goto :MKDIR__DIR_EXIT
)

cmd /c mkdir "%TARGETDIR%" || set "EXIT_STATUS=1"
if not exist "%TARGETDIR%"   (set "EXIT_STATUS=1")

if not "%EXIT_STATUS%"=="0" (
    echo %ERROR% Failed to create "%TARGETDIR%"
) else (
    echo %INFO% Created "%TARGETDIR%".
)

:MKDIR__DIR_EXIT

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MKDIR__DIR END


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
