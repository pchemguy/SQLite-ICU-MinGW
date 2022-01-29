@echo off

call "%~dp0PeaZipGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)

if not defined ARCH (
  if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" set "ARCH=x64"
  if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" set "ARCH=x32"
  if not defined ARCH set "ARCH=x32"
) else (
  set ARCH=x%ARCH:~-2%
)

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMGIT=%DEVDIR%\git4win\%ARCH%
set OUTGIT="%HOMGIT%\..\stdout.log"
set ERRGIT="%HOMGIT%\..\stderr.log"
del %OUTGIT% 2>nul
del %ERRGIT% 2>nul
set ResultCode=0
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set Owner=git-for-windows
set Repo=git
set PatternURL=%ARCH:~-2%-bit.7z.exe

call "%~dp0GitHubReleaseURL.bat" %Owner% %Repo% "%PatternURL%"

call "%~dp0DownloadFile.bat" %ReleaseURL%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set PKGNAM=%FileName%

if not exist "%HOMGIT%\git-bash.exe" (
  echo ==================== Extracting archive ====================
  if exist "%HOMGIT%" rmdir /S /Q "%HOMGIT%" 2>nul
  mkdir "%HOMGIT%" 1>nul
  cd /d "%HOMGIT%"
  7z.exe x "%PKGDIR%\%PKGNAM%" 1>>%OUTGIT% 2>>%ERRGIT%
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
) else (
  echo =========== Using previously extracted %PKGNAM% ============
)

set MSYS2BIN=%HOMGIT%\usr\bin
set MINGWBIN=%HOMGIT%\mingw%ARCH:~-2%\bin
if "/!Path!/"=="/!Path:%MSYS2BIN%=!/" (
  set "Path=%MSYS2BIN%;%Path%"
  set "Path=!Path!;%MINGWBIN%"
)


:: Cleanup
set HOMGIT=
set OUTGIT=
set ERRGIT=
set Owner=
set Repo=
set ReleaseURL=
set ZipSrcURL=
set TarSrcURL=
set PKGNAM=
set ReleaseAPI=
set MSYS2BIN=
set MINGWBIN=
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
