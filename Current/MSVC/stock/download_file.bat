@echo off

::
:: Downloads file via cURL.
::
:: Arguments:
::     %1 - Name (logging label).
::     %2 - Full download path.
::     %~3 - Download URL.
::
:: Examples:
::     set "NAME=SQLite"
::     set "DISTRO=%~dp0sqlite.zip"
::     set "URL=https://sqlite.org/src/zip/sqlite.zip"
::     
::     call "%~dp0DownloadFile.bat" "%NAME%" "%DISTRO%" "%URL%"


:: ============================================================================ MAIN BEGIN
:MAIN

SetLocal EnableExtensions EnableDelayedExpansion

set "ERROR_STATUS=0"

call :COLOR_SCHEME

echo:
echo --------------------------------------------------------------------------------
echo %WARN% Processing %~1 download.
echo:

call :CHECKURL__URL_PATH %* || exit /b !ERRORLEVEL!
call :DOWNLOAD__NAME_PATH_URL %* || exit /b !ERRORLEVEL!

echo:
echo %WARN% Completed %~1 processing.
echo --------------------------------------------------------------------------------
echo:

endlocal && exit /b %ERROR_STATUS%
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:: ============================================================================ DOWNLOAD__NAME_PATH_URL BEGIN
:: ============================================================================
:DOWNLOAD__NAME_PATH_URL

setlocal EnableDelayedExpansion
set "SECTION=DOWNLOAD__NAME_PATH_URL"
echo:
echo %WARN% ~~~~~ %SECTION% BEGIN ~~~~~
echo:
set "ERROR_STATUS=0"

if "%~3"=="" (
    set "ERROR_STATUS=1"
    echo %ERROR% Missing required parameters.
    echo %INFO%  USAGE: call %~nx0 "NAME" "PATH" "URL"
    goto :DOWNLOAD_EXIT
)

set "NAME=%~1"
set "TARGET=%~2"
set "URL=%~3"

if exist "%TARGET%" (
    echo %OKOK% Using previously downloaded %NAME%
    goto :DOWNLOAD_EXIT
)

echo %INFO% ===== Downloading %NAME% =====
curl.exe -fL --retry 3 --output "%TARGET%" %URL%
set "ERROR_STATUS=!ERRORLEVEL!"
if "!ERROR_STATUS!"=="0" (
    echo %OKOK% Downloaded %NAME%
    echo %OKOK% "%TARGET%"
) else (
    echo %ERROR% %NAME% download failed. Error Code: !ERROR_STATUS!.
)

:DOWNLOAD_EXIT

echo:
echo %WARN% ~~~~~ %SECTION% END ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ DOWNLOAD__NAME_PATH_URL END


:: ============================================================================ CHECKURL__URL_PATH BEGIN
:: ============================================================================
:CHECKURL__URL_PATH

setlocal EnableDelayedExpansion
set "SECTION=CHECKURL__URL_PATH"
echo:
echo %WARN% ~~~~~ %SECTION% BEGIN ~~~~~
echo:
set "ERROR_STATUS=0"

set "URL=%~3"
set "TARGET=%~dpn2"

curl -fIL --retry 3 -o "%TARGET%.log" %URL% 2>"%TARGET%_err.log"
set "ERROR_STATUS=%ERRORLEVEL%"
if not "%ERROR_STATUS%"=="0" (
    echo %ERROR% URL fetching error #%ERROR_STATUS%
    goto :CHECKURL__URL_PATH_EXIT
)

for /f "Usebackq tokens=1,2 delims= " %%G in (%TARGET%.log) do (
  if /I "%%G"=="HTTP/1.1"        (set "RES_CODE=%%H")
  if /I "%%G"=="Content-Length:" (set "RES_LEN=%%H")
  if /I "%%G"=="Content-Type:"   (set "RES_TYPE=%%H")
)

echo %INFO% URL Meta
echo %INFO% --------
echo %INFO% RES_CODE: _%RES_CODE%_
echo %INFO% RES_LEN:  _%RES_LEN%_
echo %INFO% RES_TYPE: _%RES_TYPE%_
echo:

if "%RES_TYPE%"=="text/html" (
    set "ERROR_STATUS=1"
    echo %ERROR% Provided URL returns text/html content.
    goto :CHECKURL__URL_PATH_EXIT
)

:CHECKURL__URL_PATH_EXIT

echo:
echo %WARN% ~~~~~ %SECTION% END ~~~~~
echo:
endlocal && set "ERROR_STATUS=%ERROR_STATUS%" && exit /b %ERROR_STATUS%
:: ============================================================================
:: ============================================================================ CHECKURL__URL_PATH END


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
