@echo off
::
:: Prepares the zlib library and sets build flags.
::
:: If exists .\distro, enter it.
:: Set
::   - current directory to the distro download directory before calling. 
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
if exist "%BASEDIR%\distro" (pushd "%BASEDIR%\distro") else (pushd "%CD%")

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
set DistroName=zlib-%ZLibVersion%.tar.gz
set ReleaseURL=https://zlib.net/%DistroName%
call "%~dp0DownloadFile.bat" %ReleaseURL%
if not exist "zlib\Makefile" (
  rmdir /S /Q "zlib" 2>nul
  call "%~dp0ExtractArchive.bat" %DistroName%
  move "zlib-%ZLibVersion%" "zlib"
)

cd /d "zlib"
if "/%USE_STDCALL%/"=="/1/" (set ZLIB_LOC=-DZLIB_WINAPI)

set ZLIB_LIBStatic=zlib.lib
set ZLIB_LIBImpLib=zdll.lib
set ZLIB_LIBShared=zlib1.dll
nmake -f win32/Makefile.msc LOC="%ZLIB_LOC%" clean all

set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo Error retrieving ZLIB.
  exit /b %ResultCode%
)

set ZLIB_HOME=%CD%
set ZLIB_LIBPATH=/LIBPATH:"%ZLIB_HOME%" %ZLIB_LIBPATH%
set ZLIB_INCLUDE=-I"%ZLIB_HOME%" %ZLIB_INCLUDE%
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

set ZLIB_SHARED=
set URL=
set ZLIB_LIBStatic=
set ZLIB_LIBShared=
set ZLIB_LIBImpLib=
set ZLibVersion=

popd

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
exit /b 0
