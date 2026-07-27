#!/usr/bin/tclsh
#
# copy_here.tcl -- Copy files and directories into the current directory.
#
# Each argument may be:
#   * a literal file path
#   * a literal directory path
#   * a glob pattern matching files and/or directories
#
# Windows paths may use either forward slashes or backslashes. Input
# backslashes are converted to forward slashes before any path processing.
#
# Directories are copied recursively. Existing destinations are replaced.
#
# Usage:
#   tclsh copy_here.tcl PATH_OR_GLOB ?PATH_OR_GLOB ...?
#
# Examples:
#   tclsh copy_here.tcl file1.c include
#   tclsh copy_here.tcl "*.c" "*.h"
#   tclsh copy_here.tcl "B:\src\include\*"
#   tclsh copy_here.tcl "B:/src/include/*"
#
# https://chatgpt.com/c/6a6304a0-4120-83eb-a07a-3138ad187229

proc usage {{channel stdout}} {
    puts $channel "Usage: tclsh copy_here.tcl PATH_OR_GLOB ?PATH_OR_GLOB ...?"
    puts $channel ""
    puts $channel "Copy files, directories, or glob matches into the current directory."
}

proc canonicalPath {path} {
    return [string map {\\ /} [file normalize [string map {\\ /} $path]]]
}

proc expandArgument {argument} {
    set argument [string map {\\ /} $argument]

    if {[file exists $argument]} {
        return [list $argument]
    }

    return [glob -nocomplain -- $argument]
}

if {[llength $argv] == 0} {
    usage stderr
    exit 2
}

if {[llength $argv] == 1 && [lindex $argv 0] in {-h --help}} {
    usage
    exit 0
}

set destinationDir [canonicalPath [pwd]]
set failed 0

array set seen {}

foreach rawArgument $argv {
    set matches [expandArgument $rawArgument]

    if {[llength $matches] == 0} {
        puts stderr "ERROR: No matches: $rawArgument"
        set failed 1
        continue
    }

    foreach matchedPath $matches {
        if {[catch {
            set source [canonicalPath $matchedPath]

            if {[info exists seen($source)]} {
                continue
            }
            set seen($source) 1

            set sourceName [file tail $source]
            if {$sourceName eq ""} {
                error "cannot determine the source name"
            }

            set destination \
                [canonicalPath [file join $destinationDir $sourceName]]

            if {$source eq $destination} {
                error "source is already in the current directory"
            }

            if {[file isdirectory $source]
                    && [string match "${source}/*" $destination]} {
                error "cannot copy a directory into itself"
            }

            # Tcl copies a source directory inside an existing destination
            # directory. Remove the destination first to obtain replacement
            # semantics instead.
            if {[file exists $destination]} {
                file delete -force -- $destination
            }

            file copy -- $source $destination

            puts "Copied: $source -> $destination"
        } message]} {
            puts stderr "ERROR: Cannot copy \"$matchedPath\": $message"
            set failed 1
        }
    }
}

exit $failed
