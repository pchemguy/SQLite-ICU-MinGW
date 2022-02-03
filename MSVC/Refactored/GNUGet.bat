@echo off
::
:: Downloads select GNU utilities for Windows. For now, uses GNUWin32 distro.
:: Consider using MSYS2 packages instead.
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set TMPDIR=%DEVDIR%\tmp

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"

set GNU32URL=https://downloads.sourceforge.net/project/gnuwin32/{PKG}.zip

set PKGNAM=sed
set PKGVER=4.2.1
set PKGBAS=%PKGNAM%/%PKGVER%/%PKGNAM%-%PKGVER%-

set GNUURLMain=!GNU32URL:{PKG}=%PKGBAS%bin!
call "%~dp0DownloadFile.bat" %GNUURLMain%
set GNUArcMain=%FileName%
set GNUURLDep=!GNU32URL:{PKG}=%PKGBAS%dep!
call "%~dp0DownloadFile.bat" %GNUURLDep%
set GNUArcDep=%FileName%


:: Expand archive
if not exist "%DEVDIR%\gnu" mkdir "%DEVDIR%\gnu"

if not exist "%DEVDIR%\gnu\sed.exe" (
  if exist "%TMPDIR%" rmdir /S /Q "%TMPDIR%" 2>nul
  mkdir "%TMPDIR%"
  call "%~dp0ExtractArchive.bat" %GNUArcMain% "%TMPDIR%"
  call "%~dp0ExtractArchive.bat" %GNUArcDep% "%TMPDIR%"
  move "%TMPDIR%\bin" "%TMPDIR%\gnu"
  move "%TMPDIR%\gnu\*" "%DEVDIR%\gnu"
  rmdir /S /Q "%TMPDIR%" 2>nul
)

set PKGNAM=grep
set PKGVER=2.5.4
set PKGBAS=%PKGNAM%/%PKGVER%/%PKGNAM%-%PKGVER%-

set GNUURLMain=!GNU32URL:{PKG}=%PKGBAS%bin!
call "%~dp0DownloadFile.bat" %GNUURLMain%
set GNUArcMain=%FileName%
set GNUURLDep=!GNU32URL:{PKG}=%PKGBAS%dep!
call "%~dp0DownloadFile.bat" %GNUURLDep%
set GNUArcDep=%FileName%


:: Expand archive
if not exist "%DEVDIR%\gnu\grep.exe" (
  if exist "%TMPDIR%" rmdir /S /Q "%TMPDIR%" 2>nul
  mkdir "%TMPDIR%"
  call "%~dp0ExtractArchive.bat" %GNUArcMain% "%TMPDIR%"
  call "%~dp0ExtractArchive.bat" %GNUArcDep% "%TMPDIR%"
  move "%TMPDIR%\bin" "%TMPDIR%\gnu"
  move "%TMPDIR%\gnu\*" "%DEVDIR%\gnu"
  rmdir /S /Q "%TMPDIR%" 2>nul
)

if "/!Path!/"=="/!Path:%DEVDIR%\gnu=!/" set Path=%Path%;%DEVDIR%\gnu
set GNUWIN32=1

:: Cleanup
set GNU32URL=
set GNUURLMain=
set GNUArcMain=
set GNUURLDep=
set GNUArcDep=
set PKGNAM=
set PKGVER=
set PKGBAS=
set URL=
set FileLen=
set FileName=
set FileSize=
set FileURL=
set Flag=
set Folder=
set ArchiveName=

popd

exit /b 0
