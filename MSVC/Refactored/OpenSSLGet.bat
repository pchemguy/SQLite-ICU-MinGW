@echo off
::
:: Prepares the OpenSSL library and sets build flags.
::
set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set BLDDIR=%BASEDIR%\bld
set DEVDIR=%BASEDIR%\dev
set HOMSSL=%BASEDIR%\dev\openssl
set BLDSSL=%BASEDIR%\bld\openssl
set OUTSSL="%BASEDIR%\opensslout.log"
set ERRSSL="%BASEDIR%\opensslerr.log"
del %OUTSSL% 2>nul
del %ERRSSL% 2>nul
set ResultCode=0

call "%~dp0GNUGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
call "%~dp0PerlGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
call "%~dp0NASMGet.bat"
if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)

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
if not exist "%BLDSSL%-src\Configure" (
  if exist "%BLDSSL%-src" rmdir /S /Q "%BLDSSL%-src" 2>nul
  set TARPATTERN=openssl*
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%BLDDIR%"
  if not "/%ErrorLevel%/"=="/0/" (set ResultCode=%ErrorLevel%)
  cd /d "%BLDDIR%"
  move "%PKGNAM:.tar.gz=%" "openssl-src"
)

if "/%VSCMD_ARG_TGT_ARCH%/"=="/x64/" (set "ARCH=x64" & set "SYSCONF=VC-WIN64A")
if "/%VSCMD_ARG_TGT_ARCH%/"=="/x86/" (set "ARCH=x32" & set "SYSCONF=VC-WIN32")

:: Configure
set BLDBLD=%BLDSSL%-bld\%ARCH%
set HOMHOM=%HOMSSL%\%ARCH%
(
  if not exist "%BLDBLD%\makefile" (
    if exist "%BLDBLD%" rmdir /S /Q "%BLDBLD%" 2>nul
    mkdir "%BLDBLD%" 2>nul
    cd /d "%BLDBLD%"
    echo ===== Configuring OpenSSL =====
    perl "%BLDSSL%-src\Configure" %SYSCONF% ^
      --prefix="%HOMHOM%\core" --openssldir="%HOMHOM%\SSL" 
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
) 1>>%OUTSSL% 2>>%ERRSSL%

:: Make
( 
  if not exist "%BLDBLD%\libcrypto-3.dll" (
    cd /d "%BLDBLD%"
    echo ===== Making OpenSSL =====
    nmake
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
) 1>>%OUTSSL% 2>>%ERRSSL%

:: Install
( 
  if not exist "%HOMHOM%\core\lib\libcrypto.lib" (
    echo ===== Installing OpenSSL =====
    cd /d "%BLDBLD%"
    if exist "%HOMHOM%" rmdir /S /Q "%HOMHOM%" 2>nul
    mkdir "%HOMHOM%" 2>nul
    nmake install
    copy /Y "%BLDBLD%\lib*_static.lib" "%HOMHOM%\core\lib"
    echo ----- Installed OpenSSL -----
  ) else (
    echo ===== Using previously installed OpenSSL =====
  )
) 1>>%OUTSSL% 2>>%ERRSSL%


echo.
echo ============= OpenSSL installation is complete. ============
echo ResultCode: %ResultCode% (^>0 - errors occured). Check the log files for errors. 
echo.


:: Set building flags
:: /LIBPATH:"%HOMHOM%\core\lib"
set OpenSSL_LIBPATH=%HOMHOM%\core\lib
if "/!LIBPATH!/"=="/!LIBPATH:%OpenSSL_LIBPATH%=!/" set LIBPATH=%OpenSSL_LIBPATH%;%LIBPATH%
:: -I"%HOMHOM%\core\include"
set OpenSSL_INCLUDE=%HOMHOM%\core\include
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
set BLDSSL=
set OUTSSL=
set ERRSSL=
set InfoURL=
set BLDBLD=
set HOMHOM=

popd

exit /b 0
