@echo off

::
:: Extracts archive using Windows Tar.
::
:: %~1 - Name.
:: %~2 - Flag - file or directory. If exists, use previously extracted files.
:: %~3 - Archive path - MUST exist.
:: %~4 - Extraction directory path - MUST exist.
::

:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

SetLocal EnableExtensions EnableDelayedExpansion

set "ERROR_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Extracting archive.
echo:

if "%~4"=="" (
    set "ERROR_STATUS=1"
    echo %ERROR% Missing required parameters.
    set "CLI=call extract_archive.bat "NAME" "FLAG" "SRC" "DST""
    echo %INFO%  USAGE: !CLI!
    goto :EXTRACT_EXIT
)

set "NAME=%~1"
set "FLAG=%~2"
set "SRC=%~3"
set "DST=%~4"
set "ERROR_STATUS=0"

if not exist "%SRC%" (
    set "ERROR_STATUS=1"
    echo %ERROR% Archive "%SRC%" not found.
    goto :EXTRACT_EXIT
)

if not exist "%DST%" (
    set "ERROR_STATUS=1"
    echo %ERROR% Directory "%DST%" not found.
    goto :EXTRACT_EXIT
)

if not exist "%FLAG%" (
    echo %INFO% ===== Extracting %NAME% =====
    cd /d "%DST%"
    "%TAR%" -xf "%SRC%"
    set "ERROR_STATUS=!ERRORLEVEL!"
    call :COLOR_SCHEME
    if "!ERROR_STATUS!"=="0" (
        echo %OKOK% Extracted %NAME%.
    ) else (
        echo %ERROR% Failed to extract %NAME%. Error Code: !ERROR_STATUS!.
    )
) else (
    echo %OKOK% ===== Using previously extracted %NAME% =====
)

:EXTRACT_EXIT

echo:
echo %WARN% Completed archive extraction.
echo --------------------------------------------------------------------------------
echo:

endlocal && exit /b %ERROR_STATUS%
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
