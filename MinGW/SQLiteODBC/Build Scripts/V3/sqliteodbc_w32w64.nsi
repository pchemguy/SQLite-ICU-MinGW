; NSIS Config (http://nsis.sf.net)
;
; Run it with
;
;    .../makensis [-DWITH_SOURCES] [-DWITH_SQLITE_DLLS] this-file.nsi
;
; to create the installer sqliteodbc.exe
;
; If -DWITH_SOURCES is specified, source code is included.
; If -DWITH_SQLITE_DLLS is specified, separate SQLite DLLs
; are packaged which allows to exchange these independently
; of the ODBC drivers in the Win32 system folder.

; -------------------------------
; Start


!if "$%MSYSTEM%" == "MINGW32"
    !define WinBitType 32
!else
    !define WinBitType 64
!endif

BrandingText " "
!ifdef WITH_SEE
  !define SOFT_NAME "SQLite ODBC Driver (SEE)"
!else
  !define SOFT_NAME "SQLite ODBC Driver"
!endif
Name "${SOFT_NAME}"

!define PROD_NAME  "${SOFT_NAME} for Win${WinBitType}"
!define PROD_NAME0 "${PROD_NAME}"
CRCCheck On
!include "MUI.nsh"
!include "Sections.nsh"
 
;--------------------------------
; General
 
OutFile "sqliteodbc_w${WinBitType}.exe"
 
;--------------------------------
; Folder selection page
 
InstallDir "$PROGRAMFILES${WinBitType}\${SOFT_NAME}"
 
;--------------------------------
; Modern UI Configuration

!define MUI_ICON "sqliteodbc.ico"
!define MUI_UNICON "sqliteodbc.ico" 
!define MUI_WELCOMEPAGE_TITLE "SQLite ODBC for Win${WinBitType} Installation"
!define MUI_WELCOMEPAGE_TEXT "This program will guide you through the \
installation of SQLite ODBC Driver.\r\n\r\n$_CLICK"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "license.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_TITLE "SQLite ODBC for Win${WinBitType} Installation"  
!define MUI_FINISHPAGE_TEXT "The installation of SQLite ODBC Driver is complete.\
\r\n\r\n$_CLICK"

!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
 
;--------------------------------
; Language
 
!insertmacro MUI_LANGUAGE "English"
 
;--------------------------------
; Installer Sections

Section "-Main (required)" InstallationInfo
 
; Add files
 SetOutPath "$INSTDIR"
!ifdef WITH_SEE
 File "sqlite3odbc${WITH_SEE}.dll"
 File "sqlite3odbc${WITH_SEE}.def"
 File "libsqlite3odbc${WITH_SEE}.a"
!else
 File "sqlite3odbc.dll"
 File "sqlite3odbc.def"
 File "libsqlite3odbc.a"
!endif
!ifndef WITHOUT_SQLITE3_EXE
 File "sqlite3.exe"
!endif
!ifdef WITH_SQLITE_DLLS
 File "sqlite3.dll"
!endif
!ifdef WITH_ICU
 File /nonfatal lib*.dll
!endif
 File "insta.exe"
 File "instq.exe"
 File "uninst.exe"
 File "uninstq.exe"
 File "adddsn.exe"
 File "remdsn.exe"
 File "addsysdsn.exe"
 File "remsysdsn.exe"
 File "SQLiteODBCInstaller.exe"
 File "license.txt"
 File "readme.txt"

; Shortcuts
 SetShellVarContext all
 !define SMROOT "$SMPROGRAMS\${PROD_NAME0}"
 SetOutPath "${SMROOT}"
 CreateShortCut "${SMROOT}\Re-install ODBC Drivers.lnk" \
   "$INSTDIR\insta.exe"
 CreateShortCut "${SMROOT}\Remove ODBC Drivers.lnk" \
   "$INSTDIR\uninst.exe"
 CreateShortCut "${SMROOT}\Uninstall.lnk" \
   "$INSTDIR\uninstall.exe"
 CreateShortCut "${SMROOT}\View README.lnk" \
   "$INSTDIR\readme.txt"
!ifndef WITHOUT_SQLITE3_EXE
 SetOutPath "${SMROOT}\Shells"
 CreateShortCut "${SMROOT}\Shells\SQLite 3.lnk" \
   "$INSTDIR\sqlite3.exe"
!endif
 
; Write uninstall information to the registry
 WriteRegStr HKLM \
  "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PROD_NAME0}" \
  "DisplayName" "${PROD_NAME} (remove only)"
 WriteRegStr HKLM \
  "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PROD_NAME0}" \
  "UninstallString" "$INSTDIR\Uninstall.exe"

 SetOutPath "$INSTDIR"
 WriteUninstaller "$INSTDIR\Uninstall.exe"

 ExecWait '"$INSTDIR\instq.exe"'

SectionEnd

;--------------------------------
; Uninstaller Section

Section "Uninstall"

ExecWait '"$INSTDIR\uninstq.exe"'
 
; Delete Files 
RMDir /r "$INSTDIR\*" 
RMDir /r "$INSTDIR\*.*" 
 
; Remove the installation directory
RMDir /r "$INSTDIR"

; Remove start menu/program files subdirectory

SetShellVarContext all
RMDir /r "$SMPROGRAMS\${PROD_NAME0}"
  
; Delete Uninstaller And Unistall Registry Entries
DeleteRegKey HKEY_LOCAL_MACHINE "SOFTWARE\${PROD_NAME0}"
DeleteRegKey HKEY_LOCAL_MACHINE \
    "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PROD_NAME0}"
  
SectionEnd
 
;--------------------------------
; EOF
