@echo off

set "USE_ICU=1"
set "USE_ZLIB=0"
set "SQLITE_EXTRA=0"

call "%~dp0sqlite_msbuild.bat"
