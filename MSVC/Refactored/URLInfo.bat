@echo off

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
  if "%%G"=="HTTP/1.1"        (set ResCod=%%H) else (
  if "%%G"=="Location:"       (set ResURL=%%H) else (
  if "%%G"=="Content-Length:" (set ResLen=%%H) ))
)

if "/%ResCod%/"=="/404/" (
  echo ----- URL not found "%URLInfo%" -----
  set ResultCode=1
) else (
  set ResultCode=0
)


:EXIT
endlocal & set "FileLen=%ResLen%" & exit /b %ResultCode%