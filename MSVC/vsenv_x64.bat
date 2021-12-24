@echo off
:: ============================================================================
:: Starts Microsoft Visual C++ Build Tools (MSVC toolset) shell.
:: ============================================================================

set ARCH=64

call "%~dp0VC\Auxiliary\Build\vcvars%ARCH%.bat"

if exist "%~1" (
  cd /d "%~1"
)

%comspec% /k