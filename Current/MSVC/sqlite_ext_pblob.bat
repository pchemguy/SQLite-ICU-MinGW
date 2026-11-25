@echo off

:: https://github.com/pchemguy/SQLitePackedBlob

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

set "EXIT_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Preparing SQLite PBLOB.
echo:

if "%SQLITE_ENABLE_PBLOB%"=="0" (
    echo %INFO% PBLOB extension is disabled via SQLITE_ENABLE_PBLOB=0, skipping.
    exit /b 0
)

call :PBLOB_DOWNLOAD    || exit /b !ERRORLEVEL!
call :FP16_DOWNLOAD     || exit /b !ERRORLEVEL!
call :FP16_EXTRACT      || exit /b !ERRORLEVEL!
call :EXTRA_SRC_THIRD   || exit /b !ERRORLEVEL!

echo:
echo %WARN% Completed SQLite PBLOB preparation.
echo --------------------------------------------------------------------------------
echo:

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ PBLOB_DOWNLOAD BEGIN
:: ============================================================================
:PBLOB_DOWNLOAD

setlocal
set "SECTION=PBLOB_DOWNLOAD"

call :MKDIR__DIR "%CACHEDIR%\SQLitePackedBlob\src" || exit /b !ERRORLEVEL!

set "NAME=PBLOB"
set "DISTRO=%CACHEDIR%\SQLitePackedBlob\src\pblob.c"
set "URL=https://raw.githubusercontent.com/pchemguy/SQLitePackedBlob/refs/heads/main/src/pblob.c"

call "%~dp0download_file.bat" "%NAME%" "%DISTRO%" "%URL%" || exit /b !ERRORLEVEL!

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
endlocal & exit /b 0
:: ============================================================================
:: ============================================================================ PBLOB_DOWNLOAD END


:: ============================================================================ FP16_DOWNLOAD BEGIN
:: ============================================================================
:FP16_DOWNLOAD

setlocal
set "SECTION=FP16_DOWNLOAD"

set "NAME=FP16"
set "DISTRO=%CACHEDIR%\fp16_master.zip"
set "URL=https://github.com/Maratyszcza/FP16/archive/refs/heads/master.zip"

call "%~dp0download_file.bat" "%NAME%" "%DISTRO%" "%URL%"
set "EXIT_STATUS=%ERRORLEVEL%"

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ FP16_DOWNLOAD END


:: ============================================================================ FP16_EXTRACT BEGIN
:: ============================================================================
:FP16_EXTRACT

setlocal
set "SECTION=FP16_EXTRACT"

set "NAME=FP16"
set "FLAG=%THIRDDIR%\FP16-master"
set "SRC=%CACHEDIR%\fp16_master.zip"
set "DST=%THIRDDIR%"

call "%~dp0extract_archive.bat" "%NAME%" "%FLAG%" "%SRC%" "%DST%"
set "EXIT_STATUS=%ERRORLEVEL%"
if not "%EXIT_STATUS%"=="0" goto :FP16_EXTRACT_EXIT

echo %INFO% ========== Copy %NAME% ===========

xcopy /H /Y /B /E /Q "%THIRDDIR%\FP16-master\include\*" "%TSRC%"
set "EXIT_STATUS=%ERRORLEVEL%"

:FP16_EXTRACT_EXIT

echo:
echo %INFO% ~~~~~ %SECTION% ~~~~~
echo:
if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ FP16_EXTRACT END


:: ============================================================================ EXTRA_SRC_THIRD BEGIN
:: ============================================================================
:EXTRA_SRC_THIRD

set "SECTION=EXTRA_SRC_THIRD"

set OPT_XTRA=%OPT_XTRA% -DSQLITE_ENABLE_PBLOB

set SOURCES=^
    "%CACHEDIR%\SQLitePackedBlob\src\pblob.c"

set MISC_EXT=^
    "pblob.c"

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
    ""%TSRC%\pblob.c""

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
