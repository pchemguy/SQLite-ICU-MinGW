#!/usr/bin/tclsh
 
if { $argc != 3 } {
    puts "The '$argv0' script requires three arguments:"
    puts "  - old text,"
    puts "  - new text, and"
    puts "  - file name."
    throw {CMDLINE ARGCOUNT} {Wrong number of arguments.}
}

set match [string map [list "\\n" "\n"] [lindex $argv 0]]
set replacement [string map [list "\\n" "\n"] [lindex $argv 1]]
set filename [string tolower [lindex $argv 2]]

set fd [open $filename rb]                     
set source [read -nonewline $fd]                      
close $fd                                           
                                                     
set patched [string map -nocase [list $match $replacement] $source]
                                                     
set fd [open "${filename}.tmp" wb]                 
puts $fd $patched                                   
close $fd                                           

file rename -force "${filename}.tmp" "${filename}"
