@echo off
::
:: Extracts distro archive via tar.
::
:: Set TARPATTERN before calling for partial extraction. The script reset this
:: variable at exit. (For now, it is only used with tar.exe).
::
:: Arguments:
::   %1 - Archive name
::   %2 - Directory (optional)
::   %3 - File name flag (optional)
::
:: On failure:
::   ResultCode <> 0
::
:: Examples:
::   ExtractArchive.bat icu4c-70_1-Win32-MSVC2019.zip icu4c bin\uconv.exe
::
:: SHELL: CMD Or MSVC Build Tools
::
SetLocal

set ResultCode=0
if not defined PEAZIP (
  call "%~dp0PeaZipGet.bat" %* 1>nul
  set ResultCode=!ErrorLevel!
  if not "/!ResultCode!/"=="/0/" (
    echo PeaZipGet.bat error.
    echo --------------------
    goto :EOS
  )
)

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
  echo ------------------------------------------------------------
  echo.
  goto :EOS
)
set Folder=%~2
if "/%Folder%/"=="//" (set Folder=.)
set Flag=%~3
if "/%Flag%/"=="//" (set Flag=$$$$$$.$$$)


set EXTRACTED=0
if not exist "%Folder%\%Flag%" (
  echo ===== Extracting %ArchiveName% =====
  if not exist "%Folder%" mkdir "%Folder%"
  if !EXTRACTED! EQU 0 (
    if /I "/%ArchiveName:~-4%/"=="/.zip/" (
      tar -C "%Folder%" -xf "%ArchiveName%" %TARPATTERN%
      set ResultCode=%ErrorLevel%
      set EXTRACTED=1
    )
  )
  if !EXTRACTED! EQU 0 (
    if /I "/%ArchiveName:~-7%/"=="/.tar.gz/" (
      tar -C "%Folder%" -xf "%ArchiveName%" %TARPATTERN%
      set ResultCode=%ErrorLevel%
      set EXTRACTED=1
    )
  )
  if !EXTRACTED! EQU 0 (
    if /I "/%ArchiveName:~-7%/"=="/.tar.xz/" (
      7z x "%ArchiveName%" -so | 7z x -aoa -si -ttar -o"%Folder%"
      set ResultCode=%ErrorLevel%
      set EXTRACTED=1
    )
  )
  if !EXTRACTED! EQU 0 (
    if /I "/%ArchiveName:~-8%/"=="/.tar.zst/" (
      zstd -d "%ArchiveName%" -c | 7z x -aoa -si -ttar -o"%Folder%"
      set ResultCode=%ErrorLevel%
      set EXTRACTED=1
    )
  )

  if %ResultCode% EQU 0 (
    echo ----- Extracted %ArchiveName%  -----
  ) else (
    echo Error extracting %ArchiveName%.
  )
) else (
  echo ========= Using previously extracted %ArchiveName% =========
)

set TARPATTERN=

:EOS
echo.
echo ------------- LEAVING ExtractArchive.bat ---------------------

EndLocal & exit /b %ResultCode%
