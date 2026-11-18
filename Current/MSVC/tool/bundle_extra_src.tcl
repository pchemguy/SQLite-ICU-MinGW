# bundle_extra_src.tcl -- Expand local C #include directives in place.
#
# Every positional argument must be the file name of a .c or .h file located
# directly in the source directory. Local include names are resolved from
# that source directory, including names that contain subdirectories.
#
# The script first scans the complete reachable include graph without changing
# any file. It rejects missing targets, invalid include paths, and include
# cycles. It then rewrites all discovered files in dependency-first order, so
# an included file is fully expanded before its content is inserted into a
# parent file.
#
# Includes of sqlite3.h and sqlite3ext.h are always replaced with a no-op
# comment. They are never resolved or traversed, even if matching files exist
# in the source directory.
#
# Usage:
#   jimsh0 bundle_extra_src.tcl file.c ?file.h ...?
#
# https://chatgpt.com/c/6a62ecf5-5bb8-83eb-ba7a-7ce302cf962c

set help [string trim {
Usage: jimsh0 bundle_extra_src.tcl FILE...

Expand local #include directives in C sources and headers in place.

Each FILE must be a file name only, have a .c or .h extension, and reside
immediately inside the source directory. Include names are resolved relative
to the source directory, including include names containing subdirectories.

Includes of sqlite3.h and sqlite3ext.h are replaced with no-op comments.
}]

set targets {}

for {set i 0} {$i < [llength $argv]} {incr i} {
  lappend targets [lindex $argv $i]
}

if {[llength $targets] == 0} {
  puts stderr $help
  exit 1
}

set srcdir [file normalize "."]

# 78 stars used for comment formatting.
set s78 \
{*****************************************************************************}

# Return one amalgamator-style section comment.
proc section_comment {text} {
  global s78
  set n [string length $text]
  set nstar [expr {60 - $n}]
  if {$nstar < 0} {
    set nstar 0
  }
  set stars [string range $s78 0 $nstar]
  return "/************** $text $stars/"
}

# Return true if INCLUDE_NAME names a SQLite public header that must become
# a no-op instead of being resolved or expanded.
proc is_sqlite_public_header {includeName} {
  set includeName [string trim $includeName]
  return [expr {
    $includeName eq "sqlite3.h" ||
    $includeName eq "sqlite3ext.h"
  }]
}

# Return a path in the comparison form appropriate for the host platform.
proc path_compare_form {path} {
  if {$::tcl_platform(platform) eq "windows"} {
    set path [string tolower [string map {\\ /} $path]]
  }
  return [string trimright $path /]
}

# Jim resolves an existing final link on Unix. Full Tcl resolves links in
# parent components, so place the link in that position before normalizing.
proc normalize_existing {path} {
  if {$::tcl_platform(engine) eq "Tcl" && [file type $path] eq "link"} {
    return [file dirname [file normalize "$path/__leaf__"]]
  }
  return [file normalize $path]
}

# Return true if PATH is BASE itself or is below BASE.
proc path_is_within {base path} {
  set base [path_compare_form $base]
  set path [path_compare_form $path]
  if {$path eq $base} {
    return 1
  }
  set prefix "${base}/"
  return [string equal -length [string length $prefix] $prefix $path]
}

# Validate one top-level target and return its normalized absolute path.
proc resolve_target {name} {
  global srcdir

  if {[regexp {[/\\]|^[~]|^[A-Za-z]:} $name]} {
    error "target must be a file name only, without a directory: $name"
  }
  if {[lsearch -exact {.c .h} [string tolower [file extension $name]]] < 0} {
    error "target must have a .c or .h extension: $name"
  }

  set path [file join $srcdir $name]
  if {![file isfile $path]} {
    error "target does not exist or is not a regular file: $path"
  }
  set path [normalize_existing $path]
  if {![path_is_within $srcdir $path]} {
    error "target escapes source directory: $name"
  }
  return $path
}

# Resolve an include name relative to the source base directory.
# Return an empty string when it does not name an existing local regular file.
proc resolve_include {includeName includingFile lineNumber} {
  global srcdir

  set includeName [string map {\\ /} $includeName]
  if {[regexp {^[/~]|^[A-Za-z]:} $includeName]} {
    error "$includingFile:$lineNumber: absolute include path is not allowed: $includeName"
  }

  # Jim on Unix can normalize only existing paths. Track missing components
  # lexically so external headers pass through and ".." is still checked.
  set candidate $srcdir
  foreach part [split $includeName /] {
    if {$part eq "" || $part eq "."} { continue }
    if {$part eq ".."} {
      if {[path_compare_form $candidate] eq [path_compare_form $srcdir]} {
        error "$includingFile:$lineNumber: include escapes source directory: $includeName"
      }
      set candidate [file dirname $candidate]
    } else {
      set candidate "[string trimright $candidate /]/$part"
      if {[file exists $candidate]} {
        set candidate [normalize_existing $candidate]
        if {![path_is_within $srcdir $candidate]} {
          error "$includingFile:$lineNumber: include escapes source directory: $includeName"
        }
      }
    }
  }

  if {[file isfile $candidate]} {
    return $candidate
  }
  return ""
}

# Read a file as uninterpreted bytes.
proc read_binary_file {filename} {
  set in [open $filename rb]
  try {
    return [read $in]
  } finally {
    close $in
  }
}

# Choose the file's existing newline convention and whether it ends in one.
proc newline_info {data} {
  if {[string first "\r\n" $data] >= 0} {
    set eol "\r\n"
  } elseif {[string first "\n" $data] >= 0} {
    set eol "\n"
  } elseif {[string first "\r" $data] >= 0} {
    set eol "\r"
  } else {
    set eol "\n"
  }
  set hasFinal [expr {
    [string length $data] > 0 &&
    ([string index $data end] eq "\n" || [string index $data end] eq "\r")
  }]
  return [list $eol $hasFinal]
}

# Convert file data into logical lines without line terminators.
proc logical_lines {data} {
  set normalized [string map [list "\r\n" "\n" "\r" "\n"] $data]
  set lines [split $normalized "\n"]
  if {[llength $lines] > 0 && [lindex $lines end] eq ""} {
    set lines [lrange $lines 0 end-1]
  }
  return $lines
}

# Scan one file and cache all local include edges found in it.
proc scan_file {filename} {
  global scanned includes

  if {[info exists scanned($filename)]} {
    return
  }

  set edges {}
  set lineNumber 0
  foreach line [logical_lines [read_binary_file $filename]] {
    incr lineNumber
    if {[regexp {^\s*#\s*include\s*["<]([^">]+)[">]} \
            $line all includeName]} {
      set includeName [string trim $includeName]

      if {[is_sqlite_public_header $includeName]} {
        continue
      }

      set included [resolve_include $includeName $filename $lineNumber]
      if {$included ne ""} {
        lappend edges [list $lineNumber $includeName $included]
      }
    }
  }

  set includes($filename) $edges
  set scanned($filename) 1

  foreach edge $edges {
    scan_file [lindex $edge 2]
  }
}

# Visit one include-graph node and append it after all of its dependencies.
proc visit_file {filename} {
  global state includes order stack

  if {[info exists state($filename)]} {
    if {$state($filename) == 2} {
      return
    }
    if {$state($filename) == 1} {
      set first [lsearch -exact $stack $filename]
      set cycle [concat [lrange $stack $first end] [list $filename]]
      set names {}
      foreach path $cycle {
        lappend names [file tail $path]
      }
      error "local include cycle detected: [join $names { -> }]"
    }
  }

  set state($filename) 1
  lappend stack $filename
  foreach edge $includes($filename) {
    visit_file [lindex $edge 2]
  }
  set stack [lrange $stack 0 end-1]
  set state($filename) 2
  lappend order $filename
}

# Build replacement data for one already scanned file.
proc expanded_file_data {filename} {
  global includes

  set original [read_binary_file $filename]
  lassign [newline_info $original] eol hasFinal
  set lines [logical_lines $original]
  set edgeByLine {}

  foreach edge $includes($filename) {
    dict set edgeByLine [lindex $edge 0] $edge
  }

  set outputLines {}
  set lineNumber 0

  foreach line $lines {
    incr lineNumber

    if {[regexp {^\s*#\s*include\s*["<]([^">]+)[">]} \
            $line all includeName] &&
        [is_sqlite_public_header $includeName]} {
      lappend outputLines \
          "/* bundle_extra_src: sqlite public header already supplied */"
      continue
    }

    if {![dict exists $edgeByLine $lineNumber]} {
      lappend outputLines $line
      continue
    }

    lassign [dict get $edgeByLine $lineNumber] ignored includeName included
    set includedData [read_binary_file $included]
    set includedLines [logical_lines $includedData]

    lappend outputLines [section_comment "Begin file $includeName"]
    foreach includedLine $includedLines {
      lappend outputLines $includedLine
    }
    lappend outputLines [section_comment "End of $includeName"]
  }

  set result [join $outputLines $eol]
  if {$hasFinal && [llength $outputLines] > 0} {
    append result $eol
  }
  return $result
}

# Jim's forced rename on Windows removes the destination before renaming.
# Retain the original in the same directory until the new name is installed.
proc install_file {tmpPath filename} {
  if {$::tcl_platform(platform) ne "windows" || $::tcl_platform(engine) ne "Jim"} {
    file rename -force $tmpPath $filename
    return
  }
  set backup "$tmpPath.orig"
  file rename $filename $backup
  if {[catch {file rename $tmpPath $filename} message]} {
    if {[catch {file rename $backup $filename} restoreError]} {
      error "$message (original retained at $backup; restore failed: $restoreError)"
    }
    error $message
  }
  file delete $backup
}

# Write and close the staged file before replacing the original.
proc rewrite_file {filename} {
  set original [read_binary_file $filename]
  set expanded [expanded_file_data $filename]
  if {$expanded eq $original} {
    return 0
  }

  # Reserve a sibling file and skip any backup left by an interrupted run.
  for {set n 0} {1} {incr n} {
    set tmpPath "${filename}.$n.tmp"
    if {[file exists "$tmpPath.orig"]} { continue }
    if {![catch {open $tmpPath {WRONLY CREAT EXCL}} tmpChannel]} { break }
    if {![file exists $tmpPath]} { error $tmpChannel }
  }
  try {
    try {
      fconfigure $tmpChannel -translation binary
      puts -nonewline $tmpChannel $expanded
      flush $tmpChannel
    } finally {
      close $tmpChannel
    }
    install_file $tmpPath $filename
  } on error {message options} {
    catch {file delete $tmpPath}
    return {*}$options $message
  }

  return 1
}

array set scanned {}
array set includes {}
array set state {}
set roots {}
set order {}
set stack {}

# Phase 1: validate targets and scan the complete graph without changing files.
foreach target $targets {
  set path [resolve_target $target]
  if {[lsearch -exact $roots $path] < 0} {
    lappend roots $path
  }
}
foreach root $roots {
  scan_file $root
}

# Phase 2: produce a dependency-first order and reject cycles before writing.
foreach root $roots {
  visit_file $root
}

# Phase 3: patch every discovered source in place, leaves before parents.
set changed 0
foreach filename $order {
  if {[rewrite_file $filename]} {
    incr changed
    puts "patched [file tail $filename]"
  }
}

puts "bundle complete: [llength $order] file(s) scanned, $changed file(s) patched"
