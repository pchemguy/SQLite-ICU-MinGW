@echo off
::
:: Prepares the zlib library and sets build flags.
::
:: The script enters the "%dp0distro" subdirectory (creates, if necessary).
:: Distro archive is downloaded, if not present, and saved in "%dp0distro".
:: Distro archive is expanded in "%dp0distro\zlib" (it contains the README
:: file). The library is build along the source. Binaries are moved to
:: "%dp0dev\zlib\lib" and .h to "%dp0dev\zlib\include".
:: 
:: Set
::   - ZLIB_STDCALL to 1 to build STDCALL; use CDECL otherwise.
::   - ZLIB_SHARED to 1 to use dynamic linking via an import library (default);
::     to use static linking, set ZLIB_SHARED to 0.
::
set ZLIB_CFLAGS=
set ZLIB_INCLUDE=
set ZLIB_LIBPATH=
set ZLIB_LIB=

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set BLDZLIB=%BASEDIR%\bld\zlib
set HOMZLIB=%BASEDIR%\dev\zlib

set OUTZLIB="%BASEDIR%\zlibout.log"
set ERRZLIB="%BASEDIR%\zliberr.log"
del %OUTZLIB% 2>nul
del %ERRZLIB% 2>nul
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"

:: Retrieve ChangeLog.txt and extract the latest release version (at the top).
set ChangeLogURL=https://zlib.net/ChangeLog.txt
call "%~dp0DownloadFile.bat" %ChangeLogURL%
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
set CommandText=type %FileName%
for /f "Usebackq tokens=1,3 skip=2 delims= " %%G in (`%CommandText%`) do (
  if "/%%G/"=="/Changes/" (
    set PKGVER=%%H
    goto :VERSION_SET
  )
)
:VERSION_SET

:: Download
cd /d "%PKGDIR%"
set PKGNAM=zlib-%PKGVER%.tar.gz
set ReleaseURL=https://zlib.net/%PKGNAM%
call "%~dp0DownloadFile.bat" %ReleaseURL%
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)

:: Expand
if not exist "%BLDZLIB%\Makefile" (
  rmdir /S /Q "%BLDZLIB%" 2>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%BLDDIR%"
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  cd /d "%BLDDIR%"
  move "zlib-%PKGVER%" "zlib"
)

:: Build
cd /d "%BLDZLIB%"
if "/%USE_STDCALL%/"=="/1/" (set ZLIB_LOC=-DZLIB_WINAPI)
nmake -f win32/Makefile.msc LOC="%ZLIB_LOC%" clean all 1>>%OUTZLIB% 2>>%ERRZLIB%
set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo Error making ZLIB.
  exit /b %ResultCode%
)

:: Collect binaries
rmdir /S /Q "%HOMZLIB%" 2>nul
mkdir "%HOMZLIB%\lib"
set ZLIB_LIBStatic=zlib.lib
copy /Y "%BLDZLIB%\%ZLIB_LIBStatic%" "%HOMZLIB%\lib"
set ZLIB_LIBImpLib=zdll.lib
copy /Y "%BLDZLIB%\%ZLIB_LIBImpLib%" "%HOMZLIB%\lib"
set ZLIB_LIBShared=zlib1.dll
copy /Y "%BLDZLIB%\%ZLIB_LIBShared%" "%HOMZLIB%\lib"
mkdir "%HOMZLIB%\include"
copy /Y "%BLDZLIB%\zlib.h" "%HOMZLIB%\include"
copy /Y "%BLDZLIB%\zconf.h" "%HOMZLIB%\include"

:: Set building flags
::   /LIBPATH:"%HOMZLIB%\lib"
set ZLIB_LIBPATH=%HOMZLIB%\lib
if "/!LIBPATH!/"=="/!LIBPATH:%ZLIB_LIBPATH%=!/" set LIBPATH=%ZLIB_LIBPATH%;%LIBPATH%
::   -I"%HOMZLIB%\include"
set ZLIB_INCLUDE=%HOMZLIB%\include
if "/!INCLUDE!/"=="/!INCLUDE:%ZLIB_INCLUDE%=!/" set INCLUDE=%ZLIB_INCLUDE%;%INCLUDE%

if "/%ZLIB_STDCALL%/"=="/1/" (
  echo Building WINAPI
  set ZLIB_CFLAGS=-DZLIB_WINAPI !ZLIB_CFLAGS!
) else (
  echo Building CDECL
  set ZLIB_CFLAGS=-DZEXPORT=__cdecl !ZLIB_CFLAGS!
)

if not "/%ZLIB_SHARED%/"=="/0/" (
  echo SHARED ZLib setting requested.
  set ZLIB_CFLAGS=-DZLIB_DLL !ZLIB_CFLAGS!
  set ZLIB_LIB=!ZLIB_LIBImpLib! !ZLIB_LIB!
) else (
  echo STATIC ZLib setting requested.
  set ZLIB_LIB=!ZLIB_LIBStatic! !ZLIB_LIB!
)

echo.
echo ============= ZLIB settings ============
echo ZLIB_STDCALL=%ZLIB_STDCALL%
echo ZLIB_SHARED=%ZLIB_SHARED%
echo ----------------------------------------
echo.
echo ========== ZLIB linking flags ==========
echo ZLIB_CFLAGS=%ZLIB_CFLAGS%
echo ZLIB_INCLUDE=%ZLIB_INCLUDE%
echo ZLIB_LIBPATH=%ZLIB_LIBPATH%
echo ZLIB_LIB=%ZLIB_LIB%
echo ----------------------------------------
echo.

echo.
echo ============= zlib building is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured) . Check the log files for errors. 
echo.

:: Cleanup
set URL=
set ZLIB_SHARED=
set ZLIB_LIBStatic=
set ZLIB_LIBShared=
set ZLIB_LIBImpLib=
set PKGVER=
set BASEDIR=
set HOMZLIB=
set BLDZLIB=
set ChangeLogURL=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ReleaseURL=
set OUTZLIB=
set ERRZLIB=
set CommandText=
set ArchiveName=

popd

exit /b 0




