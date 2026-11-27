@echo off

::
:: Downloads a missing file via cURL. An existing target file is reused as is.
::
:: Arguments:
::     %1 - Name (logging label).
::     %2 - Full download path.
::     %3 - Download URL.
::
:: Examples:
::     set "NAME=SQLite"
::     set "DISTRO=%~dp0sqlite.zip"
::     set "URL=https://sqlite.org/src/zip/sqlite.zip"
::
::     call "%~dp0download_file.bat" "%NAME%" "%DISTRO%" "%URL%"


:: ============================================================================ MAIN BEGIN
:: ============================================================================
:MAIN

setlocal EnableExtensions EnableDelayedExpansion
call :COLOR_SCHEME

set "NAME=%~1"
set "TARGET=%~f2"
set "URL=%~3"
if not defined NAME goto :USAGE
if "%~2"=="" goto :USAGE
if not defined URL goto :USAGE
if exist "%TARGET%\" (
    echo %ERROR% Expected a file, not a directory: "%TARGET%"
    exit /b 1
)

if not exist "%TARGET%" goto :FETCH
echo %OKOK% Using previously downloaded "%NAME%": "%TARGET%"
endlocal & exit /b 0

:USAGE

echo %ERROR% Usage: "%~nx0" "NAME" "TARGET" "URL"
endlocal & exit /b 1
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ FETCH BEGIN
:: ============================================================================
:FETCH

set "PART=%TARGET%.part"
set "HEADER_LOG=%~dpf2.log"

echo %INFO% Downloading "%NAME%" to "%PART%"

:: Clear any earlier headers in case curl fails before receiving a response.

if exist "%HEADER_LOG%" del /q "%HEADER_LOG%" || (
    set "RC=1"
    echo %ERROR% Could not delete header log "%HEADER_LOG%".
    goto :FAILED
)

:: Keep HTTP error headers so the response log includes the final status.

curl.exe -L --globoff --retry 3 --dump-header "%HEADER_LOG%" --output "%PART%" -- "%URL%"
set "RC=%ERRORLEVEL%"


if exist "%PART%" if not exist "%PART%\" del /q "%PART%"

if not defined RC (set "RC=1")
exit /b %RC%
:: ============================================================================
:: ============================================================================ FETCH END


:: ============================================================================ PARSE_HEADERS BEGIN
:: ============================================================================
:PARSE_HEADERS

setlocal
set "RC=0"

set "HEADER_LOG=%~1"

set "HTTP_CODE="
set "CONTENT_TYPE="

for /f "usebackq tokens=1,2 delims=:; " %%S in ("%HEADER_LOG%") do (
    set "TYP=%%~S"
    set "VAL=%%~T"
    if "!TYP:~0,5!"=="HTTP/" (
        set "HTTP_CODE=!VAL!"
        set "CONTENT_TYPE="
    ) else if /i "!TYP!"=="Content-Type" (
        set "CONTENT_TYPE=!VAL!"
    )
)

set "MSG="
if not "%HTTP_CODE%"=="200" (
    set "MSG=%ERROR% HTTP response code: %HTTP_CODE%. Expected: 200."
) else if not defined CONTENT_TYPE (
    set "MSG=%ERROR% Failed to extract Content-Type from HTTP response."
) else if /i "%CONTENT_TYPE%"=="text/html" (
    set "MSG=%ERROR% HTTP response Content-Type: %CONTENT_TYPE%. Expected NOT text/html."
)

if defined MSG (
    set "RC=1"
) else (
    set "RC=0"
    set "MSG=%INFO% Download response is OK. HTTP response code %HTTP_CODE% and Content-Type: %CONTENT_TYPE%."
)

echo %MSG%

if not defined RC (set "RC=1")
endlocal & exit /b %RC%
:: ============================================================================
:: ============================================================================ PARSE_HEADERS END


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
