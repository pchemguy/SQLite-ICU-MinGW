#!/usr/bin/tclsh
#
# Arg0 - Target file name
# Remianing args - List of substrings (<old> <new> )*
 
set filename [lindex $argv 0]
set maplist [lrange $argv 1 end]

set fd [open $filename rb]                     
set source [read -nonewline $fd]                      
close $fd                                           
                                                     
set patched [string map -nocase $maplist $source]
                                                     
set fd [open "${filename}.tmp" wb]                 
puts $fd $patched                                   
close $fd                                           

file rename -force "${filename}.tmp" "${filename}"
