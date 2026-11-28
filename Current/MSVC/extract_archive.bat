@echo off

::
:: Extracts archive using Windows Tar.
::
:: %~1 - NAME - User-friendly name shown in logging.
:: %~2 - FLAG - Path to a file or directory relative to %~4.
::              If it already exists on disk, skip extraction.
:: %~3 - SRC  - Archive path - MUST exist.
:: %~4 - DST  - Extraction directory path - MUST exist.
::
:: Windows tar directly supports .tar.gz and .zip.
:: Archive content is extracted directly into %~4.
::
:: %~2 FLAG is assumed to not include version suffix even if archive content
:: naming convention uses one. For example, for zlib.tar.gz verion 1.4 expect
::     - "zlib-1.4" - top-level container;
::     - "zlib-1.4/win32/Makefile.msc" - probe inside archive;
::     - "zlib/win32/Makefile.msc" - %~2 FLAG, probe on disk - version suffix
::        is stripped after extraction.
::   
:: The script tests for possible presense of version suffix in top-level path
:: element of archive member corresponding to the on-disk %~2 FLAG, taking into
:: account a special case of possible extension, and derives archive PROBE, e.g.:
::     - "zlib.EXT/win32/Makefile.msc" would yield "zlib*.EXT/win32/Makefile.msc".
::
:: Archive must pass the test with the derived PROBE or fail otherwise.
:: When top-level path element in archive includes version suffix, rename
:: it automaticaly to match the FLAG.
::
:: Use "%DST%/%NAME%_PROCESSING.flag" flag to ensure atomic extraction.

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

setlocal EnableExtensions EnableDelayedExpansion

set "EXIT_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Processing %NAME% archive.
echo:

call :PARSE_ARGS %*

if exist "%FLAG%" if not exist "%PROCESSING%" (
    set "EXIT_STATUS=0"
    echo %OKOK% ===== Using previously extracted %NAME% =====
    goto :EXTRACT_EXIT
)

if not defined TAR set "TAR=%SystemRoot%\System32\tar.exe"
if not exist "%TAR%" (
    set "EXIT_STATUS=1"
    echo %ERROR% Tar not found: %TAR%.
    goto :PARSE_ARGS_EXIT
)

echo %INFO% ===== Extracting %NAME% archive =====
echo:

if exist "%PROCESSING%" (
    echo %WARN% Found "%PROCESSING%" flag. Prior extraction was interrupted. Overwriting.
) else (
    echo: >"%PROCESSING%"
)

"%TAR%" -x -f "%SRC%" -C "%DST%"
set "EXIT_STATUS=%ERRORLEVEL%"
if "%EXIT_STATUS%"=="0" (
    echo %OKOK% Extracted %NAME%.
) else (
    echo %ERROR% Failed to extract %NAME%. Error Code: %EXIT_STATUS%.
)

:EXTRACT_EXIT

echo:
echo %WARN% Completed %NAME% archive extraction.
echo --------------------------------------------------------------------------------
echo:

if not defined EXIT_STATUS (set "EXIT_STATUS=0")
endlocal & exit /b %EXIT_STATUS%
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ PARSE_ARGS BEGIN
:: ============================================================================
:PARSE_ARGS

set "_EXIT_STATUS=0"

set "NAME=%~1"
set "FLAG=%~f2"
set "SRC=%~f3"
set "DST=%~f4"
set "PROCESSING=%DST%/%NAME%_PROCESSING.flag"

if "%~4"=="" (
    set "_EXIT_STATUS=1"
    echo %ERROR% Missing required parameters.
    echo %INFO%  USAGE: call extract_archive.bat "NAME" "FLAG" "SRC" "DST"
    goto :PARSE_ARGS_EXIT
)

if not exist "%SRC%" (
    set "_EXIT_STATUS=1"
    echo %ERROR% Archive "%SRC%" not found.
    goto :PARSE_ARGS_EXIT
)

if exist "%SRC%/" (
    set "_EXIT_STATUS=1"
    echo %ERROR% Expected an archive file, not a directory: "%SRC%".
    goto :PARSE_ARGS_EXIT
)

if not exist "%DST%\." (
    set "_EXIT_STATUS=1"
    echo %ERROR% Ouput directory "%DST%" not found.
    goto :PARSE_ARGS_EXIT
)

:PARSE_ARGS_EXIT

if not defined _EXIT_STATUS (set "_EXIT_STATUS=0")
exit /b %_EXIT_STATUS%
:: ============================================================================
:: ============================================================================ PARSE_ARGS END


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
