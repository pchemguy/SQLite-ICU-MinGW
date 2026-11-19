# bundle_extra_src.tcl -- Inline local C headers and sources in SQLite's tsrc tree.
#
# Run from tsrc with SQLite's jimsh0 or Tcl 8.6. Pass one or more .c or .h
# filenames directly in that directory. The script itself may live elsewhere.
#
#   jimsh0 path/to/bundle_extra_src.tcl FILE...
#
# Both #include "name" and #include <name> resolve from the current working
# directory, even inside a subdirectory header. An existing local regular file
# is expanded at each include site. Other valid relative includes pass through
# for the compiler. Only the bare names sqlite3.h and sqlite3ext.h become
# no-op comments, even when those files exist locally.
#
# The scan recognizes literal directives across backslash-newline splices and
# respects C comments and quoted literals. It scans all conditional branches
# and leaves macro-based includes for the compiler. An embedded copy replaces
# a literal #pragma once with a comment. The source header retains its pragma.
#
# Before writing, the script checks the targets, include paths, and reachable
# graph for errors, including cycles. It then patches changed files in place,
# dependencies first, including headers discovered below tsrc. The script
# preserves bytes outside each replacement, including mixed line endings.
#
# stderr traces each scan, expansion, staging, and installation by default.
# Set BUNDLE_EXTRA_SRC_TRACE=0 to disable tracing. Patched filenames and the
# final counts of scanned and patched files go to stdout.
#
# https://chatgpt.com/c/6a62ecf5-5bb8-83eb-ba7a-7ce302cf962c

set help [string trim {
Usage: jimsh0 path/to/bundle_extra_src.tcl FILE...

Run from tsrc. Each FILE must be a .c or .h filename in the current directory.
Quoted and angle-bracket includes resolve from tsrc at every nesting level.
The script patches changed targets and their local dependencies in place.
Includes of the bare names sqlite3.h and sqlite3ext.h become no-op comments.

Tracing goes to stderr by default. Set BUNDLE_EXTRA_SRC_TRACE=0 to disable it.
Patched filenames and the final counts go to stdout.
}]

set targets {}

for {set i 0} {$i < [llength $argv]} {incr i} {
  lappend targets [lindex $argv $i]
}

if {[llength $targets] == 0} {
  puts stderr $help
  exit 1
}

set traceBundle [expr {
  ![info exists ::env(BUNDLE_EXTRA_SRC_TRACE)] || $::env(BUNDLE_EXTRA_SRC_TRACE) eq "1"
}]
proc trace_file {operation filename} {
  if {$::traceBundle} {
    puts stderr "$operation [source_name $filename]"
    flush stderr
  }
}

set srcdir [file normalize "."]

# Padding for SQLite-style section comments.
set s78 \
{*****************************************************************************}

# Return one amalgamator-style section comment.
proc section_comment {text} {
  global s78
  set text [string map [list "/*" "**" "*/" "**"] $text]
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

# All graph paths have already been normalized beneath the source directory.
proc source_name {path} {
  global srcdir
  return [string range $path [string length "[string trimright $srcdir /]/"] end]
}

# Use the same graph node for Windows spellings that differ only in case.
proc graph_path {path} {
  global spelling
  if {$::tcl_platform(platform) ne "windows"} { return $path }
  set key [path_compare_form $path]
  if {![info exists spelling($key)]} { set spelling($key) $path }
  return $spelling($key)
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
  return [graph_path $path]
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
    return [graph_path $candidate]
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

# Split file data into physical lines without line terminators.
proc physical_lines {data} {
  set normalized [string map [list "\r\n" "\n" "\r" "\n"] $data]
  set lines [split $normalized "\n"]
  if {[llength $lines] > 0 && [lindex $lines end] eq ""} {
    set lines [lrange $lines 0 end-1]
  }
  return $lines
}

# Return a recognized directive from a spliced line. Mask comments with spaces
# to retain source positions. Quoted literals protect their comment markers.
proc read_directive {line blockVar} {
  upvar 1 $blockVar inBlock
  set clean $line
  set pos 0
  if {$inBlock || [string first "/*" $line] >= 0 || [string first "//" $line] >= 0} {
    set tokenRE {["'<]|/\*|//}
    while {$pos < [string length $line]} {
      if {!$inBlock} {
        if {![regexp -indices -start $pos $tokenRE $line token]} { break }
        lassign $token first last
        set pos [expr {$last + 1}]
        switch -- [string index $line $first] {
          < {
            # An angle-delimited header name is one preprocessing token.
            if {[regexp {^\s*#\s*include\s*$} [string range $clean 0 $first-1]]} {
              set end [string first ">" $line $pos]
              if {$end >= 0} { set pos [expr {$end + 1}] }
            }
            continue
          }
          / {
            if {[string index $line $last] eq "/"} {
              set clean [string range $clean 0 $first-1]
              break
            }
            set inBlock 1
          }
          default {
            # Skip the literal without a recursive regexp on long C strings.
            set quote [string index $line $first]
            while {1} {
              set end [string first $quote $line $pos]
              if {$end < 0} { set pos [string length $line]; break }
              set pos [expr {$end + 1}]
              set i $end
              while {[string index $line $i-1] eq "\\"} { incr i -1 }
              if {($end - $i) % 2 == 0} { break }
            }
            continue
          }
        }
      } else {
        set first $pos
      }
      set end [string first "*/" $line $pos]
      if {$end < 0} {
        set clean [string range $clean 0 $first-1]
        break
      }
      set pos [expr {$end + 2}]
      set clean [string replace $clean $first [expr {$pos - 1}] \
                     [string repeat " " [expr {$pos - $first}]]]
      set inBlock 0
    }
  }

  if {[regexp -indices {^\s*(#)\s*include\s*("[^"]+"|<[^>]+>)\s*$} \
           $clean match hash argument]} {
    lassign $argument first last
    set name [string trim [string range $line $first+1 $last-1]]
    set kind include
  } elseif {[regexp -indices {^\s*(#)\s*pragma\s+(once)\s*$} \
                 $clean match hash argument]} {
    set last [lindex $argument 1]
    set name ""
    set kind once
  } else {
    return {}
  }

  # Keep a preceding comment (especially a closing */ from a previous line)
  # and any trailing comment that continues into the next physical line.
  set first [lindex $hash 0]
  set prefix [string range $line 0 $first-1]
  if {[string trim $prefix] eq ""} { set prefix "" }
  set suffix ""
  if {$inBlock} { set suffix [string range $line $last+1 end] }
  return [list $kind $name $prefix $suffix]
}

# Discover dependencies and record the byte spans of the directives to edit.
proc scan_file {filename} {
  global includes edits embedded
  if {[info exists includes($filename)]} { return }

  trace_file scan $filename
  set raw [read_binary_file $filename]
  set lines [physical_lines $raw]
  set lastEol "\n"
  set offset 0
  set inBlock 0
  set includes($filename) {}
  set edits($filename) {}
  set count [llength $lines]

  for {set i 0} {$i < $count} {incr i} {
    set start $offset
    set lineNumber [expr {$i + 1}]
    set line ""
    while {1} {
      set part [lindex $lines $i]
      incr offset [string length $part]
      set eol [string index $raw $offset]
      if {$eol eq "\r" && [string index $raw $offset+1] eq "\n"} { set eol "\r\n" }
      incr offset [string length $eol]
      if {$eol ne ""} { set lastEol $eol }
      if {$eol eq "" || [string index $part end] ne "\\"} {
        append line $part
        break
      }
      append line [string range $part 0 end-1]
      if {$i + 1 == $count} { break }
      incr i
    }

    set directive [read_directive $line inBlock]
    if {![llength $directive]} { continue }
    lassign $directive kind name prefix suffix
    set child ""
    if {$kind eq "once"} {
      # Only the copy embedded in a parent elides this pragma.
      set embedded($filename) ""
    } elseif {[is_sqlite_public_header $name]} {
      set kind public
    } else {
      set child [resolve_include $name [source_name $filename] $lineNumber]
      if {$child eq ""} { continue }
      lappend includes($filename) $child
    }
    # Leave the directive's final physical terminator in the original text.
    set stop [expr {$offset - [string length $eol]}]
    if {$eol eq ""} { set eol $lastEol }
    lappend edits($filename) [list $start $stop $kind $name $child $prefix $suffix $eol]
  }

  foreach child $includes($filename) { scan_file $child }
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
        lappend names [source_name $path]
      }
      error "local include cycle detected: [join $names { -> }]"
    }
  }

  set state($filename) 1
  lappend stack $filename
  foreach child $includes($filename) {
    visit_file $child
  }
  set stack [lrange $stack 0 end-1]
  set state($filename) 2
  lappend order $filename
}

# Copy untouched spans verbatim. New lines inside an insertion use the
# terminator of the directive they replace, including in mixed-ending files.
proc expanded_file_data {filename original forEmbedding} {
  global edits embedded
  set result ""
  set offset 0
  foreach edit $edits($filename) {
    lassign $edit first stop kind name child prefix suffix eol
    if {$kind eq "once" && !$forEmbedding} { continue }
    append result [string range $original $offset $first-1] $prefix
    switch -- $kind {
      once   { append result "/* bundle_extra_src: #pragma once elided */" }
      public { append result "/* bundle_extra_src: sqlite public header already supplied */" }
      include {
        if {[info exists embedded($child)]} {
          set body $embedded($child)
        } else {
          set body [read_binary_file $child]
        }
        append result [section_comment "Begin file $name"] $eol
        if {$body ne ""} {
          set content [join [physical_lines $body] $eol]
          append result $content $eol
          if {[string index $content end] eq "\\"} { append result $eol }
        }
        append result [section_comment "End of $name"]
      }
    }
    append result $suffix
    set offset $stop
  }
  if {$offset == 0} { return $original }
  append result [string range $original $offset end]
  return $result
}

# Reserve a new sibling by opening it exclusively. This also protects
# dangling links on platforms where file exists cannot see them.
proc open_sibling {filename suffix pathVar} {
  upvar 1 $pathVar path
  set failures 0
  for {set n 0} {1} {incr n} {
    set path "${filename}.$n.$suffix"
    if {[file exists $path]} { continue }
    if {![catch {open $path {WRONLY CREAT EXCL}} channel]} { return $channel }
    if {![catch {file lstat $path}]} { continue }
    # Some Jim builds report the same generic error code for an occupied
    # dangling link and a permission failure. Try another name, with a bound.
    if {[incr failures] >= 16} { error $channel }
  }
}

# Jim's forced rename on Windows removes the destination before renaming.
# Retain the original in the same directory until the new name is installed.
proc install_file {tmpPath filename} {
  if {$::tcl_platform(platform) ne "windows" || $::tcl_platform(engine) ne "Jim"} {
    file rename -force $tmpPath $filename
    return
  }
  set reserved [open_sibling $filename tmp.orig backup]
  try {
    close $reserved
    # This process owns the empty destination. Keep the original there until
    # the staged file is successfully installed.
    file rename -force $filename $backup
  } on error {message options} {
    catch {file delete $backup}
    return {*}$options $message
  }
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
  global edits embedded
  if {![llength $edits($filename)]} { return 0 }
  trace_file expand $filename
  set original [read_binary_file $filename]
  if {[info exists embedded($filename)]} {
    set embedded($filename) [expanded_file_data $filename $original 1]
  }
  set expanded [expanded_file_data $filename $original 0]
  if {$expanded eq $original} {
    return 0
  }

  trace_file stage $filename
  set tmpChannel [open_sibling $filename tmp tmpPath]
  try {
    try {
      fconfigure $tmpChannel -translation binary
      puts -nonewline $tmpChannel $expanded
      flush $tmpChannel
    } finally {
      close $tmpChannel
    }
    trace_file install $filename
    install_file $tmpPath $filename
  } on error {message options} {
    catch {file delete $tmpPath}
    return {*}$options $message
  }

  return 1
}

array set edits {}
array set embedded {}
array set spelling {}
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
    puts "patched [source_name $filename]"
  }
}

puts "bundle complete: [llength $order] file(s) scanned, $changed file(s) patched"
