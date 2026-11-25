@echo off

::
:: Extracts archive using Windows Tar.
::
:: %~1 - Name.
:: %~2 - Path to a file or directory from the archive.
::       If it already exists on disk, skip extraction.
:: %~3 - Archive path - MUST exist.
:: %~4 - Extraction directory path - MUST exist.
::

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

setlocal EnableExtensions EnableDelayedExpansion

set "EXIT_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Extracting archive.
echo:

if "%~4"=="" (
    set "EXIT_STATUS=1"
    echo %ERROR% Missing required parameters.
    echo %INFO%  USAGE: call extract_archive.bat "NAME" "FLAG" "SRC" "DST"
    goto :EXTRACT_EXIT
)

set "NAME=%~1"
set "FLAG=%~f2"
set "SRC=%~f3"
set "DST=%~f4"
if not defined TAR set "TAR=%SystemRoot%\System32\tar.exe"

if not exist "%SRC%" (
    set "EXIT_STATUS=1"
    echo %ERROR% Archive "%SRC%" not found.
    goto :EXTRACT_EXIT
)

if exist "%SRC%\" (
    set "EXIT_STATUS=1"
    echo %ERROR% Expected an archive file, not a directory: "%SRC%".
    goto :EXTRACT_EXIT
)

if not exist "%DST%\." (
    set "EXIT_STATUS=1"
    echo %ERROR% Directory "%DST%" not found.
    goto :EXTRACT_EXIT
)

if exist "%FLAG%" (
    echo %OKOK% ===== Using previously extracted %NAME% =====
    goto :EXTRACT_EXIT
)

echo %INFO% ===== Extracting %NAME% =====
echo:

"%TAR%" -x -f "%SRC%" -C "%DST%"
set "EXIT_STATUS=%ERRORLEVEL%"
if "%EXIT_STATUS%"=="0" (
    echo %OKOK% Extracted %NAME%.
) else (
    echo %ERROR% Failed to extract %NAME%. Error Code: %EXIT_STATUS%.
)

:EXTRACT_EXIT

echo:
echo %WARN% Completed archive extraction.
echo --------------------------------------------------------------------------------
echo:

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


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
