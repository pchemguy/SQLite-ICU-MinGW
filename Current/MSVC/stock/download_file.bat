@echo off

::
:: Downloads file via cURL. A completed cache entry is reused offline.
::
:: Arguments:
::     %1 - Name (logging label).
::     %2 - Full download path.
::     %~3 - Download URL.
::     %~4 - Optional archive member pattern to validate with Windows tar.
::
:: Examples:
::     set "NAME=SQLite"
::     set "DISTRO=%~dp0sqlite.zip"
::     set "URL=https://sqlite.org/src/zip/sqlite.zip"
::     
::     call "%~dp0download_file.bat" "%NAME%" "%DISTRO%" "%URL%"


:: ============================================================================ MAIN BEGIN
:: ============================================================================

setlocal EnableExtensions DisableDelayedExpansion
call :COLOR_SCHEME

set "NAME=%~1"
set "TARGET=%~f2"
set "URL=%~3"
set "MEMBER=%~4"
if not defined NAME goto :USAGE
if "%~2"=="" goto :USAGE
if not defined URL goto :USAGE
if exist "%TARGET%\" (
    echo %ERROR% Expected a file, not a directory: "%TARGET%"
    exit /b 1
)

if not defined TAR set "TAR=%SystemRoot%\System32\tar.exe"
if not exist "%TARGET%" goto :FETCH
set "CANDIDATE=%TARGET%"
call :CHECK_ARCHIVE
if errorlevel 1 (
    echo %ERROR% Invalid cache entry: "%TARGET%". Move it aside before retrying.
    exit /b 1
)
echo %OKOK% Using previously downloaded "%NAME%": "%TARGET%"
exit /b 0
:: ============================================================================
:: ============================================================================ MAIN END


:: ############################################################################
:: ############################################################################
:: ############################################################################


:FETCH
set "PART=%TARGET%.part"
set "META=%TARGET%.response.log"
set "HEADER_LOG=%~dpn2.log"
if /i "%HEADER_LOG%"=="%TARGET%" set "HEADER_LOG=%TARGET%.headers.log"
set "ERROR_LOG=%~dpn2_err.log"
echo %INFO% Downloading "%NAME%" to "%PART%"

:: Write final status and media type from the GET, not a separate HEAD. The
:: trailing semicolon makes bare and parameterized media types comparable.
curl.exe -fL --globoff --retry 3 --dump-header "%HEADER_LOG%" --output "%PART%" --write-out "%%{http_code} %%{content_type};\n" -- "%URL%" >"%META%" 2>"%ERROR_LOG%"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo %ERROR% Download failed with status %RC%. See "%ERROR_LOG%".
    goto :FAILED
)

:: Only accept a full HTTP response (not, for example, unsolicited 206).
set "RC=1"
findstr /b /c:"200 " "%META%" >nul || goto :BAD_RESPONSE
findstr /i /r /b /c:"200 [ 	]*text/html[; 	]" "%META%" >nul
if errorlevel 2 goto :BAD_RESPONSE
if not errorlevel 1 goto :BAD_RESPONSE

set "CANDIDATE=%PART%"
call :CHECK_ARCHIVE
if errorlevel 1 (
    echo %ERROR% Invalid downloaded archive for "%NAME%".
    goto :FAILED
)

:: REN stays in the same directory and does not overwrite an existing target.
ren "%PART%" "%~nx2"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo %ERROR% Could not publish "%TARGET%".
    goto :FAILED
)
echo %OKOK% Downloaded "%NAME%": "%TARGET%"
exit /b 0

:BAD_RESPONSE
echo %ERROR% Unexpected HTTP status or media type. See "%META%".

:FAILED
if exist "%PART%" if not exist "%PART%\" del /q "%PART%"
exit /b %RC%


:CHECK_ARCHIVE
if not defined MEMBER exit /b 0
"%TAR%" -tf "%CANDIDATE%" -- "%MEMBER%" >nul
exit /b %ERRORLEVEL%

:USAGE
echo %ERROR% Usage: "%~nx0" "NAME" "TARGET" "URL" [ARCHIVE_MEMBER]
exit /b 1


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
