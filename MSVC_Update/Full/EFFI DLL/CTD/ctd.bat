@echo off

set "SOURCE=ctd.c"
set "LIBOUT=ctd.lib"
set "DLLOUT=ctd.dll"
set "PREFIX=CTD"
set FLAGS=^
    /D%PREFIX%_C_API ^
    /D%PREFIX%_BUILD_LIB

cl /nologo /TC /O2 /LD ^
    %FLAGS% ^
    "%SOURCE%" ^
    /link /IMPLIB:"%LIBOUT%" /OUT:"%DLLOUT%"
