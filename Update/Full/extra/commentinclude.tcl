#!/usr/bin/tclsh
 
if { $argc != 3 } {
    puts "The '$argv0' script requires three arguments:"
    puts "  - name of the source file,"
    puts "  - name of the included file,"
    puts "  - destination directory."
    throw {CMDLINE ARGCOUNT} {Wrong number of arguments.}
}

set SourceName [string tolower [lindex $argv 0]]
set IncludeName [lindex $argv 1]
cd [lindex $argv 2]
 
set fd [open $SourceName rb]
set Source [read -nonewline $fd]
close $fd

set from "(# *include +\[<\"\]${IncludeName}\[\">\] *)(\r?\n)"
set to "/* \\1 */\\2"
set Patched [regsub $from $Source $to]

set fd [open "${SourceName}.tmp" wb]
puts $fd $Patched
close $fd
 
file rename -force "${SourceName}.tmp" "${SourceName}"
