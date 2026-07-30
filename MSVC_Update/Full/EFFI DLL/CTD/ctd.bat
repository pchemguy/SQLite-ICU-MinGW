@echo off

set "PROG=ctd"
set "FLAG=CTD"

cl /nologo /TC /O2 /LD ^
    /D%FLAG%_C_API ^
    /D%FLAG%_BUILD_LIB ^
    "%PROG%.c" ^
    /link /IMPLIB:"%PROG%.lib" /OUT:"%PROG%.dll"
