@echo off
:: ============================================================================
:: Starts Microsoft Visual C++ Build Tools (MSVC toolset) shell.
::
:: Addc ICU4C and TCL to the environment:
::   Expected TCL bin location: %PREFIX%\TCL\bin
::   Expected ICU4C-x32 bin location: %PREFIX%\icu4c\bin
::   Expected ICU4C-x64 bin location: %PREFIX%\icu4c\bin64
:: PREFIX points to %ProgramFiles% junction having the same name w/o spaces.
:: ============================================================================

set ARCH=32
if %ARCH%==32 (
  set ICUARCH=
) else (
  set ICUARCH=64
)

set PREFIX=%ProgramFiles: =%

set INCLUDE=%PREFIX%\icu4c\include;%INCLUDE%
set Path=%PREFIX%\icu4c\bin%ICUARCH%;%PREFIX%\TCL\bin;%Path%
set LIB=%PREFIX%\icu4c\lib%ICUARCH%;%LIB%

call "%~dp0VC\Auxiliary\Build\vcvars%ARCH%.bat"

if exist "%~1" (
  cd /d "%~1"
)

%comspec% /k