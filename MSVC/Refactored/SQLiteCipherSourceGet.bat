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
set SRCSQL=%BASEDIR%\bld\%DBENG%\src

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
if not exist "%SRCSQL%\Makefile.msc" (
  if exist "%SRCSQL%" rmdir /S /Q "%SRCSQL%" 1>nul
  if not exist "%SRCSQL:~0,-4%" mkdir "%SRCSQL:~0,-4%" 1>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%SRCSQL:~0,-4%"
  if not "/!ErrorLevel!/"=="/0/" exit /b !ErrorLevel!
  cd /d "%SRCSQL%\.."
  if /I "/%DBENG%/"=="/sqlcipher/" (
    move "sqlcipher-!PKGVER!" "src"
  ) else (
    move "sqlite" "src"
  )
)
:: ext\misc\json1.c => src\json.c refactoring fix for SQLCipher. Remove it when
:: SQLCipher upgrades its base SQLite distro (to 3.37 or 3.38 - check above)
if exist "%SRCSQL%\ext\misc\json1.c" if not exist "%SRCSQL%\src\json.c" (
  copy /Y "%SRCSQL%\ext\misc\json1.c" "%SRCSQL%\src\json.c"
)

popd

exit /b 0
