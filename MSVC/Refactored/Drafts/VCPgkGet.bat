@echo off
::
:: Installs VCPKG.
::
:: DO NOT execute from a MSBuild shell or a PowerShell!
:: Only use regular cmd.exe.
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMVCPKG=%DEVDIR%\vcpkg
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set Owner=microsoft
set Repo=vcpkg

call "%~dp0GitHubReleaseURL.bat" %Owner% %Repo%
echo %ZipSrcURL%
set PKGNAM=vcpkg.zip
call "%~dp0DownloadFile.bat" %ZipSrcURL% "%PKGNAM%"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

if not exist "%HOMVCPKG%\bootstrap-vcpkg.bat" (
  if exist "%HOMVCPKG%" rmdir /S /Q "%HOMVCPKG%" 2>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%DEVDIR%"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  cd /d "%DEVDIR%"
  move microsoft-vcpkg-* "vcpkg" 1>nul
)

cd /d "%HOMVCPKG%"
.\bootstrap-vcpkg.bat -disableMetrics

exit /b 0

set PZIP7Z_BINPATH=%HOMVCPKG%\res\bin\7z
if exist "%PZIP7Z_BINPATH%\7z.exe" (
  if "/!Path!/"=="/!Path:%PZIP7Z_BINPATH%=!/" set "Path=%Path%;%PZIP7Z_BINPATH%"
  echo 7z = "%PZIP7Z_BINPATH%\7z.exe"
  set ResultCode=0
) else (
  echo 7z is not found in PeaZip distro!
  set ResultCode=1
)


:: Cleanup
set HOMVCPKG=
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
