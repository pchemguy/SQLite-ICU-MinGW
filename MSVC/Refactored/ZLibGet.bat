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
set ZLIB_HOME=%BASEDIR%\dev\zlib
set ZLIB_DISTRO=%BASEDIR%\distro\zlib
set ZLIB_BUILD=%BASEDIR%\build\zlib

if not exist "%BASEDIR%\distro" mkdir "%BASEDIR%\distro"
pushd "%BASEDIR%\distro"

:: Retrieve ChangeLog.txt and extract the latest release version (at the top).
set ChangeLogURL=https://zlib.net/ChangeLog.txt
call "%~dp0DownloadFile.bat" %ChangeLogURL%
set CommandText=type %FileName%
for /f "Usebackq tokens=1,3 skip=2 delims= " %%G in (`%CommandText%`) do (
  if "/%%G/"=="/Changes/" (
    set ZLibVersion=%%H
    goto :VERSION_SET
  )
)
:VERSION_SET

:: Expand archive
set DistroName=zlib-%ZLibVersion%.tar.gz
set ReleaseURL=https://zlib.net/%DistroName%
call "%~dp0DownloadFile.bat" %ReleaseURL%
if not exist "%ZLIB_BUILD%\Makefile" (
  rmdir /S /Q "%ZLIB_BUILD%" 2>nul
  call "%~dp0ExtractArchive.bat" %DistroName% "%BASEDIR%\build"
  cd /d "%BASEDIR%\build"
  move "zlib-%ZLibVersion%" "zlib"
)

:: Build
cd /d "%ZLIB_BUILD%"
if "/%USE_STDCALL%/"=="/1/" (set ZLIB_LOC=-DZLIB_WINAPI)
nmake -f win32/Makefile.msc LOC="%ZLIB_LOC%" clean all
set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo Error making ZLIB.
  exit /b %ResultCode%
)

:: Collect binaries
rmdir /S /Q "%ZLIB_HOME%" 2>nul
mkdir "%ZLIB_HOME%\lib"
set ZLIB_LIBStatic=zlib.lib
copy /Y "%ZLIB_BUILD%\%ZLIB_LIBStatic%" "%ZLIB_HOME%\lib"
set ZLIB_LIBImpLib=zdll.lib
copy /Y "%ZLIB_BUILD%\%ZLIB_LIBImpLib%" "%ZLIB_HOME%\lib"
set ZLIB_LIBShared=zlib1.dll
copy /Y "%ZLIB_BUILD%\%ZLIB_LIBShared%" "%ZLIB_HOME%\lib"
mkdir "%ZLIB_HOME%\include"
copy /Y "%ZLIB_BUILD%\zlib.h" "%ZLIB_HOME%\include"
copy /Y "%ZLIB_BUILD%\zconf.h" "%ZLIB_HOME%\include"

:: Set building flags
set ZLIB_LIBPATH=/LIBPATH:"%ZLIB_HOME%\lib" %ZLIB_LIBPATH%
set ZLIB_INCLUDE=-I"%ZLIB_HOME%\include" %ZLIB_INCLUDE%
echo.
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

:: Cleanup
set ZLIB_SHARED=
set URL=
set ZLIB_LIBStatic=
set ZLIB_LIBShared=
set ZLIB_LIBImpLib=
set ZLibVersion=
set BASEDIR=
set ZLIB_HOME=
set ZLIB_DISTRO=
set ZLIB_BUILD=

popd

exit /b 0
