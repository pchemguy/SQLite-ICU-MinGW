@echo off
::
:: Installs PeaZip and appends 7z bin subfolder to Path.
:: (7z binaries are only available as .7z archive not supported by stock tar.exe.
::  Command-line self-extracting feature of 7z is undocumented and buggy - an
::  attempt to use this feature caused hanging archive exe and started
::  git_bash.exe)
::
:: SHELL: CMD Or MSVC Build Tools
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMPZIP=%DEVDIR%\peazip
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set Owner=peazip
set Repo=PeaZip
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
  set PatternURL=WIN64.zip
) else (
  set PatternURL=WINDOWS.zip
)

call "%~dp0GitHubReleaseURL.bat" %Owner% %Repo% "%PatternURL%"

call "%~dp0DownloadFile.bat" %ReleaseURL%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set PKGNAM=%FileName%

if not exist "%HOMPZIP%\peazip.exe" (
  if exist "%HOMPZIP%" rmdir /S /Q "%HOMPZIP%" 2>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%DEVDIR%"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  cd /d "%DEVDIR%"
  move %PKGNAM:~0,-4% "peazip" 1>nul
)

set PZIP7Z_BINPATH=%HOMPZIP%\res\bin\7z
if exist "%PZIP7Z_BINPATH%\7z.exe" (
  if "/!Path!/"=="/!Path:%PZIP7Z_BINPATH%=!/" set "Path=%Path%;%PZIP7Z_BINPATH%"
  echo 7z = "%PZIP7Z_BINPATH%\7z.exe"
  set ResultCode=0
) else (
  echo 7z is not found in PeaZip distro!
  set ResultCode=1
)

set ZSTD_BINPATH=%HOMPZIP%\res\bin\zstd
if exist "%ZSTD_BINPATH%\zstd.exe" (
  if "/!Path!/"=="/!Path:%ZSTD_BINPATH%=!/" set "Path=%Path%;%ZSTD_BINPATH%"
  echo zstd = "%ZSTD_BINPATH%\zstd.exe"
  set ResultCode=0
) else (
  echo Zstd is not found in PeaZip distro!
  set ResultCode=1
)
set PEAZIP=1


:: Cleanup
set HOMPZIP=
set PZIP7Z_BINPATH=
set ZSTD_BINPATH=
set Owner=
set Repo=
set ReleaseURL=
set ZipSrcURL=
set TarSrcURL=
set PKGNAM=
set ReleaseAPI=
set PatternURL=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ArchiveName=
set CommandText=

popd

exit /b %ResultCode%
