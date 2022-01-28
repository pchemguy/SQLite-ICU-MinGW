@echo off


set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMZSTD=%DEVDIR%\zstd
set ResultCode=0

call "%~dp0GNUGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set Owner=facebook
set Repo=zstd
set Pattern=win32.zip

call "%~dp0GitHubReleaseURL.bat" %Owner% %Repo% "%Pattern%"

call "%~dp0DownloadFile.bat" %ReleaseURL%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set ZSTDx32File=%FileName%
call "%~dp0DownloadFile.bat" %ReleaseURL:win32=win64%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set ZSTDx64File=%FileName%

if not exist "%HOMZSTD%\x32\zstd.exe" (
  if exist "%HOMZSTD%" rmdir /S /Q "%HOMZSTD%" 2>nul
  mkdir "%HOMZSTD%" 1>nul
  call "%~dp0ExtractArchive.bat" %ZSTDx32File% "%HOMZSTD%"
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
  call "%~dp0ExtractArchive.bat" %ZSTDx64File% "%HOMZSTD%"
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
  cd /d "%HOMZSTD%"
  move %ZSTDx32File:~0,-4% x32 1>nul
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
  move %ZSTDx64File:~0,-4% x64 1>nul
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
)

:: Set building flags
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" set "ARCH=x64"
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" set "ARCH=x32"
if not defined ARCH set "ARCH=x32"

set ZSTD_BINPATH=%HOMZSTD%\%ARCH%
if "/!Path!/"=="/!Path:%ZSTD_BINPATH%=!/" set Path=%ZSTD_BINPATH%;%Path%
set ZSTD_BINPATH=%HOMZSTD%\%ARCH%\dll

set ZSTD_LIBPATH=%HOMZSTD%\%ARCH%\static
if "/!LIBPATH!/"=="/!LIBPATH:%ZSTD_LIBPATH%=!/" set LIBPATH=%ZSTD_LIBPATH%;%LIBPATH%

set ZSTD_INCLUDE=%HOMZSTD%\%ARCH%\include
if "/!INCLUDE!/"=="/!INCLUDE:%ZSTD_INCLUDE%=!/" set INCLUDE=%ZSTD_INCLUDE%;%INCLUDE%
set ZSTD_LIBSTATIC=libzstd_static.lib
set ZSTD_LIBSHARED=libzstd.dll
set ZSTD_LIB=%ZSTD_LIBSTATIC%

echo.
echo ============= Zstd installation is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured). Check the log files for errors. 
echo.

echo ========== Zstd core linking flags ==========
echo ZSTD_INCLUDE   = %ZSTD_INCLUDE%
echo ZSTD_LIBPATH   = %ZSTD_LIBPATH%
echo ZSTD_BINPATH   = %ZSTD_BINPATH%
echo ZSTD_LIB       = %ZSTD_LIB%
echo ZSTD_LIBSTATIC = %ZSTD_LIBSTATIC%
echo ZSTD_LIBSHARED = %ZSTD_LIBSHARED%
echo ---------------------------------------------


:: Cleanup
set HOMZSTD=
set Owner=
set Repo=
set Pattern=
set ReleaseURL=
set ZipSrcURL=
set TarSrcURL=
set ZSTDx32File=
set ZSTDx64File=
set ReleaseAPI=
set RepoName=
set RepoOwner=
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
