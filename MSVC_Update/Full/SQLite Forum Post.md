# Integrating ordinary loadable extensions from ext/misc into amalgamation as auto extensions

A few years ago, I have been experimenting with customized SQLite build process aimed at integrating select ordinary loadable extensions from ext/misc into amalgamation as auto extensions. Since I am on Windows, my primary focus is on the native MSVC toolchain, though I have also successfully experimented with MinGW/MSYS2. To achieve the integration objective, I have patched the sources, such as `ext/misc/csv.c` and `main.c`, as well as a few build files (`Makefile.msc` and `mksqlite3c.tcl`). The process was a bit messy, though it worked just fine. I have revisited my pipeline recently, as well as updates to the SQLite source and build system and realized that now that

1. `Makefile.msc` provides support for `EXTRA_SRC`
2. `mksqlite3c.tcl` supports integrating extra sources into amalgamation
3. `sqlite3BuiltinExtensions` registry from `main.c` used for activating auto extensions provides a hook
```
#ifdef SQLITE_EXTRA_AUTOEXT
  SQLITE_EXTRA_AUTOEXT,
#endif
```

the whole integration process can now be streamlined: only the extensions being integrated needs to be patched, while the rest of the build process customization is achieved via CLI without patching `main.c` or build files (related thread https://sqlite.org/forum/info/903f721f3e7c0d25).

 `mksqlite3c.tcl` integrates extra sources verbatim after the core, so the sources need to be prepared for this integration. As I did not want to patch SQLite's build files, I created two TCL tools to assist me in this preparation, which I would like to share along with my workflow.

The primary tool `patch_sqlite_misc_autoext.tcl`

