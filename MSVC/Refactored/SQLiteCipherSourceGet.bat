@echo off
::
:: Downloads SQLite/SQLCipher distro and unpacks it.
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
if /I "/%~1/"=="/SQLCipher/" (set DBENG=sqlcipher) else (set DBENG=sqlite)
set BLDSQL=%BASEDIR%\bld\%DBENG%
set HOMSQL=%BASEDIR%\dev\%DBENG%

set ResultCode=0


if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


if /I "/%DBENG%/"=="/sqlite/" (
  set ReleaseURL=https://www.sqlite.org/src/zip/sqlite.zip
) else (
  set ChangeLogURL=https://github.com/sqlcipher/sqlcipher/raw/master/CHANGELOG.md
  call "%~dp0DownloadFile.bat" !ChangeLogURL!
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  for /f "Usebackq skip=3 tokens=1,2 delims= " %%G in ("!FileName!") do (
    if "/%%G/"=="/##/" (
      set PKGVER=%%H
      set PKGVER=!PKGVER:~1,-1!
      set ReleaseURL=https://codeload.github.com/sqlcipher/sqlcipher/zip/refs/tags/v!PKGVER!
      goto :VERSION_SET
    )
  )
)
:VERSION_SET

:: Download
cd /d "%PKGDIR%"
set PKGNAM=%DBENG%.zip
call "%~dp0DownloadFile.bat" %ReleaseURL% "%PKGNAM%"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

:: Expand
if not exist "%BLDSQL%\Makefile.msc" (
  if exist "%BLDSQL%" rmdir /S /Q "%BLDSQL%" 2>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%BLDDIR%"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
)
if /I "/%DBENG%/"=="/sqlcipher/" (
  cd /d "%BLDDIR%"
  move "sqlcipher-!PKGVER!" "sqlcipher"
)

popd

exit /b 0
