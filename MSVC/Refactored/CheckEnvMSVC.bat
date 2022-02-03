@echo off
:: ============================================================================
:: Collects MSVC environment information.
:: SHELL: MSVC Build Tools
:: ===========================================================================

:: ================================ BEGIN MAIN ================================
:MAIN

set STDOUTLOG=stdout.log
set STDERRLOG=stderr.log
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul

if "/%VSCMD_ARG_TGT_ARCH%/" == "/x64/" (set ARCH=x64)
if "/%VSCMD_ARG_TGT_ARCH%/" == "/x86/" (set ARCH=x32)
if not defined DEVDIR (set DEVDIR=%~dp0dev)

if exist CheckDelayedExpansion.bat (
  call CheckDelayedExpansion.bat
) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"

SetLocal EnableExtensions EnableDelayedExpansion

(
  call :TIMESTAMP

  echo ======================= SHELL SETTINGS ======================
  echo =============================================================
  echo  DESIRED VALUES:
  echo     EnableExtensions    REG_DWORD    0x1
  echo     DelayedExpansion    REG_DWORD    0x1
  echo.
  echo  ACTUAL  VALUES:
  reg query "HKLM\Software\Microsoft\Command Processor" /s /f nsion
  echo -------------------------------------------------------------
  echo.

  echo ==================== CHECKING MSVC TOOLS ====================
  echo =============================================================
  set ErrorStatus=0
  call :CHECKTOOL cl
  call :CHECKTOOL nmake
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "MSVC TOOLS"
  echo -------------------------------------------------------------
  echo.

  echo ================== CHECKING MSVC VARIABLES ==================
  echo =============================================================
  set ErrorStatus=0
  call :CHECKVAR "VisualStudioVersion" "%VisualStudioVersion%"
  call :CHECKVAR "VSINSTALLDIR" "%VSINSTALLDIR%"
  call :CHECKVAR "VCINSTALLDIR" "%VCINSTALLDIR%"
  call :CHECKVAR "VCToolsInstallDir" "%VCToolsInstallDir%"
  call :CHECKVAR "VCToolsVersion" "%VCToolsVersion%"
  call :CHECKVAR "VSCMD_ARG_HOST_ARCH" "%VSCMD_ARG_HOST_ARCH%"
  call :CHECKVAR "VSCMD_ARG_TGT_ARCH" "%VSCMD_ARG_TGT_ARCH%"
  call :CHECKVAR "VSCMD_VER" "%VSCMD_VER%"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "MSVC VARIABLES"
  echo -------------------------------------------------------------
  echo.

  echo ============== CHECKING WINDOWS RESOURCE KITS ===============
  echo =============================================================
  set ErrorStatus=0
  call :CHECKSUBSTRING "INCLUDE" "%INCLUDE%" "Windows Kits"
  call :CHECKSUBSTRING "LIB"     "%LIB%"     "Windows Kits"
  call :CHECKSUBSTRING "LIBPATH" "%LIBPATH%" "Windows Kits"
  call :CHECKSUBSTRING "Path"    "%Path%"    "Windows Kits"

  call :CHECKVAR "WindowsSdkDir"        "%WindowsSdkDir%"
  call :CHECKVAR "WindowsSdkBinPath"    "%WindowsSdkBinPath%"
  call :CHECKVAR "WindowsSDKVersion"    "%WindowsSDKVersion%"
  call :CHECKVAR "WindowsSDKLibVersion" "%WindowsSDKLibVersion%"
  call :CHECKVAR "WindowsSdkVerBinPath" "%WindowsSdkVerBinPath%"
  call :CHECKVAR "WindowsSDK_ExecutablePath_x64" ^
                 "%WindowsSDK_ExecutablePath_x64%"
  call :CHECKVAR "WindowsSDK_ExecutablePath_x86" ^
                 "%WindowsSDK_ExecutablePath_x86%"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "WINDOWS RESOURCE KITS"
  echo -------------------------------------------------------------
  echo.

  echo ====================== CHECKING DOTNET ======================
  echo =============================================================
  set ErrorStatus=0
  call :CHECKVAR "FrameworkDir"       "%FrameworkDir%"
  call :CHECKVAR "FrameworkDir32"     "%FrameworkDir32%"
  call :CHECKVAR "FrameworkVersion"   "%FrameworkVersion%"
  call :CHECKVAR "FrameworkVersion32" "%FrameworkVersion32%"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "DOTNET"
  echo -------------------------------------------------------------
  echo.

  echo ======================= CHECKING TCL ========================
  echo =============================================================
  set ErrorStatus=0
  if not defined TCL_HOME (set TCL_HOME=%DEVDIR%\TCL)
  call :CHECKTOOL tclsh "!TCL_HOME!\bin"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "TCL"
  echo -------------------------------------------------------------
  echo.

  echo ======================= CHECKING ICU ========================
  echo =============================================================
  set ErrorStatus=0
  if not defined ICU_HOME (set ICU_HOME=%DEVDIR%\icu4c)
  call :CHECKTOOL uconv "!ICU_HOME!\bin"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "ICU"
  echo -------------------------------------------------------------
  echo.

  echo ====================== CHECKING NASM ========================
  echo =============================================================
  set ErrorStatus=0
  if not defined NASM_HOME (set NASM_HOME=%DEVDIR%\nasm\%ARCH%)
  call :CHECKTOOL nasm "!NASM_HOME!"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "NASM"
  echo -------------------------------------------------------------
  echo.

  echo ====================== CHECKING PERL ========================
  echo =============================================================
  set ErrorStatus=0
  if not defined PERL_HOME (set PERL_HOME=%DEVDIR%\Perl)
  call :CHECKTOOL perl "!PERL_HOME!\bin"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "PERL"
  echo -------------------------------------------------------------
  echo.

  echo ==================== CURRENT ENVIRONMENT ====================
  echo =============================================================
  set
  echo -------------------------------------------------------------
  echo.

) 1>>"%STDOUTLOG%" 2>>"%STDERRLOG%"


EndLocal
exit /b 0
:: ================================= END MAIN =================================


:: ============================================================================
:CHECKVAR
:: Call this sub with argument(s):
::   - %1 - Variable name
::   - %2 - Variable value
::
SetLocal

set VarName=%~1
set "VarValue=%~2"
if "/%VarValue%/"=="//" (
  set ErrorStatus=1
  echo %%%VarName%%% not set.
) else (
  set ErrorStatus=0
  echo %VarName%=!VarValue!
)

popd
EndLocal & exit /b %ErrorStatus%


:: ============================================================================
:CHECKTOOL
:: Call this sub with argument(s):
::   - %1 - Tool executable name
::   - %2 - CD before check
::
SetLocal

set TOOLEXE=%~1
if exist "%~2" (set TARGETDIR=%~2) else (set TARGETDIR=.)
pushd "%TARGETDIR%"

set CommandText=where "%TOOLEXE%" 2^^^>nul
set Output=
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!Output!/"=="//" (
    set Output=%%i
  )
)

if "/%Output%/"=="//" (
  set ErrorStatus=1
  echo "%TOOLEXE%" not found.
) else (
  set ErrorStatus=0
  echo %TOOLEXE% location: %Output%
)

popd
EndLocal & set "TOOLPATH=%Output%" & exit /b %ErrorStatus%


:: ============================================================================
:CHECKSUBSTRING
:: Call this sub with argument(s):
::   - %1 - Variable name
::   - %2 - Variable value
::   - %3 - Substring
::
SetLocal


set VarName=%~1
set VarValue=_%~2_
set Substring=%~3

set TestString=!VarValue:%Substring%=!
if "/%TestString%/"=="/%VarValue%/" (
  set ErrorStatus=1
  echo "%VarName%" does not contain %Substring%.
) else (
  set ErrorStatus=0
  echo "%VarName%" - match found.
)

popd
EndLocal & exit /b %ErrorStatus%


:: ============================================================================
:CHECKERRORSTATUS
:: Call this sub with argument(s):
::   - %1 - Test name
::
if %ErrorStatus% NEQ 0 (
  echo #################### Test %~1 failed. ####################
) else (
  echo ~~~~~~~~~~~~~~~~~~~~ Test %~1 passed. ~~~~~~~~~~~~~~~~~~~~
)

exit /b 0


:: ============================================================================
:TIMESTAMP
::
set CommandText=time /T
set Output=
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!Output!/"=="//" (
    set Output=%%i
  )
)
set CurTime=%Output%

set CommandText=date /T
set Output=
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!Output!/"=="//" (
    set Output=%%i
  )
)
set CurDate=%Output%

echo ==================== %CurDate% %CurTime% ====================
echo.

exit /b 0
