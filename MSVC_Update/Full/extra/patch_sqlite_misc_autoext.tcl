#===============================================================================
# SCRIPT:      patch_sqlite_misc_autoext.tcl
# PURPOSE:     Automates the inline modification of SQLite loadable extensions 
#              (ext/misc/*.c) to enable integration into SQLite amalgamation builds 
#              as autoextensions via -DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit.
#
# OVERVIEW:
#              1. Converts 'sqlite3_<name>_init' entry points into standard core
#                 initialization functions ('sqlite3<Name>Init').
#              2. Strips dynamic load macros ('SQLITE_EXTENSION_INIT2') and 
#                 unused parameter casts.
#              3. Appends a '#ifndef SQLITE_CORE' dynamic wrapper block to 
#                 maintain dual static/dynamic load capability.
#              4. Generates 'misc_ext_init.c' containing forward declarations
#                 and the 'sqlite3ExtraAutoExtInit' dispatcher function.
#
# USAGE:       tclsh patch_sqlite_misc_autoext.tcl <file1.c> [file2.c ...]
#              Example (MSVC / NMake):
#                tclsh patch_sqlite_misc_autoext.tcl $(MISC_SRC)
#
# FEATURES:    - Idempotent: Safe for multi-pass execution in build pipelines.
#              - Input Sanitization: Cleans non-breaking spaces (\u00A0) and 
#                handles space-delimited string arguments from NMake macros.
#===============================================================================

# List accumulators for the activation stub generator
set ext_names {}
set Ext_names {}

# Normalize and clean input arguments (handles NBSPs, multi-spaces, and quoted lists)
set clean_files {}
foreach arg $argv {
    # Replace non-breaking spaces (\u00a0) with regular spaces and trim
    set cleaned [string map [list \u00a0 " "] $arg]
    set cleaned [string trim $cleaned]
    
    # Expand if NMake passed a space-separated string as a single argument
    foreach item [split $cleaned " "] {
        set item [string trim $item]
        if {$item ne ""} {
            lappend clean_files $item
        }
    }
}

foreach file $clean_files {
    if {![file exists $file]} {
        puts "Warning: File '$file' does not exist. Skipping."
        continue
    }

    set fp [open $file r]
    set content [read $fp]
    close $fp

    # Idempotency Check: Look for the specific dynamic loading wrapper we append
    if {[regexp {#ifndef SQLITE_CORE\s+#ifdef _WIN32\s+__declspec\(dllexport\)\s+#endif\s+int\s+sqlite3_([a-zA-Z0-9_]+)_init} $content _ extname]} {
        puts "Skipping '$file': already patched."
        
        # Convert snake_case to CamelCase (e.g. stmt_vtab -> StmtVtab)
        set Extname ""
        foreach part [split $extname "_"] {
            append Extname [string totitle $part]
        }
        
        lappend ext_names $extname
        lappend Ext_names $Extname
        continue
    }

    # Find the original auto-load extension initialization function
    if {[regexp {int\s+sqlite3_([a-zA-Z0-9_]+)_init\s*\(} $content _ extname]} {
        set Extname ""
        foreach part [split $extname "_"] {
            append Extname [string totitle $part]
        }
        
        # 1. Remove the DLLEXPORT block while preserving the trailing comment if present
        set pattern "#ifdef _WIN32\\s+__declspec\\(dllexport\\)\\s+#endif\\s+(/\\*.*?\\*/\\s*)?int\\s+sqlite3_${extname}_init"
        regsub -all -- $pattern $content "\\1int sqlite3_${extname}_init" content
        
        # 2. Change the function signature
        set sig_old "int\\s+sqlite3_${extname}_init\\s*\\(\\s*sqlite3\\s*\\*\\s*db\\s*,\\s*char\\s*\\*\\*\\s*pzErrMsg\\s*,\\s*const\\s+sqlite3_api_routines\\s*\\*\\s*pApi\\s*\\)"
        set sig_new "int sqlite3${Extname}Init(sqlite3 *db)"
        regsub -all -- $sig_old $content $sig_new content
        
        # 3. Remove SQLITE_EXTENSION_INIT2
        regsub -all -- {\s*SQLITE_EXTENSION_INIT2\s*\(\s*pApi\s*\)\s*;?} $content "" content
        
        # 4. Remove the unused parameter cast for pzErrMsg
        regsub -all -- {\s*\(\s*void\s*\)\s*pzErrMsg\s*;[^\n\r]*} $content "" content
        
        # Safety Check: If an extension (like series.c) actively evaluates `pzErrMsg!=0` 
        # inject a dummy variable at the top of the block.
        if {[string match "*pzErrMsg*" $content]} {
            set search_pattern "int sqlite3${Extname}Init\\(sqlite3 \\*db\\)\\s*\\\{"
            set replace_pattern "int sqlite3${Extname}Init(sqlite3 *db)\{\n  char **pzErrMsg = 0; /* dummy for static build */"
            regsub -- $search_pattern $content $replace_pattern content
        }

        # 5. Append the dynamic loading wrapper stub to the EOF
        set stub "\n\n#ifndef SQLITE_CORE\n#ifdef _WIN32\n__declspec(dllexport)\n#endif\nint sqlite3_${extname}_init(\n  sqlite3 *db,\n  char **pzErrMsg,\n  const sqlite3_api_routines *pApi\n)\{\n  (void)pzErrMsg;  /* Unused parameter */\n  SQLITE_EXTENSION_INIT2(pApi);\n  return sqlite3${Extname}Init(db);\n\}\n#endif\n"
        append content $stub
        
        # Write back the patched content in-place
        set fp [open $file w]
        puts -nonewline $fp $content
        close $fp
        
        puts "Patched '$file' ($extname -> $Extname)"
        lappend ext_names $extname
        lappend Ext_names $Extname
    } else {
        puts "Warning: Could not find 'int sqlite3_<name>_init' in '$file'."
    }
}

# Generate the activation stub module: misc_ext_init.c
set out_c "misc_ext_init.c"
set fp [open $out_c w]

puts $fp "/*"
puts $fp "** Auto-generated extension initialization dispatcher."
puts $fp "** Built as part of customized SQLite nmake build pipeline."
puts $fp "*/"
puts $fp ""

# Generate forward declarations
# foreach ext $ext_names Ext $Ext_names {
#     set EXT [string toupper $ext]
#     puts $fp "#ifdef SQLITE_ENABLE_${EXT}"
#     puts $fp "int sqlite3${Ext}Init(sqlite3*);"
#     puts $fp "#endif"
# }

puts $fp ""
puts $fp "int sqlite3ExtraAutoExtInit(sqlite3 *db){"
puts $fp "  int rc = SQLITE_OK;"

# Generate the dispatcher sequences
foreach ext $ext_names Ext $Ext_names {
    set EXT [string toupper $ext]
    puts $fp "#ifdef SQLITE_ENABLE_${EXT}"
    puts $fp "  if( rc==SQLITE_OK ) rc = sqlite3${Ext}Init(db);"
    puts $fp "#endif"
}

puts $fp "  return rc;"
puts $fp "}"

close $fp
puts "\nGenerated '$out_c' with dispatcher sqlite3ExtraAutoExtInit."
