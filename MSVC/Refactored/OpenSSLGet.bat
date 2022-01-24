@echo off
::
:: Prepares the OpenSSL library and sets build flags.
::
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" (set "ARCH=x64" & set "SYSCONF=VC-WIN64A")
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (set "ARCH=x32" & set "SYSCONF=VC-WIN32")

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMSSL=%BASEDIR%\dev\openssl\%ARCH%
set SRCSSL=%BASEDIR%\bld\openssl\src
set BLDSSL=%BASEDIR%\bld\openssl\%ARCH%
set OUTSSL="%BLDSSL%\opensslout.log"
set ERRSSL="%BLDSSL%\opensslerr.log"
del %OUTSSL% 2>nul
del %ERRSSL% 2>nul
set ResultCode=0


call "%~dp0GNUGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
call "%~dp0PerlGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
call "%~dp0NASMGet.bat"
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
pushd "%PKGDIR%"


set InfoURL=https://www.openssl.org/source/
if not exist "openssl-info.txt" (
  call "%~dp0DownloadFile.bat" "%InfoURL%" "openssl-info.txt"
)

set CommandText=grep.exe -Po "openssl-3.*?.tar.gz" openssl-info.txt
for /f "Usebackq delims=" %%G in (`%CommandText%`) do (
  set PKGNAM=%%~G
  set URLSSL=https://www.openssl.org/source/!PKGNAM!
  goto :URL_SET
)
:URL_SET

:: Download
call "%~dp0DownloadFile.bat" %URLSSL%
if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%

:: Extract
if not exist "%SRCSSL%\Configure" (
  if exist "%SRCSSL%" rmdir /S /Q "%SRCSSL%" 1>nul
  mkdir "%SRCSSL:~0,-4%" 1>nul
  set TARPATTERN=openssl*
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%SRCSSL%\.."
  if not "/%ErrorLevel%/"=="/0/" exit /b %ErrorLevel%
  cd /d "%SRCSSL%\.."
  move "%PKGNAM:.tar.gz=%" "src" 1>nul
)

:: Configure
if not exist "%BLDSSL%\makefile" (
  if exist "%BLDSSL%" rmdir /S /Q "%BLDSSL%" 1>nul
  mkdir "%BLDSSL%" 1>nul
  cd /d "%BLDSSL%"
  echo ===== Configuring OpenSSL =====
  perl "%SRCSSL%\Configure" %SYSCONF% no-tests --prefix="%HOMSSL%\core" ^
    --openssldir="%HOMSSL%\SSL" 1>>%OUTSSL% 2>>%ERRSSL%
  set ResultCode=!ErrorLevel!
  if !ResultCode! EQU 0 (
    echo ----- Configured OpenSSL -----
  ) else (
    echo Error configuring OpenSSL
    echo Errod code: !ResultCode!
  )
) else (
  echo ===== Using previously configured OpenSSL setup =====
)

:: Make
if not exist "%BLDSSL%\libcrypto-3.dll" (
  cd /d "%BLDSSL%"
  echo ===== Making OpenSSL =====
  nmake 1>>%OUTSSL% 2>>%ERRSSL%
  if %ErrorLevel% EQU 0 (
    echo ----- Made OpenSSL -----
  ) else (
    set ResultCode=%ErrorLevel%
    echo Error making OpenSSL
    echo Errod code: !ResultCode!
  )
) else (
  echo ===== Using previously made OpenSSL =====
)

:: Install
if not exist "%HOMSSL%\core\lib\libcrypto.lib" (
  echo ===== Installing OpenSSL =====
  cd /d "%BLDSSL%"
  if exist "%HOMSSL%" rmdir /S /Q "%HOMSSL%" 1>nul
  mkdir "%HOMSSL%" 1>nul
  nmake install 1>>%OUTSSL% 2>>%ERRSSL%
  copy /Y "%BLDSSL%\lib*_static.lib" "%HOMSSL%\core\lib" 1>nul
  echo ----- Installed OpenSSL -----
) else (
  echo ===== Using previously installed OpenSSL =====
)


echo.
echo ============= OpenSSL installation is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured). Check the log files for errors. 
echo.


:: Set building flags
:: /LIBPATH:"%HOMSSL%\core\lib"
set OpenSSL_LIBPATH=%HOMSSL%\core\lib
if "/!LIBPATH!/"=="/!LIBPATH:%OpenSSL_LIBPATH%=!/" set LIBPATH=%OpenSSL_LIBPATH%;%LIBPATH%
:: -I"%HOMSSL%\core\include"
set OpenSSL_INCLUDE=%HOMSSL%\core\include
if "/!INCLUDE!/"=="/!INCLUDE:%OpenSSL_INCLUDE%=!/" set INCLUDE=%OpenSSL_INCLUDE%;%INCLUDE%
set OpenSSL_LIB_IMPORT=libcrypto.lib libssl.lib
set OpenSSL_LIB_STATIC=libcrypto_static.lib libssl_static.lib

echo ========== OpenSSL linking flags ==========
echo OpenSSL_INCLUDE=%OpenSSL_INCLUDE%
echo OpenSSL_LIBPATH=%OpenSSL_LIBPATH%
echo OpenSSL_LIB_STATIC=%OpenSSL_LIB_STATIC%
echo OpenSSL_LIB_IMPORT=%OpenSSL_LIB_IMPORT%
echo ----------------------------------------


:: Cleanup
set HOMSSL=
set SRCSSL=
set BLDSSL=
set OUTSSL=
set ERRSSL=
set InfoURL=

popd

exit /b 0
