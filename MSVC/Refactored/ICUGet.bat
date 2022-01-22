@echo off


set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMICU=%DEVDIR%\icu4c
set ResultCode=0

call "%~dp0GNUGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set Owner=unicode-org
set Repo=icu
set Pattern=Win32-MSVC

call "%~dp0GitHubReleaseURL.bat" %Owner% %Repo% "%Pattern%"

call "%~dp0DownloadFile.bat" %ReleaseURL%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set ICUx32File=%FileName%
call "%~dp0DownloadFile.bat" %ReleaseURL:Win32=Win64%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
set ICUx64File=%FileName%

if not exist "%HOMICU%\bin\uconv.exe" (
  if exist "%HOMICU%" rmdir /S /Q "%HOMICU%" 2>nul
  mkdir "%HOMICU%" 1>nul
  set TARPATTERN=bin* lib*
  call "%~dp0ExtractArchive.bat" %ICUx32File% "%HOMICU%"
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
)

if not exist "%HOMICU%\bin64\uconv.exe" (
  call "%~dp0ExtractArchive.bat" %ICUx64File% "%HOMICU%"
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
)

:: Set building flags
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" set "ARCH=64"
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" set "ARCH="
if not defined ARCH set "ARCH="

set Path=%HOMICU%\bin%ARCH%;%Path%
set ICU_LIBPATH=/LIBPATH:"%HOMICU%\lib%ARCH%"
set ICU_INCLUDE=-I"%HOMICU%\include"
set ICU_LIBImpLib=icudt70.lib icuuc70.lib icuin70.lib icutu70.lib icuio70.lib
set ICU_LIB=%ICU_LIBImpLib%

echo.
echo ============= ICU installation is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured). Check the log files for errors. 
echo.

echo ========== ICU core linking flags ==========
echo ICU_INCLUDE=%ICU_INCLUDE%
echo ICU_LIBPATH=%ICU_LIBPATH%
echo ICU_LIB=%ICU_LIB%
echo --------------------------------------------


:: Cleanup
set HOMICU=
set Owner=
set Repo=
set Pattern=
set ReleaseURL=
set ZipSrcURL=
set TarSrcURL=
set ICUx32File=
set ICUx64File=

popd

exit /b %ResultCode%
