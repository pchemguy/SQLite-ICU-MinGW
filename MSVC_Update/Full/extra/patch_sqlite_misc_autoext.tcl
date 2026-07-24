#!/usr/bin/tclsh
#
#===============================================================================
# SCRIPT:      patch_sqlite_misc_autoext.tcl
# PURPOSE:     Automates the inline modification of SQLite loadable extensions 
#              (ext/misc/*.c) to enable integration into SQLite amalgamation builds 
#              as autoextensions via -DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit.
#
# OVERVIEW:
#              1. Header Patch: Locates extension header declarations matching:
#                     #include "sqlite3ext.h" (or <sqlite3ext.h>)
#                     SQLITE_EXTENSION_INIT1
#                 and wraps them in a conditional `#ifndef SQLITE_CORE` block 
#                 to include "sqlite3.h" instead when compiled into the core.
#              2. Init Patch & Detection: Converts dynamic 'sqlite3_<name>_init' 
#                 entry points into static initializers ('sqlite3<Name>Init').
#                 Includes fallback detection to identify modules that already 
#                 have 'sqlite3<Name>Init' (skipping the patch while registering 
#                 them correctly).
#              3. Anti-Collision Macro: Injects a preprocessor alias right before
#                 the static initializer to rename it conditionally (e.g., 
#                 `#define sqlite3CsvInit sqlite3CsvInit_Standalone`) when 
#                 SQLITE_CORE is NOT defined. This prevents symbol collisions if 
#                 the module is included in both sqlite3.c and shell.c.
#              4. Dynamic Wrapper: Appends a '#ifndef SQLITE_CORE' block to 
#                 maintain dual static/dynamic load capability.
#              5. Dispatcher Gen: Generates 'misc_ext_init.c' with forward 
#                 declarations and the 'sqlite3ExtraAutoExtInit' dispatcher.
#                 Intelligently converts CamelCase names to UPPER_SNAKE_CASE 
#                 (e.g., StmtVtab -> STMT_VTAB) for build macros.
#
# USAGE:       tclsh patch_sqlite_misc_autoext.tcl <file1.c> [file2.c ...]
#              Example (MSVC / NMake):
#                tclsh patch_sqlite_misc_autoext.tcl $(MISC_SRC)
#
# FEATURES:    - Fully Idempotent: Safe for multi-pass execution in pipelines.
#              - Input Sanitization: Cleans non-breaking spaces (\u00A0) and 
#                handles space-delimited string arguments from NMake macros.
#              - Robust Parsing: Prevents TCL parser brace-counting conflicts.
#
# https://gemini.google.com/app/a928354bab65795e
#===============================================================================

# Accumulators for the activation stub generator
set EXT_macros {}
set Ext_funcs {}

# Normalize and clean input arguments
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

    set modified 0
    set ext_found 0
    set extname ""
    set Extname ""
    set EXT ""

    # -------------------------------------------------------------------------
    # PART 1: INIT FUNCTION PATCHING & REGISTRATION
    # -------------------------------------------------------------------------
    
    # Pathway A: Module has the standard dynamic init function
    if {[regexp {int\s+sqlite3_([a-zA-Z0-9_]+)_init\s*\(} $content _ match_ext]} {
        set extname $match_ext
        
        # Convert snake_case to CamelCase (e.g. stmt_vtab -> StmtVtab)
        foreach part [split $extname "_"] {
            append Extname [string totitle $part]
        }
        set EXT [string toupper $extname]
        set ext_found 1

        # If sqlite3<Name>Init already exists, skip patching the init block
        if {[regexp "int\\s+sqlite3${Extname}Init\\s*\\(" $content]} {
            # Natively compliant or previously patched.
        } else {
            # 1. Remove the DLLEXPORT block while preserving trailing comments
            set pattern "#ifdef _WIN32\\s+__declspec\\(dllexport\\)\\s+#endif\\s+(/\\*.*?\\*/\\s*)?int\\s+sqlite3_${extname}_init"
            regsub -all -- $pattern $content "\\1int sqlite3_${extname}_init" content
            
            # 2. Change the function signature
            set sig_old "int\\s+sqlite3_${extname}_init\\s*\\(\\s*sqlite3\\s*\\*\\s*db\\s*,\\s*char\\s*\\*\\*\\s*pzErrMsg\\s*,\\s*const\\s+sqlite3_api_routines\\s*\\*\\s*pApi\\s*\\)"
            set sig_new "int sqlite3${Extname}Init(sqlite3 *db)"
            regsub -all -- $sig_old $content $sig_new content
            
            # 3. Remove SQLITE_EXTENSION_INIT2
            regsub -all -- {\s*SQLITE_EXTENSION_INIT2\s*\(\s*pApi\s*\)\s*;?} $content "" content
            
            # 4. Remove unused parameter cast for pzErrMsg
            regsub -all -- {\s*\(\s*void\s*\)\s*pzErrMsg\s*;[^\n\r]*} $content "" content
            
            # Safety Check: Inject a dummy variable if pzErrMsg is still evaluated
            if {[string match "*pzErrMsg*" $content]} {
                set search_pattern "int sqlite3${Extname}Init\\(sqlite3 \\*db\\)\\s*\\\{"
                set replace_pattern "int sqlite3${Extname}Init(sqlite3 *db)\{\n  char **pzErrMsg = 0; /* dummy for static build */"
                regsub -- $search_pattern $content $replace_pattern content
            }

            # 5. Append dynamic loading wrapper stub to EOF
            set stub "\n\n#ifndef SQLITE_CORE\n#ifdef _WIN32\n__declspec(dllexport)\n#endif\nint sqlite3_${extname}_init(\n  sqlite3 *db,\n  char **pzErrMsg,\n  const sqlite3_api_routines *pApi\n)\{\n  (void)pzErrMsg;  /* Unused parameter */\n  SQLITE_EXTENSION_INIT2(pApi);\n  return sqlite3${Extname}Init(db);\n\}\n#endif\n"
            append content $stub
            
            set modified 1
        }
    
    # Pathway B: Module is missing dynamic init, but already has a static init
    } elseif {[regexp {int\s+sqlite3([A-Z][a-zA-Z0-9_]*?)Init\s*\(} $content _ match_Ext]} {
        set Extname $match_Ext
        
        # Convert CamelCase back to UPPER_SNAKE_CASE (e.g. StmtVtab -> STMT_VTAB)
        set EXT [string toupper [regsub -all {([a-z])([A-Z])} $Extname {\1_\2}]]
        set ext_found 1
    } else {
        puts "Warning: Could not find initialization function in '$file'."
    }

    # Register the resolved module for the dispatcher
    if {$ext_found} {
        lappend EXT_macros $EXT
        lappend Ext_funcs $Extname
        
        # -------------------------------------------------------------------------
        # PART 2: ANTI-COLLISION MACRO INJECTION
        # -------------------------------------------------------------------------
        # Prepend a macro right before the definition to rename it outside the core.
        if {![regexp "#\\s*define\\s+sqlite3${Extname}Init\\s+sqlite3${Extname}Init_Standalone" $content]} {
            set macro_str "/* Prevent symbol collision when included in both core and shell */\n#ifndef SQLITE_CORE\n# define sqlite3${Extname}Init sqlite3${Extname}Init_Standalone\n#endif\n"
            set sig_pattern "(int\\s+sqlite3${Extname}Init\\s*\\()"
            
            # Use regsub without -all to inject only before the first occurrence
            if {[regsub -- $sig_pattern $content "${macro_str}\\1" content]} {
                set modified 1
            }
        }
    }

    # -------------------------------------------------------------------------
    # PART 3: HEADER PATCHING (#include "sqlite3ext.h" / SQLITE_EXTENSION_INIT1)
    # -------------------------------------------------------------------------
    if {![regexp {#ifndef SQLITE_CORE\s+#include\s+["<]sqlite3ext\.h[">]} $content]} {
        set hdr_search {[ \t]*#include[ \t]+["<]sqlite3ext\.h[">][ \t\r\n]+SQLITE_EXTENSION_INIT1[ \t]*}
        set hdr_replace "#ifndef SQLITE_CORE\n  #include \"sqlite3ext.h\"\n  SQLITE_EXTENSION_INIT1\n#else\n  #include \"sqlite3.h\"\n#endif\n"
        
        if {[regsub -- $hdr_search $content $hdr_replace content]} {
            set modified 1
        }
    }

    # -------------------------------------------------------------------------
    # WRITE BACK
    # -------------------------------------------------------------------------
    if {$modified} {
        set fp [open $file w]
        puts -nonewline $fp $content
        close $fp
        puts "Patched '$file' (Registered as $Extname)"
    } elseif {$ext_found} {
        puts "Skipping '$file': already completely patched. (Registered as $Extname)"
    }
}

# -----------------------------------------------------------------------------
# PART 4: DISPATCHER MODULE GENERATION
# -----------------------------------------------------------------------------
set out_c "misc_ext_init.c"
set fp [open $out_c w]

puts $fp "/*"
puts $fp "** Auto-generated extension initialization dispatcher."
puts $fp "** Built as part of customized SQLite nmake build pipeline."
puts $fp "*/"
puts $fp ""

# Generate forward declarations
foreach EXT $EXT_macros Ext $Ext_funcs {
    puts $fp "#ifdef SQLITE_ENABLE_${EXT}"
    puts $fp "int sqlite3${Ext}Init(sqlite3*);"
    puts $fp "#endif"
}

puts $fp ""
puts $fp "int sqlite3ExtraAutoExtInit(sqlite3 *db){"
puts $fp "  int rc = SQLITE_OK;"

# Generate dispatcher sequences
foreach EXT $EXT_macros Ext $Ext_funcs {
    puts $fp "#ifdef SQLITE_ENABLE_${EXT}"
    puts $fp "  if( rc==SQLITE_OK ) rc = sqlite3${Ext}Init(db);"
    puts $fp "#endif"
}

puts $fp "  return rc;"
puts $fp "}"

close $fp
puts "\nGenerated '$out_c' with dispatcher sqlite3ExtraAutoExtInit."
