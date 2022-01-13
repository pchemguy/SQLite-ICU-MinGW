@echo off
:: ============================================================================
:: Collects MSVC environment information.
:: ===========================================================================

:: ================================ BEGIN MAIN ================================
:MAIN
SetLocal EnableExtensions EnableDelayedExpansion

set STDOUTLOG=stdout.log
set STDERRLOG=stderr.log
del "%STDOUTLOG%" 2>nul
del "%STDERRLOG%" 2>nul


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

  echo ==================== CHECKING MSVC TOOLS ====================
  echo =============================================================
  set ErrorStatus=0
  call :CHECKTOOL cl
  call :CHECKTOOL nmake
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "MSVC TOOLS"
  echo -------------------------------------------------------------
  echo.

  echo ======================= CHECKING TCL ========================
  echo =============================================================
  set ErrorStatus=0
  call :CHECKTOOL tclsh
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "TCL"
  echo -------------------------------------------------------------
  echo.

  echo ======================= CHECKING ICU ========================
  echo =============================================================
  set ErrorStatus=0
  call :CHECKTOOL uconv
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "ICU"
  echo -------------------------------------------------------------
  echo.

  echo ============== CHECKING WINDOWS RESOURCE KITS ===============
  echo =============================================================
  set ErrorStatus=0
  call :CHECKSUBSTRING "INCLUDE" "%INCLUDE%" "Windows Kits"
  call :CHECKSUBSTRING "LIB"     "%LIB%"     "Windows Kits"
  call :CHECKSUBSTRING "LIBPATH" "%LIBPATH%" "Windows Kits"
  call :CHECKSUBSTRING "Path"    "%Path%"    "Windows Kits"
  echo -------------------------------------------------------------
  call :CHECKERRORSTATUS "WINDOWS RESOURCE KITS"
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
set VarName=%~1
set VarValue=%~2
if "/%VarValue%/"=="//" (
  set ErrorStatus=1
  echo %%%VarName%%% not set.
) else (
  echo %VarName%=%VarValue%
)

exit /b 0


:: ============================================================================
:CHECKTOOL
:: Call this sub with argument(s):
::   - %1 - Tool executable name
::
set CommandText=where "%~1"
set Output=
for /f "Usebackq delims=" %%i in (`%CommandText%`) do (
  if "/!Output!/"=="//" (
    set Output=%%i
  )
)

if "/%Output%/"=="//" (
  set ErrorStatus=1
  echo "%~1" not found.
) else (
  echo %~1=%Output%
)

exit /b 0


:: ============================================================================
:CHECKSUBSTRING
:: Call this sub with argument(s):
::   - %1 - Variable name
::   - %2 - Variable value
::   - %3 - Substring
::
set VarName=%~1
set VarValue=_%~2_
set Substring=%~3

set TestString=!VarValue:%Substring%=!
if "/%TestString%/"=="/%VarValue%/" (
  set ErrorStatus=1
  echo "%VarName%" does not contain %Substring%.
) else (
  echo "%VarName%" - match found.
)

exit /b 0


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
