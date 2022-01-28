@echo off
::
:: Prepares the zlib library and sets build flags.
::
:: The script enters the "%dp0distro" subdirectory (creates, if necessary).
:: Distro archive is downloaded, if not present, and saved in "%dp0distro".
:: Distro archive is expanded in "%dp0distro\zlib" (it contains the README
:: file). The library is build via CMake/MSVC.
::
call "%~dp0CMakeMSVCActivate.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" set "ARCH=x64"
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" set "ARCH=x32"

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set SRCZLIB=%BASEDIR%\bld\zlib\src
set BLDZLIB=%BASEDIR%\bld\zlib\%ARCH%
set HOMZLIB=%BASEDIR%\dev\zlib\%ARCH%

set OUTZLIB="%BLDZLIB%\stdout.log"
set ERRZLIB="%BLDZLIB%\stderr.log"
del %OUTZLIB% 2>nul
del %ERRZLIB% 2>nul
set ResultCode=0

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"

:: Build dir holds the log files, so reset it first, if necessary.
if not exist "%BLDZLIB%\CMakeCache.txt" (
  if exist "%BLDZLIB%" rmdir /S /Q "%BLDZLIB%" 1>nul
  mkdir "%BLDZLIB%" 1>nul
)

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
if not exist "%SRCZLIB%\Makefile" (
  if exist "%SRCZLIB%" rmdir /S /Q "%SRCZLIB%" 1>nul
  if not exist "!SRCZLIB:~0,-4!" mkdir "!SRCZLIB:~0,-4!" 1>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "!SRCZLIB:~0,-4!"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  cd /d "%SRCZLIB:~0,-4%"
  move "zlib-%PKGVER%" "src" 1>nul
)

:: Configure
if not exist "%BLDZLIB%\CMakeCache.txt" (
  echo. 1>>%OUTZLIB% 2>>%ERRZLIB%
  echo ============= CMake configure ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
  if exist "%HOMZLIB%" rmdir /S /Q "%HOMZLIB%" 1>nul
  cd /d "%BLDZLIB%"
  cmake "%SRCZLIB%" -DCMAKE_INSTALL_PREFIX:PATH="%HOMZLIB%" 1>>%OUTZLIB% 2>>%ERRZLIB%
) else (
  echo ============= Using previously configured ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
)

:: Build
if not exist "%BLDZLIB%\Release\zlib.dll" (
  echo. 1>>%OUTZLIB% 2>>%ERRZLIB%
  echo ============= CMake build ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
  if exist "%HOMZLIB%" rmdir /S /Q "%HOMZLIB%" 1>nul
  cd /d "%BLDZLIB%"
  cmake --build . --target ALL_BUILD --config Release 1>>%OUTZLIB% 2>>%ERRZLIB%
) else (
  echo ============= Using previously built ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
)

:: Install
if not exist "%HOMZLIB%\bin\zlib.dll" (
  echo. 1>>%OUTZLIB% 2>>%ERRZLIB%
  echo ============= CMake install ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
  if exist "%HOMZLIB%" rmdir /S /Q "%HOMZLIB%" 1>nul
  mkdir "%HOMZLIB%" 1>nul
  cd /d "%BLDZLIB%"
  cmake --install . 1>>%OUTZLIB% 2>>%ERRZLIB%
) else (
  echo ============= Using previously installed ZLIB ============ 1>>%OUTZLIB% 2>>%ERRZLIB%
)
set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo Error making ZLIB.
  exit /b %ResultCode%
)

:: Set building flags
set ZLIBDIR=%HOMZLIB%
set ZLIB_ROOT=%HOMZLIB%
set ZLIB_BINPATH=%HOMZLIB%\bin
set ZLIB_LIBPATH=%HOMZLIB%\lib
if "/!LIBPATH!/"=="/!LIBPATH:%ZLIB_LIBPATH%=!/" set LIBPATH=%ZLIB_LIBPATH%;%LIBPATH%
set ZLIB_INCLUDE=%HOMZLIB%\include
if "/!INCLUDE!/"=="/!INCLUDE:%ZLIB_INCLUDE%=!/" set INCLUDE=%ZLIB_INCLUDE%;%INCLUDE%

set ZLIB_LIBSTATIC=zlibstatic.lib
set ZLIB_LIBIMPORT=zlib.lib
set ZLIB_LIBSHARED=zlib.dll

echo.
echo ========== ZLIB linking flags ==========
echo ZLIBDIR        = %ZLIBDIR%
echo ZLIB_ROOT      = %ZLIB_ROOT%
echo ZLIB_BINPATH   = %ZLIB_BINPATH%
echo ZLIB_INCLUDE   = %ZLIB_INCLUDE%
echo ZLIB_LIBPATH   = %ZLIB_LIBPATH%
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
