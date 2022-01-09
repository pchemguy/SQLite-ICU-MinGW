---
layout: default
title: Integrating extra extensions
nav_order: 7
permalink: /extra-exts
---

The SQLite source distribution includes a suite of small extensions within the *sqlite/ext/misc* folder. These extensions, except for *json*, must be compiled as independent loadable modules. Integrated extensions, such as *json*, are simpler to use, so I picked several *sqlite/ext/misc* extensions for integration into the amalgamation. Integration of an extension into the amalgamation consists of several steps. To illustrate them, lets use the *sqlite/ext/misc/csv.c* extension as an example and the *sqlite/ext/misc/json1.c* extension as a reference.

**Source file references**
As discussed earlier, the SQLite building process starts with copying the source files into the *build/tsrc* folder based on the information in the *make* files. Make files contain several sections accumulating the list of source files. (The *Makefile* file is generated in the *build* folder by the *configure* script, and the *Makefile.msc* is copied from the source folder into the *build* folder by the shell script.) The source file names of the selected extensions can be added, for example,

after `$(TOP)\ext\misc\json1.c \` in *build\Makefile.msc*:

```makefile
  $(TOP)\ext\misc\csv.c \
```

and after `$(TOP)/ext/misc/json1.c \` in the *build/Makefile*

```makefile
  $(TOP)/ext/misc/csv.c \
```

Target file names must also be added to the list of source names in *sqlite\tool\mksqlite3c.tcl.ext*, e.g., after *json1.c*:

```
   csv.c
```

--- 

**Conditional inclusion**
The source of an integrated extension needs to be wrapped in a conditional:

```c
#ifdef SQLITE_ENABLE_CSV
#endif
```
 
 ---
 
**Extension initialization**
A loadable extension must define the init function `sqlite3_\<module name\>_init` called by SQLite when the extension is loaded, e.g.:
 
```c
sqlite3_csv_init
sqlite3_json_init
```

An integrated extension must additionally define a separate init function (with essentially identical content) called when SQLite is loaded, e.g.:

```c
sqlite3Json1Init
sqlite3IcuInit
```

The CSV extension does not have sqlite3CsvInit, so one should be added before sqlite3_csv_init, and its content should either come from sqlite3_csv_init 

```c
int sqlite3CsvInit(sqlite3 *db){
#ifndef SQLITE_OMIT_VIRTUALTABLE	
  return sqlite3_create_module(db, "csv", &CsvModule, 0);
#else
  return SQLITE_OK;
#endif
}
```

or modeled using its contents after, e.g., sqlite3Json1Init

```c
int sqlite3CsvInit(sqlite3 *db){
  int rc = SQLITE_OK;
  unsigned int i;
#ifndef SQLITE_OMIT_VIRTUALTABLE
  static const struct {
     const char *zName;
     sqlite3_module *pModule;
  } aMod[] = {
    { "csv",                  &CsvModule                    },
  };
  for(i=0; i<sizeof(aMod)/sizeof(aMod[0]) && rc==SQLITE_OK; i++){
    rc = sqlite3_create_module(db, aMod[i].zName, aMod[i].pModule, 0);
  }
#endif
  return rc;
}
```

Finally, a prototype of the new sqlite3CsvInit init function must be added to the *build/tsrc/main.c*, e.g.:

```c
#ifdef SQLITE_ENABLE_JSON1
int sqlite3Json1Init(sqlite3*);
#endif
#ifdef SQLITE_ENABLE_CSV
int sqlite3CsvInit(sqlite3*);
#endif
```
and the sqlite3CsvInit pointer must be added to the *sqlite3BuiltinExtensions* array:

```c
#ifdef SQLITE_ENABLE_JSON1
  sqlite3Json1Init,
#endif
#ifdef SQLITE_ENABLE_CSV
  sqlite3CsvInit,
#endif
```

---

These steps are typically necessary for each extension to be integrated. However, if an extension only provides new C APIs (such as *sqlite/ext/misc/normalize.c*) it does not need the initialization step.
