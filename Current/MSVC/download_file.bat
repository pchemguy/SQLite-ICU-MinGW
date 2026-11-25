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
exit /b 0

:USAGE

echo %ERROR% Usage: "%~nx0" "NAME" "TARGET" "URL"
exit /b 1
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ FETCH BEGIN
:: ============================================================================
:FETCH

set "PART=%TARGET%.part"
set "META=%TARGET%.response.log"
set "HEADER_LOG=%~dpn2.log"
if /i "%HEADER_LOG%"=="%TARGET%" set "HEADER_LOG=%TARGET%.headers.log"
echo %INFO% Downloading "%NAME%" to "%PART%"

:: Write final status and media type from the GET, not a separate HEAD. The
:: trailing semicolon makes bare and parameterized media types comparable.
curl.exe -fL --globoff --retry 3 --dump-header "%HEADER_LOG%" --output "%PART%" --write-out "%%{http_code} %%{content_type};\n" -- "%URL%" >"%META%"
if not "%ERRORLEVEL%"=="0" (
    set "RC=%ERRORLEVEL%"
    echo %ERROR% Download failed with status %ERRORLEVEL%.
    goto :FAILED
)

:: Only accept a full HTTP response (not, for example, unsolicited 206).
set "RC=1"
findstr /b /c:"200 " "%META%" >nul || goto :BAD_RESPONSE
findstr /i /r /b /c:"200 [ 	]*text/html[; 	]" "%META%" >nul
if not "%ERRORLEVEL%"=="1" goto :BAD_RESPONSE

:: REN stays in the same directory and does not overwrite an existing target.
ren "%PART%" "%~nx2"
if not "%ERRORLEVEL%"=="0" (
    set "RC=%ERRORLEVEL%"
    echo %ERROR% Could not publish "%TARGET%".
    goto :FAILED
)
echo %OKOK% Downloaded "%NAME%": "%TARGET%"
exit /b 0

:BAD_RESPONSE

echo %ERROR% Unexpected HTTP status or media type. See "%META%".

:FAILED

if exist "%PART%" if not exist "%PART%\" del /q "%PART%"

if not defined RC (set "RC=1")
exit /b %RC%
:: ============================================================================
:: ============================================================================ FETCH END


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
