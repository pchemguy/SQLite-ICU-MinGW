@echo off
::
:: Downloads and installs MSYS2 distro.
::
:: SHELL: CMD Or MSVC Build Tools
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set DEVDIR=%BASEDIR%\dev
set PKGMSYS=%PKGDIR%\msys2
set HOMMSYS=%DEVDIR%\msys2
set OUTMSYS="%BASEDIR%\stdout.log"
set ERRMSYS="%BASEDIR%\stderr.log"
del %OUTMSYS% 2>nul
del %ERRMSYS% 2>nul
set ResultCode=0

if exist "%HOMMSYS%\msys2_shell.cmd" goto :ADDPATH
if exist "%HOMMSYS%" rmdir /S /Q "%HOMMSYS%" 1>nul
if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


if /I "/%PROCESSOR_ARCHITECTURE%/"=="/AMD64/" (
  set MSYSTEM_CARCH=x86_64
) else (
  set MSYSTEM_CARCH=i686
)
set MSYSDISTURL=https://mirror.msys2.org/distrib/msys2-%MSYSTEM_CARCH%-latest.tar.xz

call "%~dp0DownloadFile.bat" %MSYSDISTURL%
set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo DownloadFile.bat error!
  echo ----------------------
  goto :EOS
)
set PKGNAM=%FileName%

call "%~dp0ExtractArchive.bat" %PKGNAM% "%DEVDIR%"
set ResultCode=!ErrorLevel!
if not "/!ResultCode!/"=="/0/" (
  echo ExtractArchive.bat error!
  echo -------------------------
  goto :EOS
)

cd /d %DEVDIR%
if exist "msys64" (ren "msys64" "msys2" 1>nul) else (ren "msys" "msys2" 1>nul)

set MSYS_BIN=%HOMMSYS%\usr\bin
call "%HOMMSYS%\msys2_shell.cmd" -defterm -no-start -c "pacman-key --init" 1>>%OUTMSYS% 2>>%ERRMSYS%
call "%MSYS_BIN%\pacman" --noconfirm --needed --root "%HOMMSYS%" -Syu 1>>%OUTMSYS% 2>>%ERRMSYS%
call "%MSYS_BIN%\pacman" --noconfirm --needed --root "%HOMMSYS%" -Su 1>>%OUTMSYS% 2>>%ERRMSYS%
call "%MSYS_BIN%\pacman" --noconfirm --needed --root "%HOMMSYS%" -Su 1>>%OUTMSYS% 2>>%ERRMSYS%

:ADDPATH
set MSYS_BIN=%HOMMSYS%\usr\bin
if "/!Path!/"=="/!Path:%MSYS_BIN%=!/" set "Path=%MSYS_BIN%;%Path%"

:EOS

:: Cleanup
set PKGMSYS=
set HOMMSYS=
set MSYSDISTURL=
set MSYSTEM_CARCH=
set MSYS_BIN=
set OUTMSYS=
set ERRMSYS=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ArchiveName=
set CommandText=
set InfoFile=

popd

exit /b %ResultCode%

