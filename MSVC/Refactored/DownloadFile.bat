@echo off
::
:: Downloads file via cURL.
::
:: Set current directory to the distro download directory before calling.
::
:: Arguments:
::   %1 - URL
::   %2 - File name
::
:: On failure:
::   ResultCode <> 0
::
:: Examples:
::   DownloadFile.bat https://github.com/unicode-org/icu/releases/download/release-70-1/icu4c-70_1-Win32-MSVC2019.zip icu4c-70_1-Win32-MSVC2019.zip
::
echo.
echo ==================== Downloading file ====================
set ResultCode=0
set FileURL=%~1
if "/%FileURL%/"=="//" (
  echo File URL is not supplied.
  set ResultCode=1
)
set FileName=%~2
if "/%FileName%/"=="//" (
  echo File name is not supplied.
  set ResultCode=1
)
if not %ResultCode% EQU 0 (
  echo Correct arguments have not been provided to download file.
  echo ----------------------------------------------------------
  echo.
  exit /b %ResultCode%
)

if not exist "%FileName%" (
  echo ===== Downloading %FileName% =====
  curl -L %FileURL% --output "%FileName%"
  set ResultCode=%ErrorLevel%
  if %ResultCode% EQU 0 (
    echo ----- Downloaded %FileName%  -----
  ) else (
    echo Error downloading %FileName%.
  )
) else (
  echo ========= Using previously downloaded %FileName% =========
)
echo ----------------------------------------------------------
echo.

exit /b %ResultCode%
