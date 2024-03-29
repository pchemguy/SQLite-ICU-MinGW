@echo off
::
:: Prepares the zlib library and sets build flags.
::
:: The script enters the "%dp0distro" subdirectory (creates, if necessary).
:: Distro archive is downloaded, if not present, and saved in "%dp0distro".
:: Distro archive is expanded in "%dp0distro\zlib" (it contains the README
:: file). The library is build via CMake/MSVC.
::
:: SHELL: MSVC Build Tools
::
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" set "ARCH=x64"
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" set "ARCH=x32"
if not defined USE_STDCALL (
  if "/%ARCH%/"=="/x32/" (set USE_STDCALL=1) else (set USE_STDCALL=0)
)
if "/%USE_STDCALL%/"=="/1/" (set ZLIB_LOC=-DZLIB_WINAPI) else (set ZLIB_LOC=)

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set BLDZLIB=%BASEDIR%\bld\zlib\%ARCH%
set HOMZLIB=%BASEDIR%\dev\zlib\%ARCH%

set OUTZLIB="%BLDZLIB%\stdout.log"
set ERRZLIB="%BLDZLIB%\stderr.log"
del %OUTZLIB% 2>nul
del %ERRZLIB% 2>nul
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"

:: Retrieve ChangeLog.txt and extract the latest release version (at the top).
set ChangeLogURL=https://zlib.net/ChangeLog.txt
call "%~dp0DownloadFile.bat" %ChangeLogURL%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
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
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

:: Expand
if not exist "%BLDZLIB%\Makefile" (
  if exist "%BLDZLIB%" rmdir /S /Q "%BLDZLIB%" 1>nul
  if not exist "!BLDZLIB:~0,-4!" mkdir "!BLDZLIB:~0,-4!" 1>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "!BLDZLIB:~0,-4!"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  cd /d "%BLDZLIB:~0,-4%"
  move "zlib-%PKGVER%" "%ARCH%" 1>nul
)

:: Build
if not exist "%BLDZLIB%\zlib1.dll" (
  rem If rebuilt, make sure existing binaries are deleted.
  if exist "%HOMZLIB%" rmdir /S /Q "%HOMZLIB%"
  echo. 1>>%OUTZLIB% 2>>%ERRZLIB%
  echo ============= Build ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
  cd /d "%BLDZLIB%"
  nmake -f win32/Makefile.msc LOC="!ZLIB_LOC!" clean all 1>>%OUTZLIB% 2>>%ERRZLIB%
  set ResultCode=!ErrorLevel!
  if not "/!ResultCode!/"=="/0/" (
    echo Error making ZLIB.
    exit /b %ResultCode%
  )
) else (
  echo ============= Using previously built ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
)

:: Install
if not exist "%HOMZLIB%\bin\zlib1.dll" (
  echo. 1>>%OUTZLIB% 2>>%ERRZLIB%
  echo ============= Install ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
  (
    if exist "%HOMZLIB%" rmdir /S /Q "%HOMZLIB%"
    mkdir "%HOMZLIB%\bin"
    mkdir "%HOMZLIB%\lib"
    mkdir "%HOMZLIB%\include"
    cd /d "%BLDZLIB%"
    copy     *.lib "%HOMZLIB%\lib"
    copy  zlib.pdb "%HOMZLIB%\lib"
    copy zlib1.dll "%HOMZLIB%\bin"
    copy     *.exe "%HOMZLIB%\bin"
    copy     *.pdb "%HOMZLIB%\bin"
    copy  zlib.h   "%HOMZLIB%\include"
    copy zconf.h   "%HOMZLIB%\include"
  ) 1>nul
) else (
  echo ============= Using previously installed ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
)
set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo Error making ZLIB.
  exit /b %ResultCode%
)

:: Set building flags
set ZLIB_ROOT=%HOMZLIB%
set ZLIB_BINPATH=%HOMZLIB%\bin
set ZLIB_LIBPATH=%HOMZLIB%\lib
if "/!LIBPATH!/"=="/!LIBPATH:%ZLIB_LIBPATH%=!/" set LIBPATH=%ZLIB_LIBPATH%;%LIBPATH%
set ZLIB_INCLUDE=%HOMZLIB%\include
if "/!INCLUDE!/"=="/!INCLUDE:%ZLIB_INCLUDE%=!/" set INCLUDE=%ZLIB_INCLUDE%;%INCLUDE%

set ZLIB_LIBSTATIC=zlib.lib
set ZLIB_LIBIMPORT=zdll.lib
set ZLIB_LIBSHARED=zlib1.dll
set ZLIB_CFLAGS=-DZLIB_DLL %ZLIB_LOC% -I"%ZLIB_INCLUDE%"
set ZLIB_LDFLAGS=/LIBPATH:"%ZLIB_LIBPATH%"

echo.
echo ========== ZLIB linking flags ==========
echo ZLIB_ROOT      = %ZLIB_ROOT%
echo ZLIB_BINPATH   = %ZLIB_BINPATH%
echo ZLIB_INCLUDE   = %ZLIB_INCLUDE%
echo ZLIB_LIBPATH   = %ZLIB_LIBPATH%
echo ZLIB_CFLAGS    = %ZLIB_CFLAGS%
echo ZLIB_LDFLAGS   = %ZLIB_LDFLAGS%
echo ZLIB_LIBSTATIC = %ZLIB_LIBSTATIC%
echo ZLIB_LIBIMPORT = %ZLIB_LIBIMPORT%
echo ZLIB_LIBSHARED = %ZLIB_LIBSHARED%
echo ----------------------------------------
echo.

echo.
echo ============= zlib building is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured) . Check the log files for errors. 
echo.

:: Cleanup
set URL=
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
