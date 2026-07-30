@echo off

cl /nologo /TC /O2 /LD ^
  /DCTD_C_API ^
  /DCTD_BUILD_LIB ^
  ctd.c ^
  /link /IMPLIB:ctd.lib /OUT:ctd.dll
