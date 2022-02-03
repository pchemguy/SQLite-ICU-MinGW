@echo off
::
:: Downloads and extracts a package from the MSYS/MSYS2 repo.
::
:: Arguments:
::   %1 - Full package name
::   %2 - Architecture - x32/x86 or x64/AMD64
::     (optional; uses %ARCH% then %PROCESSOR_ARCHITECTURE% by default).
::
:: On failure:
::   ResultCode <> 0
::
:: Examples:
::   MSYS2pkgGet.bat bash
::
:: SHELL: CMD Or MSVC Build Tools
::
SetLocal

set ResultCode=0
if not defined GNUWIN32 (
  call "%~dp0GNUGet.bat" 1>nul
  set ResultCode=!ErrorLevel!
  if not "/!ResultCode!/"=="/0/" (
    echo GNUGet.bat error.
    echo -----------------
    goto :EOS
  )
)
call "%~dp0MSYS2pkgURL.bat" %*
set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo MSYS2pkgURL.bat error.
  echo ----------------------
  goto :EOS
)

set BASEDIR=%~dp0
set BASEDIR=%BASEDIR:~0,-1%
set PKGDIR=%BASEDIR%\pkg
set TMPDIR=%BASEDIR%\tmp
set DEVDIR=%BASEDIR%\dev
set PKGMSYS=%PKGDIR%\msys2
set HOMMSYS=%DEVDIR%\msys2
set PKGMETA=%PKGDIR%\msys2\msys

if not exist "%PKGMSYS%" mkdir "%PKGMSYS%"
pushd "%PKGMSYS%"


call "%~dp0DownloadFile.bat" %PKGURL%
set ResultCode=%ErrorLevel%
if not "/%ResultCode%/"=="/0/" (
  echo DownloadFile.bat error!
  echo ----------------------
  goto :EOS
)
set PKGNAM=%FileName%
set TOOLNAME=%~1

set PKGINFO=%PKGMETA%\%TOOLNAME%\.PKGINFO
if not exist "%PKGINFO%" (
  echo ===== Installing %TOOLNAME% =====
  (
    if exist "%TMPDIR%" rmdir /S /Q "%TMPDIR%"
    mkdir "%TMPDIR%"
    if not exist "%HOMMSYS%" mkdir "%HOMMSYS%"
  ) 1>nul
  call "%~dp0ExtractArchive.bat" %PKGNAM% "%TMPDIR%"
  set ResultCode=!ErrorLevel!
  if not "/!ResultCode!/"=="/0/" (
    echo ExtractArchive.bat error!
    echo -------------------------
    goto :EOS
  )

  (
    if not exist "%PKGMETA%\%TOOLNAME%" mkdir "%PKGMETA%\%TOOLNAME%"
    move "%TMPDIR%\.*" "%PKGMETA%\%TOOLNAME%"
    xcopy /H /Y /B /E /Q "%TMPDIR%\*" "%HOMMSYS%"
    rmdir /S /Q "%TMPDIR%"
  ) 1>nul
  echo ----- Installed  %~1 -----
  echo --------------------------

  echo ===== Installing dependencies =====
  set CommandText=grep.exe "^depend = " "%PKGINFO%"
  for /f "Usebackq delims=" %%G in (`!CommandText!`) do (
    set PKGDPD=%%G
    set PKGDPD=!PKGDPD:~9!
    if not exist "%HOMMSYS%\usr\bin\!PKGDPD!.exe" (
      echo ----- Parent: [%TOOLNAME%] -----
      call "%~0" !PKGDPD! %2
      set ResultCode=!ErrorLevel!
    ) else set ResultCode=0
    if not "/!ResultCode!/"=="/0/" (
      echo Error installing !PKGDPD!
      echo -------------------------
      goto :EOS
    )
  )
  echo ----- Installed  dependencies -----
) else (
  echo ===== %~1 already installed =====
)


:EOS

:: Cleanup
set PKGMSYS=
set PKGMETA=
set HOMMSYS=
set PKGINFO=
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

EndLocal & exit /b %ResultCode%
