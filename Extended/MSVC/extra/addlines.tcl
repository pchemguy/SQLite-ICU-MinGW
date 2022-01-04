#!/usr/bin/tclsh
 
if { $argc != 3 } {
    puts "The '$argv0' script requires three arguments:"
    puts "  - name of the source file,"
    puts "  - name of the file with new lines, starting with a unique line in"
    puts "    the source file, after which the new lines are added, and"
    puts "  - destination directory, where both files are located."
    throw {CMDLINE ARGCOUNT} {Wrong number of arguments.}
}

set SourceName [lindex $argv 0]
set NewLinesName [lindex $argv 1]
cd [lindex $argv 2]
 
set fd [open $SourceName rb]
set Source [read -nonewline $fd]
close $fd
 
set fd [open $NewLinesName rb]
set NewLines [split [read -nonewline $fd] "\n"]
close $fd
 
set AddLinesAfter [string map {"\r" ""} [lindex $NewLines 0]]
set Patched [string map -nocase [list $AddLinesAfter [join $NewLines "\n"]] $Source]
 
set fd [open "${SourceName}.tmp" wb]
puts $fd $Patched
close $fd
 
file rename -force "${SourceName}.tmp" "${SourceName}"
