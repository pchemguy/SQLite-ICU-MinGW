#!/usr/bin/tclsh
 
if { $argc != 3 } {
    puts "The '$argv0' script requires three arguments:"
    puts "  - name of the source file,"
    puts "  - name of the file with new lines, starting with a unique line in"
    puts "    the source file, after which the new lines are added, and"
    puts "  - destination directory, where both files are located."
    throw {CMDLINE ARGCOUNT} {Wrong number of arguments.}
}

set SourceName [string tolower [lindex $argv 0]]
set NewLinesName [lindex $argv 1]
cd [lindex $argv 2]
 
set fd [open $SourceName rb]
set Source [string map {"\r" ""} [read -nonewline $fd]]
close $fd
 
set fd [open $NewLinesName rb]
set NewLines [split [string map {"\r" ""} [read -nonewline $fd]] "\n"]
close $fd
 
set AddLinesAfter [lindex $NewLines 0]
set Patched [string map -nocase [list $AddLinesAfter [join $NewLines "\n"]] $Source]
 
set from "#ifdef _WIN32\r?\n#endif\r?\n"
set to ""
set Patched [regsub $from $Patched $to]

set fd [open "${SourceName}.tmp" wb]
puts $fd $Patched
close $fd
 
file rename -force "${SourceName}.tmp" "${SourceName}"
