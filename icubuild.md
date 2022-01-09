---
layout: default
title: ICU-enabled build
nav_order: 6
permalink: /icubuild
---

In order to compile SQLite with ICU exetnsions enabled, the following needs to be done:

- `-DSQLITE_ENABLE_ICU` option must be supplied to the compiler;
- `-I` flags pointing to the ICU include directories needs to be supplied to the compiler;
- `-l` and `-L` flags specifying names and locations of the necessary libraries needs to be supplied to the linker.
 
An important consideration regarding the linker flags is that *the order of these flags matters when static compilation is requested*. The safe attitude is to assume that these flags always need to be supplied in the correct order. In the command line, dependencies should follow the module depending on it (*including the source/object files*). The necessary flags can be obtained via pkg-config or icu-config (though the two methods yield slightly different sets):

```bash
# via icu-config
ICU_CFLAGS="$(icu-config --cflags --cppflags)"
ICU_LDFLAGS="$(icu-config --ldflags --ldflags-system)"

via pkg-config 
ICU_CFLAGS="$(pkg-config --cflags icu-i18n)"
ICU_LDFLAGS="$(pkg-config --libs --static icu-i18n)"
```

These flags then need to be injected into the commands executed by the SQLite Makefile. Rather than manually editing the generated Makefile, we should go over the provided [shell script][SQLite Build Proxy Script].

- **Download the source**  
This routine checks if SQLite archive is present. If not, SQLite source is downloaded. If the “configure” script does not exist, it unpacks the archive and renames the folder to “sqlite3”.  
  
```bash
get_sqlite() {
  cd "${BASEDIR}" || ( echo "Cannot enter ${BASEDIR}" && exit 101 )
  local SQLite_URL="https://www.sqlite.org/src/tarball/sqlite.tar.gz?r=release"
  if [[ ! -f ./sqlite.tar.gz ]]; then
    echo "____________________________________________"
    echo "Downloading the current release of SQLite..."
    echo "--------------------------------------------"
    wget -c "${SQLite_URL}" --no-check-certificate -O sqlite.tar.gz \
      || EC=$?
    (( EC != 0 )) && echo "Error downloading SQLite ${EC}." && exit 102
  else
    echo "________________________________________________"
    echo "Using previously downloaded archive of SQLite..."
    echo "------------------------------------------------"
  fi

  if [[ ! -f "./${DBDIR}/configure" ]]; then
    tar xzf ./sqlite.tar.gz
  fi
  return 0
} 
```

- **Configure**  
This routine creates a “build” subfolder inside the source folder. If “Makefile” is present in the “build” folder, configure is not run. "readline" flags are obtained via “pkg-config” as full Windows paths. The "$(cygpath -m /)" command returns the Windows path to the MSYS2 root folder, and this prefix is removed from the previously saved flags. Additional options to “configure” enable certain extensions, and “libtool” “lt_cv_deplibs_check_method” is set as a workaround.

```bash
configure_sqlite() {
  mkdir -p "./${BUILDDIR}"
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 104 )

  if [[ ! -f ./Makefile ]]; then
    [[ ! -r ../configure ]] && echo "Error accessing SQLite configure" \
      && exit 105
    echo "______________________"
    echo "Configuring SQLite3..."
    echo "----------------------"

    local msys_root
    msys_root="$(cygpath -m /)"
    msys_root="${msys_root%/}"
    local readline_inc
    readline_inc=$(pkg-config --cflags --static readline)
    readline_inc=${readline_inc//${msys_root}/}
    local readline_lib
    readline_lib=$(pkg-config --libs --static readline)
    readline_lib=${readline_lib//${msys_root}/}
    
    local CONFIGURE_OPTS
    CONFIGURE_OPTS=(
      --enable-all
      --enable-fts3
      --enable-memsys5
      --enable-update-limit
      --with-tcl=${MINGW_PREFIX}/lib
      --with-readline-lib="${readline_lib}"
      --with-readline-inc="${readline_inc}"
    )

    lt_cv_deplibs_check_method="pass_all" ../configure ${CONFIGURE_OPTS[@]} \
      || EXITCODE=$?
    (( EXITCODE != 0 )) && echo "Error configuring SQLite" && exit 106
  else
    echo "____________________________________________"
    echo "Makefile found. Skipping configuring SQLite3"
    echo "--------------------------------------------"
  fi
  return 0
}  
```

- **Patch the Makefile**  
This routine patches the generated SQLite Makefile in the “build” folder, cleaning up the $(TOP) variable and ensuring that the Makefile takes ${CFLAGS}, ${CFLAGS_EXTRAS}, $(OPT_FEATURE_FLAGS), and $(LIBS) variables from the environment.

```bash
patch_sqlite3_makefile() {
  cd "${BASEDIR}/${BUILDDIR}" \
    || ( echo "Cannot enter ./${BUILDDIR}" && exit 108 )
  echo "____________________________"
  echo "Patching SQLite3 Makefile..."
  echo "----------------------------"
  sed -e "s|^TOP = \(.*\)$|TOP = ${BASEDIR}/${DBDIR}|;" \
      -e 's|^CFLAGS =\(.*\)$|CFLAGS :=\1 \${CFLAGS}|;' \
      -e 's|^\(TCC = \${CC} \${CFLAGS}\)\( [^$]\)|\1 \${CFLAGS_EXTRAS}\2|;' \
      -e 's|^OPT_FEATURE_FLAGS =\(.*\)$|OPT_FEATURE_FLAGS :=\1 \$(OPT_FEATURE_FLAGS)|;' \
      -e 's|\(--strip-all.*\$(REAL_LIBOBJ)\)\( \$(LIBS)\)*|\1 \$(LIBS)|;' \
      -i Makefile
  return 0
}
```

- **Set the variables from the previous step**  
This routine sets default library flags, flags for static binding of the standard libraries, ICU flags, and enables additional SQLite features.

```bash
set_sqlite3_extra_options() {
  DEFAULT_LIBS="-lpthread -lm -ldl"
  LIBOPTS="-static-libgcc -static-libstdc++"
  LIBS+="${LIBOPTS}"
  
  ICU_CFLAGS="$(icu-config --cflags --cppflags)"
  CFLAGS_EXTRAS+="${ICU_CFLAGS}"
  ICU_LDFLAGS="$(icu-config --ldflags --ldflags-system)"
  LIBS+="${ICU_LDFLAGS}"
  local libraries
  IFS=$' \n\t'
    libraries=( ${DEFAULT_LIBS} )
  IFS=$'\n\t'
  local library
  for library in "${libraries[@]}"; do
    if [[ -n "${LIBS##*${library}*}" ]]; then
      LIBS+=" ${library}"
    fi
  done
  
  FEATURES=(
    -D_HAVE_SQLITE_CONFIG_H
    -DSQLITE_DQS=0
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS
    -DSQLITE_MAX_EXPR_DEPTH=0
    -DSQLITE_OMIT_DEPRECATED
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1
    -DSQLITE_DEFAULT_SYNCHRONOUS=1
    -DSQLITE_ENABLE_COLUMN_METADATA
    -DSQLITE_ENABLE_DBPAGE_VTAB
    -DSQLITE_ENABLE_DBSTAT_VTAB
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS
    -DSQLITE_ENABLE_FTS3
    -DSQLITE_ENABLE_FTS3_PARENTHESIS
    -DSQLITE_ENABLE_FTS3_TOKENIZER
    -DSQLITE_ENABLE_MATH_FUNCTIONS
    -DSQLITE_ENABLE_QPSG
    -DSQLITE_ENABLE_RBU
    -DSQLITE_ENABLE_ICU
    -DSQLITE_ENABLE_STMTVTAB
    -DSQLITE_ENABLE_STAT4
    -DSQLITE_SOUNDEX
    -DNDEBUG
  )

  OPT_FEATURE_FLAGS="${FEATURES[@]}"
  
  export CFLAGS_EXTRAS OPT_FEATURE_FLAGS LIBS
  return 0
}
```

- **Run the *main* routine**  
The main routine calls the above subroutines and, in the end, runs the Makefile.

- **Copy required libraries**
    The following general libraries, if not statically linked, may be required:
    - libgcc_s_dw2-1.dll/libgcc_s_seh-1.dll
    - libstdc++\-6.dll
    - libwinpthread-1.dll
    
    ICU libraries:
    - libicudtXX.dll
    - libicuinXX.dll
    - libicuucXX.dll

    Copy these libraries from "${MINGW_PREFIX}/bin" to the folder containing SQLite binaries (system folder should also do the job).
