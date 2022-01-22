@echo off
::
:: Downloads file via cURL.
::
:: Set current directory to the distro download directory before calling.
::
:: Arguments:
::   %1 - URL
::   %2 - File name (optional; if not provided, tries to extract the last part of the URL)
::
:: On failure:
::   ResultCode <> 0
::
:: Examples:
::   DownloadFile.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip icu4c-70_1-Win32-MSVC2019.zip
::   DownloadFile.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip
::
echo.
echo ==================== Downloading file ====================
set ResultCode=0
set FileURL=%~1
if "/%FileURL%/"=="//" (
  echo File URL is not supplied.
  set ResultCode=1
)
if not %ResultCode% EQU 0 (
  echo Correct arguments have not been provided to download file.
  echo ----------------------------------------------------------
  echo.
  exit /b %ResultCode%
)
set FileName=%~2
if "/%FileName%/"=="//" (call :EXTRACT_FILENAME %FileURL%)

if not exist "%FileName%.size" (
  call "%~dp0URLInfo.bat" %FileURL%
  set ResultCode=%ErrorLevel%
  if not !ResultCode! EQU 0 (
    echo ----- URL error -----
    exit /b !ResultCode!
  )
  echo !FileLen!>"%FileName%.size"
)

for /f "Usebackq delims=" %%G in ("%FileName%.size") do (
  set FileLen=%%G
)

if exist "%FileName%" (
  call :SET_FILEZIE "%FileName%"
  if "/!FileSize!/"=="/%FileLen%/" (
    echo ========= Using previously downloaded %FileName% =========
    echo ----------------------------------------------------------
    exit /b 0
  ) else (
    echo ----- File size saved in file "%FileName%.size" does not match the size of cached copy: -----
    echo Saved file size:     ==%FileLen%==
    echo Size of cached copy: ==%FileSize%==
    echo Dowloading again.
    echo.
    del /Q "%FileName%"
  )
)

echo ===== Downloading %FileName% =====
curl -L %FileURL% --output "%FileName%"
set ResultCode=%ErrorLevel%
if %ResultCode% NEQ 0 (
  echo Error downloading %FileName%.
  exit /b !ResultCode!
)

call :SET_FILEZIE "%FileName%"
if "/!FileSize!/"=="/%FileLen%/" (
  echo ----- Downloaded %FileName%  -----
) else (
  echo Error downloading %FileName% - file size mismatch. Run the processes again.
  echo File renamed to %FileName%.$$$.
  echo.
  move "%FileName%" "%FileName%.$$$" 1>nul
  move "%FileName%.size" "%FileName%.size.$$$" 1>nul
  set ResultCode=1
)
echo ----------------------------------------------------------
echo.

exit /b %ResultCode%


:: ============================================================================
:EXTRACT_FILENAME
set URL=%~1
set URL=%URL:http://=%
set URL=%URL:https://=%
set URL=%URL:?= %
call :SET_FILENAME %URL%
exit /b 0

:SET_FILENAME
set FileName=%~nx1
exit /b 0

:SET_FILEZIE
set FileSize=%~z1
exit /b 0
