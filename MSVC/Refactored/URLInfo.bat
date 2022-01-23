@echo off
::
:: Verifies URL.
::
:: The script uses cURL to verify that the given URL returns "HTTP/1.1 200 OK"
:: (follows any redirects). The script also attempts to determine the file size
:: and final URL (if redirected). Presently, the final URL is not returned.
::
:: Sets:
::   "FileLen" - file size (this value, if set, is likely meaningless for a web
::               page).
::
:: Arguments:
::   %1 - URL
::
:: On failure:
::   ResultCode <> 0
::
:: Examples:
::   URLInfo.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip
::
setlocal EnableDelayedExpansion


set URLInfo=%~1
if "/%URLInfo%/"=="//" (
  echo ----- URL is not supplied. -----
  set ResultCode=1
  goto :EXIT
)

if exist URLInfo.txt del /Q URLInfo.txt 1>nul
if exist URLInfoERR.log del /Q URLInfoERR.log

curl -Is -L %URLInfo% -o URLInfo.txt 2>URLInfoERR.log
set ResultCode=%ErrorLevel%
if not %ResultCode% EQU 0 (
  echo ----- URL fetching error #%ResultCode% -----
  goto :EXIT
)

set CommandText=URLInfo.txt
for /f "Usebackq tokens=1,2 delims= " %%G in (%CommandText%) do (
  if /I "%%G"=="HTTP/1.1"        (set ResCod=%%H) else (
  if /I "%%G"=="Location:"       (set ResURL=%%H) else (
  if /I "%%G"=="Content-Length:" (set ResLen=%%H) ))
)

if "/%ResCod%/"=="/404/" (
  echo ----- URL not found "%URLInfo%" -----
  set ResultCode=1
) else (
  set ResultCode=0
)


:EXIT
endlocal & set "FileLen=%ResLen%" & exit /b %ResultCode%
