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

set match "\\s*#\\s*include\\s+\[<\"\]${IncludeName}\[\">\]\\s*\r?\n"
regexp -nocase -indices	$match $Source location


if {[info exists location]} {
  regexp "\r?\n" $Source EOL
  set EOL "${EOL}${EOL}"
  set LeftStars [expr 35 - [string length ${IncludeName}] / 2]
  set RightStars [expr 70 - [string length ${IncludeName}] - ${LeftStars}]
  set LeftStars "${EOL}/[string repeat "*" ${LeftStars}]"
  set RightStars "[string repeat "*" ${RightStars}]/${EOL}"
  set BegInc "${LeftStars} BEGIN [string toupper ${IncludeName}] ${RightStars}"
  set EndInc "${LeftStars}* END [string toupper ${IncludeName}] *${RightStars}"

  set fd [open $IncludeName rb]
  set Include "${BegInc}[read -nonewline $fd]${EndInc}"
  close $fd

  set Patched [string replace $Source [lindex $location 0] [lindex $location 1] ${Include}]

  set fd [open "${SourceName}.tmp" wb]
  puts $fd $Patched
  close $fd
 
  file rename -force "${SourceName}.tmp" "${SourceName}"
}
