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
#
# FEATURES:    - Fully Idempotent: Safe for multi-pass execution in pipelines.
#
# https://gemini.google.com/app/a928354bab65795e
#===============================================================================

# ==============================================================================
# HELPER ROUTINES: Naming Conversions
# ==============================================================================

# Converts snake_case to CamelCase (e.g., stmt_vtab -> StmtVtab)
proc snake_to_camel {snake_str} {
    set camel ""
    foreach part [split $snake_str "_"] {
        append camel [string totitle $part]
    }
    return $camel
}

# Converts CamelCase to UPPER_SNAKE_CASE (e.g., StmtVtab -> STMT_VTAB)
proc camel_to_upper_snake {camel_str} {
    return [string toupper [regsub -all {([a-z])([A-Z])} $camel_str {\1_\2}]]
}


# ==============================================================================
# PROCESSING ROUTINES
# ==============================================================================

# Task 1: Apply text mutations to convert a dynamic init to static.
proc apply_init_patch {content_var match_snake mod_camel} {
    upvar 1 $content_var content
    
    # 1. Remove the DLLEXPORT block while preserving trailing comments
    set pattern [string cat \
        "#ifdef _WIN32\\s+__declspec\\(dllexport\\)\\s+" \
        "#endif\\s+(/\\*.*?\\*/\\s*)?int\\s+sqlite3_${match_snake}_init" \
    ]
    regsub -all -- $pattern $content "\\1int sqlite3_${match_snake}_init" content
    
    # 2. Change the function signature
    set sig_old [string cat \
        "int\\s+sqlite3_${match_snake}_init\\s*\\(\\s*" \
        "sqlite3\\s*\\*\\s*db\\s*,\\s*" \
        "char\\s*\\*\\*\\s*pzErrMsg\\s*,\\s*" \
        "const\\s+sqlite3_api_routines\\s*\\*\\s*pApi\\s*\\)" \
    ]
    set sig_new "int sqlite3${mod_camel}Init(sqlite3 *db)"
    regsub -all -- $sig_old $content $sig_new content
    
    # 3. Remove SQLITE_EXTENSION_INIT2 and unused parameter cast
    regsub -all -- {\s*SQLITE_EXTENSION_INIT2\s*\(\s*pApi\s*\)\s*;?} $content "" content
    regsub -all -- {\s*\(\s*void\s*\)\s*pzErrMsg\s*;[^\n\r]*} $content "" content
    
    # 4. Safety Check: Inject a dummy variable if pzErrMsg is still evaluated
    if {[string match "*pzErrMsg*" $content]} {
        set search_pattern "int sqlite3${mod_camel}Init\\(sqlite3 \\*db\\)\\s*\\\{"
        set replace_pattern [string cat \
            "int sqlite3${mod_camel}Init(sqlite3 *db)\{\n" \
            "  char **pzErrMsg = 0; /* dummy for static build */" \
        ]
        regsub -- $search_pattern $content $replace_pattern content
    }

    # 5. Append dynamic loading wrapper stub to EOF
    set stub [string cat \
        "\n\n#ifndef SQLITE_CORE\n" \
        "#ifdef _WIN32\n__declspec(dllexport)\n#endif\n" \
        "int sqlite3_${match_snake}_init(\n" \
        "  sqlite3 *db,\n" \
        "  char **pzErrMsg,\n" \
        "  const sqlite3_api_routines *pApi\n" \
        ")\{\n" \
        "  (void)pzErrMsg;  /* Unused parameter */\n" \
        "  SQLITE_EXTENSION_INIT2(pApi);\n" \
        "  return sqlite3${mod_camel}Init(db);\n" \
        "\}\n" \
        "#endif\n" \
    ]
    append content $stub
}

# Task 2: Analyze the initialization function and route to patching if necessary.
# Returns a list: {found_boolean modified_boolean module_camel module_upper}
proc resolve_init_function {content_var} {
    upvar 1 $content_var content
    
    # Pathway A: Module has the standard dynamic init function
    if {[regexp {int\s+sqlite3_([a-zA-Z0-9_]+)_init\s*\(} $content _ match_snake]} {
        set mod_camel [snake_to_camel $match_snake]
        set mod_upper [string toupper $match_snake]
        
        # If the static initializer doesn't exist yet, patch the file
        if {![regexp "int\\s+sqlite3${mod_camel}Init\\s*\\(" $content]} {
            apply_init_patch content $match_snake $mod_camel
            return [list 1 1 $mod_camel $mod_upper]
        }
        
        # Found, but natively compliant (no patch needed)
        return [list 1 0 $mod_camel $mod_upper]
        
    # Pathway B: Module is missing dynamic init, but already has a static init
    } elseif {[regexp [string cat \
        {int\s+sqlite3([A-Z][a-zA-Z0-9_]*?)} \
        {Init\s*\(} \
    ] $content _ match_camel]} {
        set mod_camel $match_camel
        set mod_upper [camel_to_upper_snake $match_camel]
        return [list 1 0 $mod_camel $mod_upper]
    }
    
    # Not found
    return [list 0 0 "" ""]
}

# Task 3: Inject anti-collision macro
# Returns boolean indicating if content was modified.
proc inject_anti_collision_macro {content_var mod_camel} {
    upvar 1 $content_var content
    set macro_str [string cat \
        "/* Prevent symbol collision when included in both core and shell */\n" \
        "#ifndef SQLITE_CORE\n" \
        "# define sqlite3${mod_camel}Init sqlite3${mod_camel}Init_Standalone\n" \
        "#endif\n" \
    ]
    set sig_pattern "(int\\s+sqlite3${mod_camel}Init\\s*\\()"
    
    set macro_pattern [string cat \
        "#\\s*define\\s+sqlite3${mod_camel}Init\\s+" \
        "sqlite3${mod_camel}Init_Standalone" \
    ]
    
    if {![regexp $macro_pattern $content]} {
        if {[regsub -- $sig_pattern $content "${macro_str}\\1" content]} {
            return 1
        }
    }

    return 0
}

# Task 4: Patch headers for conditional SQLite core compilation
# Returns boolean indicating if content was modified.
proc patch_headers {content_var} {
    upvar 1 $content_var content
    
    set check_pattern [string cat \
        {#ifndef SQLITE_CORE\s+} \
        {#include\s+["<]sqlite3ext\.h[">]} \
    ]
    
    if {![regexp $check_pattern $content]} {
        
        set hdr_search [string cat \
            {[ \t]*#include[ \t]+["<]sqlite3ext\.h[">]} \
            {[ \t\r\n]+SQLITE_EXTENSION_INIT1[ \t]*} \
        ]
        
        set hdr_replace [string cat \
            "#ifndef SQLITE_CORE\n" \
            "  #include \"sqlite3ext.h\"\n" \
            "  SQLITE_EXTENSION_INIT1\n" \
            "#else\n" \
            "  #include \"sqlite3.h\"\n" \
            "#endif\n" \
        ]
        
        if {[regsub -- $hdr_search $content $hdr_replace content]} {
            return 1
        }
    }
    return 0
}

# Task 5: Orchestrate the patching of a single module
# Returns a dict-like list {camel_name upper_name} if successful, empty if failed.
proc process_module {filepath} {
    if {![file exists $filepath]} {
        puts "Warning: File '$filepath' does not exist. Skipping."
        return {}
    }

    set fp [open $filepath r]
    set content [read $fp]
    close $fp

    # 1. Init Detection & Patching
    lassign [resolve_init_function content] found init_mod mod_camel mod_upper
    
    if {!$found} {
        puts "Warning: Could not find initialization function in '$filepath'."
        return {}
    }

    # 2. Macro & Header Patching
    set collision_mod [inject_anti_collision_macro content $mod_camel]
    set header_mod    [patch_headers content]

    # 3. Write back only if changes were made
    if {$init_mod || $collision_mod || $header_mod} {
        set fp [open $filepath w]
        puts -nonewline $fp $content
        close $fp
        puts "Patched '$filepath' (Registered as $mod_camel)"
    } else {
        puts [string cat \
            "Skipping '$filepath': already completely " \
            "patched. (Registered as $mod_camel)" \
        ]
    }

    return [list $mod_camel $mod_upper]
}

# Task 6: Generate the dispatcher source file
proc generate_dispatcher {outfile registered_modules} {
    set fp [open $outfile w]

    puts $fp "/*"
    puts $fp "** Auto-generated extension initialization dispatcher."
    puts $fp "** Built as part of customized SQLite nmake build pipeline."
    puts $fp "*/\n"

    # Forward declarations
    foreach module $registered_modules {
        lassign $module mod_camel mod_upper
        puts $fp "#ifdef SQLITE_ENABLE_${mod_upper}"
        puts $fp "int sqlite3${mod_camel}Init(sqlite3*);"
        puts $fp "#endif"
    }

    puts $fp "\nint sqlite3ExtraAutoExtInit(sqlite3 *db){"
    puts $fp "  int rc = SQLITE_OK;"

    # Dispatcher block
    foreach module $registered_modules {
        lassign $module mod_camel mod_upper
        puts $fp "#ifdef SQLITE_ENABLE_${mod_upper}"
        puts $fp "  if( rc==SQLITE_OK ) rc = sqlite3${mod_camel}Init(db);"
        puts $fp "#endif"
    }

    puts $fp "  return rc;"
    puts $fp "}"

    close $fp
    puts "\nGenerated '$outfile' with dispatcher sqlite3ExtraAutoExtInit."
}


# ==============================================================================
# MAIN PIPELINE ORCHESTRATOR
# ==============================================================================

set registered_modules {}

foreach extrasrc $argv {
    set module_data [process_module $extrasrc]
    
    # If the file yielded valid module info, append it to our registry list
    if {[llength $module_data] == 2} {
        lappend registered_modules $module_data
    }
}

if {[llength $registered_modules] > 0} {
    generate_dispatcher "misc_ext_init.c" $registered_modules
}
