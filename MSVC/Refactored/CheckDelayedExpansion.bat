@echo off
::
:: This script checks if EnableDelayedExpansion is set and sets:
::   ErrorStatus=0, if EnableDelayedExpansion is ON,
::   ErrorStatus=1, if EnableDelayedExpansion is OFF
:: It returns ErrorStatus as ErrorLevel.
::
:: SHELL: CMD Or MSVC Build Tools
::
set $$$$$$$=$$$$$$$

if "/%$$$$$$$%/"=="/!$$$$$$$!/" (
  echo ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Test EnableDelayedExpansion PASSED. ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  set ErrorStatus=0
) else (
  echo.
  echo ############################## Test EnableDelayedExpansion FAILED. ##############################
  echo DelayedExpansion is disabled.
  echo Either enable this feature globally by running the following commands from an admin shell:
  echo   ^>reg add "HKLM\Software\Microsoft\Command Processor" /f /v EnableExtensions /t REG_DWORD /d 1
  echo   ^>reg add "HKLM\Software\Microsoft\Command Processor" /f /v DelayedExpansion /t REG_DWORD /d 1
  echo or wrap the batch script code in
  echo   SetLocal EnableDelayedExpansion EnableExtensions
  echo     rem Code using DelayedExpansion in here.
  echo   EndLocal
  echo -------------------------------------------------------------------------------------------------
  echo.
  set ErrorStatus=1
)

exit /b %ErrorStatus%

