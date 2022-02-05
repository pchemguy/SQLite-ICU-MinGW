@echo off
::
:: Extracts distro archive via tar.
::
:: Set TARPATTERN before calling for partial extraction. The script reset this
:: variable at exit.
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
:: Provides 7z and zstd
if not defined PEAZIP (
  call "%~dp0PeaZipGet.bat" %* 1>nul
  set ResultCode=!ErrorLevel!
  if not "/!ResultCode!/"=="/0/" (
    echo PeaZipGet.bat error.
    echo --------------------
    goto :EOS
  )
)

set CommandText=where bsdtar 2^^^>nul
set TOOLPATH=
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!TOOLPATH!/"=="//" (
    set TOOLPATH=%%i
  )
)
if "/%TOOLPATH%/"=="//" (set TAR=tar) else (set TAR=bsdtar)

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
      %TAR% -C "%Folder%" -xf "%ArchiveName%" %TARPATTERN%
      set ResultCode=%ErrorLevel%
      set EXTRACTED=1
    )
  )
  if !EXTRACTED! EQU 0 (
    if /I "/%ArchiveName:~-7%/"=="/.tar.gz/" (
      %TAR% -C "%Folder%" -xf "%ArchiveName%" %TARPATTERN%
      set ResultCode=%ErrorLevel%
      set EXTRACTED=1
    )
  )
  if !EXTRACTED! EQU 0 (
    if /I "/%ArchiveName:~-7%/"=="/.tar.xz/" (
      7z x "%ArchiveName%" -so | %TAR% -C "%Folder%" -xf - %TARPATTERN%
      set ResultCode=%ErrorLevel%
      set EXTRACTED=1
    )
  )
  if !EXTRACTED! EQU 0 (
    if /I "/%ArchiveName:~-8%/"=="/.tar.zst/" (
      zstd -d "%ArchiveName%" -c | %TAR% -C "%Folder%" -xf - %TARPATTERN%
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


:EOS
echo.
echo ------------- LEAVING ExtractArchive.bat ---------------------

EndLocal & set "TARPATTERN=" & exit /b %ResultCode%
