#!/usr/bin/tclsh
#
set Filename [file join [file dirname [info script]] crypto_openssl_p.h]
set fd [open ${Filename} rb]
set Hdr [string map {"\r" ""} [read -nonewline $fd]]
close $fd

set Pattern {SQLITE_APICALL [^(\n]*?\(}
set FuncNames [split [string map -nocase [list "SQLITE_APICALL " "" "_p(" "" " " "\n"] [join [regexp -all -inline $Pattern $Hdr] " "]] "\n"]

set MapList {"#include \"crypto.h\"" "#include \"crypto.h\"\n#include \"crypto_openssl_p.h\""}
foreach FuncName $FuncNames {
  lappend MapList "${FuncName}(" "${FuncName}_p("
}

set Filename [file join [file dirname [info script]] crypto_openssl.c]
set fd [open ${Filename} rb]
set Source [string map {"\r" ""} [read -nonewline $fd]]
close $fd

set Patched [string map -nocase $MapList $Source]

set from "(# *include +\[<\"\]openssl/\[^\">\]*?\[\">\] *)(\r?\n)"
set to "/* \\1 */\\2"
set Patched [regsub -all $from $Patched $to]

                                                     
set fd [open "${Filename}.tmp" wb]                 
puts $fd $Patched                                   
close $fd                                           

file rename -force "${Filename}.tmp" "${Filename}"
