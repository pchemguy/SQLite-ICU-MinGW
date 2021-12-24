@echo off
:: ============================================================================
:: Starts Microsoft Visual C++ Build Tools (MSVC toolset) shell.
::
:: Addc ICU4C and TCL to the environment:
::   Expected TCL bin location: %ProgramFiles%\TCL\bin
::   Expected ICU4C-x32 bin location: %ProgramFiles%\icu4c\bin
::   Expected ICU4C-x64 bin location: %ProgramFiles%\icu4c\bin64
:: ============================================================================

set INCLUDE=%ProgramFiles%\icu4c\include;%INCLUDE%
set Path=%ProgramFiles%\icu4c\bin64;%ProgramFiles%\TCL\bin;%Path%
set LIB=%ProgramFiles%\icu4c\lib64;%LIB%

call "%~dp0VC\Auxiliary\Build\vcvars64.bat"

if exist "%~1" (
  cd /d "%~1"
)

%comspec% /k