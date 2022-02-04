@echo off
::
:: Downloads and installs MSYS2 distro and MinGW dev toolchains.
::
:: SHELL: CMD Or MSVC Build Tools
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set DEVDIR=%BASEDIR%\dev
set PKGMSYS=%PKGDIR%\msys2\pkg
set HOMMSYS=%DEVDIR%\msys2
set OUTMSYS="%BASEDIR%\stdout.log"
set ERRMSYS="%BASEDIR%\stderr.log"
del %OUTMSYS% 2>nul
del %ERRMSYS% 2>nul
set ResultCode=0

if exist "%HOMMSYS%\msys2_shell.cmd" goto :ADDPATH
if exist "%HOMMSYS%" rmdir /S /Q "%HOMMSYS%" 1>nul
if not exist "%PKGMSYS%" mkdir "%PKGMSYS%"
pushd "%PKGMSYS%\.."


if /I "/%PROCESSOR_ARCHITECTURE%/"=="/AMD64/" (
  set MSYSTEM_CARCH=x86_64
) else (
  set MSYSTEM_CARCH=i686
)
set MSYSDISTURL=https://mirror.msys2.org/distrib/msys2-%MSYSTEM_CARCH%-latest.tar.xz

call "%~dp0DownloadFile.bat" %MSYSDISTURL%.sig
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

set EXEC="%HOMMSYS%\msys2_shell.cmd" -defterm -no-start -c
set PACMAN="%HOMMSYS%\usr\bin\pacman" --noconfirm --needed --root "%HOMMSYS%" --cachedir "%PKGMSYS%" -S
set PACMAN=%PACMAN:"=""%
set PACBOY=%PACMAN:pacman=pacboy%
(
  call %EXEC% "pacman-key --init"
  call %EXEC% "%PACMAN%yuu"
  call %EXEC% "%PACMAN%yuu"
  call %EXEC% "%PACMAN%yuu"
  set PKGS=base-devel pactoys compression bc ed
  call %EXEC% "%PACMAN% !PKGS!"
  set PKGS=mingw-w64-x86_64 mingw-w64-i686
  call %EXEC% "%PACMAN% !PKGS!"
  set PKGS=toolchain:m dlfcn:m icu:m nsis:m libfreexl:m librttopo:m minizip:m iconv:m
  call %EXEC% "%PACBOY% !PKGS!"
) 1>>%OUTMSYS% 2>>%ERRMSYS%

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
