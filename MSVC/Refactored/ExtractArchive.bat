@echo off
::
:: Extracts distro archive via tar.
::
:: Set TARPATTERN before calling for partial extraction. The script reset this
:: variable at exit.
::
:: Arguments:
::   %1 - Archive name
::   %2 - Directory (optional
::   %3 - File name flag (optional)
::
:: On failure:
::   ResultCode <> 0
::
:: Examples:
::   ExtractArchive.bat icu4c-70_1-Win32-MSVC2019.zip icu4c bin\uconv.exe
::
echo.
echo ==================== Extracting archive ====================
set ResultCode=0
set ArchiveName=%~1
if "/%ArchiveName%/"=="//" (
  echo Archive is not supplied.
  set ResultCode=1
)
if not %ResultCode% EQU 0 (
  echo Correct arguments have not been provided to extract archive.
  echo ----------------------------------------------------------
  echo.
  exit /b %ResultCode%
)
set Folder=%~2
if "/%Folder%/"=="//" (set Folder=.)
set Flag=%~3
if "/%Flag%/"=="//" (set Flag=$$$$$$.$$$)


if not exist "%Folder%\%Flag%" (
  echo ===== Extracting %ArchiveName% =====
  if not exist "%Folder%" mkdir "%Folder%"
  tar -C "%Folder%" -xf "%ArchiveName%" %TARPATTERN%

  set ResultCode=%ErrorLevel%
  if %ResultCode% EQU 0 (
    echo ----- Extracted %ArchiveName%  -----
  ) else (
    echo Error extracting %ArchiveName%.
  )
) else (
  echo ========= Using previously extracted %ArchiveName% =========
)
echo ------------------------------------------------------------
echo.

set TARPATTERN=

exit /b %ResultCode%
