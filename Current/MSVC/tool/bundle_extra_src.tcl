# bundle_extra_src.tcl -- Expand local C #include directives in place.
#
# Every positional argument must be the file name of a .c or .h file located
# directly in the source directory. Local include names are resolved from
# the including file's directory and the source directory, including names
# that contain subdirectories.
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
to the including file and the source directory, including include names
containing subdirectories.

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
  if {$::tcl_platform(engine) eq "Tcl" && ![catch {file type $path} ftype] && $ftype eq "link"} {
    return [file dirname [file normalize "$path/__leaf__"]]
  }
  return [file normalize $path]
}

set srcdir [normalize_existing "."]

# 78 stars used for amalgamator-style comment formatting.
set s78 [string repeat * 78]

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
  set norm [string map {\\ /} [string trim $includeName]]
  set tail [file tail $norm]
  return [expr {
    $tail eq "sqlite3.h" ||
    $tail eq "sqlite3ext.h"
  }]
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

# Format PATH relative to $srcdir for diagnostics.
proc rel_path {path} {
  global srcdir
  set normBase [path_compare_form $srcdir]
  set normPath [path_compare_form $path]
  set prefix "${normBase}/"
  if {[string equal -length [string length $prefix] $prefix $normPath]} {
    set cleanPath [string map {\\ /} $path]
    return [string range $cleanPath [string length $prefix] end]
  }
  return [file tail $path]
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

# Resolve INCLUDE_NAME starting at BASE_DIR while enforcing that no step
# escapes $srcdir. Returns [list status resolvedPath] where status is one of:
#   "found"   - existing regular file inside $srcdir
#   "missing" - stays within $srcdir, but file does not exist
#   "escape"  - path traversal or symlink escapes $srcdir
proc resolve_from_base {baseDir includeName} {
  global srcdir

  set candidate $baseDir
  foreach part [split $includeName /] {
    if {$part eq "" || $part eq "."} { continue }
    if {$part eq ".."} {
      if {[path_compare_form $candidate] eq [path_compare_form $srcdir]} {
        return [list "escape" ""]
      }
      set candidate [file dirname $candidate]
      if {![path_is_within $srcdir $candidate]} {
        return [list "escape" ""]
      }
    } else {
      set candidate "[string trimright $candidate /]/$part"
      if {[file exists $candidate]} {
        set candidate [normalize_existing $candidate]
        if {![path_is_within $srcdir $candidate]} {
          return [list "escape" ""]
        }
      }
    }
  }

  if {[file isfile $candidate]} {
    set candidate [normalize_existing $candidate]
    if {![path_is_within $srcdir $candidate]} {
      return [list "escape" ""]
    }
    return [list "found" $candidate]
  }
  return [list "missing" ""]
}

# Resolve an include name relative to the including file's directory and the
# source base directory. Return "" when it does not name a local regular file.
proc resolve_include {includeName includingFile lineNumber delim} {
  global srcdir

  set includeName [string map {\\ /} $includeName]
  if {[regexp {^[/~]|^[A-Za-z]:} $includeName]} {
    error "$includingFile:$lineNumber: absolute include path is not allowed: $includeName"
  }

  set incDir [file dirname $includingFile]
  if {[path_compare_form $incDir] eq [path_compare_form $srcdir]} {
    set bases [list $srcdir]
  } elseif {$delim eq "<"} {
    set bases [list $srcdir $incDir]
  } else {
    set bases [list $incDir $srcdir]
  }

  set allEscape 1
  foreach base $bases {
    lassign [resolve_from_base $base $includeName] status resolved
    if {$status eq "found"} {
      return $resolved
    }
    if {$status ne "escape"} {
      set allEscape 0
    }
  }

  if {$allEscape} {
    error "$includingFile:$lineNumber: include escapes source directory: $includeName"
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

# Strip comments from a single logical line while updating block-comment state.
# Also records any trailing unclosed block-comment suffix ("/* ...") that starts
# on this line so line replacements do not corrupt multi-line comments.
proc strip_line_comments {line inBlockVar trailingCommentVar} {
  upvar 1 $inBlockVar inBlock
  upvar 1 $trailingCommentVar trailingComment
  set trailingComment ""

  if {!$inBlock && [string first "/*" $line] < 0 && [string first "//" $line] < 0} {
    return $line
  }
  if {$inBlock && [string first "*/" $line] < 0} {
    return ""
  }

  set out ""
  set len [string length $line]
  set i 0
  set inQuote 0

  while {$i < $len} {
    if {$inBlock} {
      set closeIdx [string first "*/" $line $i]
      if {$closeIdx < 0} {
        break
      }
      set inBlock 0
      append out " "
      set i [expr {$closeIdx + 2}]
      continue
    }

    set ch [string index $line $i]
    if {$inQuote} {
      append out $ch
      if {$ch eq "\\" && ($i + 1) < $len} {
        incr i
        append out [string index $line $i]
      } elseif {$ch eq "\""} {
        set inQuote 0
      }
      incr i
      continue
    }

    if {$ch eq "\""} {
      set inQuote 1
      append out $ch
      incr i
      continue
    }

    if {$ch eq "/" && ($i + 1) < $len} {
      set next [string index $line [expr {$i + 1}]]
      if {$next eq "/"} {
        break
      }
      if {$next eq "*"} {
        set closeIdx [string first "*/" $line [expr {$i + 2}]]
        if {$closeIdx < 0} {
          set inBlock 1
          set trailingComment [string range $line $i end]
          break
        }
        append out " "
        set i [expr {$closeIdx + 2}]
        continue
      }
    }

    append out $ch
    incr i
  }

  return $out
}

# Scan one file and cache its raw bytes, logical lines, and include edges.
proc scan_file {filename} {
  global scanned includes noopIncludes rawContent fileLines

  if {[info exists scanned($filename)]} {
    return
  }

  set raw [read_binary_file $filename]
  set rawContent($filename) $raw
  set lines [logical_lines $raw]
  set fileLines($filename) $lines

  set edges {}
  set noops {}
  set lineNumber 0
  set inBlock 0

  foreach line $lines {
    incr lineNumber
    set stripped [strip_line_comments $line inBlock trailingComment]

    if {[regexp {^[ \t]*#[ \t]*include[ \t]*(["<])([^"<>]+)([">])} \
            $stripped all openDelim includeName closeDelim]} {
      if {($openDelim eq "\"" && $closeDelim ne "\"") ||
          ($openDelim eq "<" && $closeDelim ne ">")} {
        continue
      }
      set includeName [string trim $includeName]

      if {[is_sqlite_public_header $includeName]} {
        lappend noops [list $lineNumber $trailingComment]
        continue
      }

      set included [resolve_include $includeName $filename $lineNumber $openDelim]
      if {$included ne ""} {
        lappend edges [list $lineNumber $includeName $included $trailingComment]
      }
    }
  }

  set includes($filename) $edges
  set noopIncludes($filename) $noops
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
        lappend names [rel_path $path]
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
# Because Phase 3 visits files in topological dependency-first order,
# $fileLines($included) already holds the fully expanded lines of each child.
proc expanded_file_data {filename} {
  global includes noopIncludes rawContent fileLines

  set original $rawContent($filename)
  if {[llength $includes($filename)] == 0 && [llength $noopIncludes($filename)] == 0} {
    return $original
  }

  lassign [newline_info $original] eol hasFinal
  set lines $fileLines($filename)
  set edgeByLine {}
  set noopByLine {}

  foreach edge $includes($filename) {
    dict set edgeByLine [lindex $edge 0] $edge
  }
  foreach noop $noopIncludes($filename) {
    dict set noopByLine [lindex $noop 0] [lindex $noop 1]
  }

  set outputLines {}
  set lineNumber 0

  foreach line $lines {
    incr lineNumber

    if {[dict exists $noopByLine $lineNumber]} {
      set trailingComment [dict get $noopByLine $lineNumber]
      set suffix [expr {$trailingComment ne "" ? " $trailingComment" : ""}]
      lappend outputLines \
          "/* bundle_extra_src: sqlite public header already supplied */$suffix"
      continue
    }

    if {![dict exists $edgeByLine $lineNumber]} {
      lappend outputLines $line
      continue
    }

    lassign [dict get $edgeByLine $lineNumber] ignored includeName included trailingComment
    set suffix [expr {$trailingComment ne "" ? " $trailingComment" : ""}]
    set includedLines $fileLines($included)

    lappend outputLines [section_comment "Begin file $includeName"]
    foreach includedLine $includedLines {
      if {[regexp {^[ \t]*#[ \t]*pragma[ \t]+once[ \t]*$} $includedLine]} {
        lappend outputLines "/* bundle_extra_src: #pragma once elided */"
      } else {
        lappend outputLines $includedLine
      }
    }
    if {[llength $includedLines] > 0 && [string index [lindex $includedLines end] end] eq "\\"} {
      lappend outputLines ""
    }
    lappend outputLines "[section_comment "End of $includeName"]$suffix"
  }

  set fileLines($filename) $outputLines

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
  global rawContent

  set original $rawContent($filename)
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
    set rawContent($filename) $expanded
  } on error {message options} {
    catch {file delete $tmpPath}
    return {*}$options $message
  }

  return 1
}

array set scanned {}
array set includes {}
array set noopIncludes {}
array set state {}
array set rawContent {}
array set fileLines {}
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
    puts "patched [rel_path $filename]"
  }
}

puts "bundle complete: [llength $order] file(s) scanned, $changed file(s) patched"
