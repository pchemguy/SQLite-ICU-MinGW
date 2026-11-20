@echo off

:: https://github.com/pchemguy/SQLiteRegexpMatches

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

set "ERROR_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Preparing SQLite RegexpMatches.
echo:

if "%SQLITE_ENABLE_REGEXPMATCHES%"=="0" (
    echo %INFO% RegexpMatches extension is disabled via SQLITE_ENABLE_ICUEX=0, skipping.
    exit /b 0
)

call :REGEXPMATCHES_DOWNLOAD    || exit /b !ERRORLEVEL!
call :EXTRA_SRC_THIRD           || exit /b !ERRORLEVEL!

echo:
echo %WARN% Completed SQLite RegexpMatches preparation.
echo --------------------------------------------------------------------------------
echo:

exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ REGEXPMATCHES_DOWNLOAD BEGIN
:: ============================================================================
:REGEXPMATCHES_DOWNLOAD

setlocal
set "SECTION=REGEXPMATCHES_DOWNLOAD"

call :MKDIR__DIR "%CACHEDIR%\SQLiteRegexpMatches\src"

set "NAME=RegexpMatches"
set "DISTRO=%CACHEDIR%\SQLiteRegexpMatches\src\regexpmatches.c"
set "URL=https://raw.githubusercontent.com/pchemguy/SQLiteRegexpMatches/refs/heads/main/src/regexpmatches.c"

call "%~dp0download_file.bat" "%NAME%" "%DISTRO%" "%URL%"
set "ERROR_STATUS=%ERRORLEVEL%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ REGEXPMATCHES_DOWNLOAD END


:: ============================================================================ EXTRA_SRC_THIRD BEGIN
:: ============================================================================
:EXTRA_SRC_THIRD

set "SECTION=EXTRA_SRC_THIRD"

set OPT_XTRA=%OPT_XTRA% -DSQLITE_ENABLE_REGEXPMATCHES

set SOURCES=^
    "%CACHEDIR%\SQLiteRegexpMatches\src\regexpmatches.c"

set MISC_EXT=^
    "regexpmatches.c"

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
    ""%TSRC%\regexpmatches.c""

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
exit /b %ERRORLEVEL%
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
