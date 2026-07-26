I need a TCL script to be executed as part of a customized SQLite build pipeline. The pipeline amends the stock SQLite nmake build process on Windows with MSVC. The objective is to patch a set of extensions from ext\misc to make them integratable into SQLite amalgamation as autoextensions. The key part is at the end of each module responsible for initialization. These extra/misc extensions are designed to be compiled and loaded as loadable extensions on demand, so they do not incorporate the init mechanics used by autoloaded extensions included in the SQLite core. Here are two reference sections for extensions supporting both building/loading workflows:

## Reference AutoExtension Activation

### ICU

```c
/*
** Register the ICU extension functions with database db.
*/
int sqlite3IcuInit(sqlite3 *db){
  ...
  return rc;
}

#ifndef SQLITE_CORE
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_icu_init(
  sqlite3 *db, 
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  SQLITE_EXTENSION_INIT2(pApi)
  return sqlite3IcuInit(db);
}
#endif

#endif
```

### Rtree

```c
/*
** Register the r-tree module with database handle db. This creates the
** virtual table module "rtree" and the debugging/analysis scalar 
** function "rtreenode".
*/
int sqlite3RtreeInit(sqlite3 *db){

  return rc;
}

#ifndef SQLITE_CORE
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_rtree_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  SQLITE_EXTENSION_INIT2(pApi)
  return sqlite3RtreeInit(db);
}
#endif

#endif
```

Function
```
int sqlite3_<name>_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
)
```
is used by the on-demand loading.

`int sqlite3<Name>Init(sqlite3 *db)`
is used by automatic loader.

Every extension has `sqlite3_<name>_init`, but not `sqlite3<Name>Init(sqlite3 *db)`.

The script will accept a list of paths. 

Here are sample targets:

## Sample Targets

### CSV

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
/* 
** This routine is called when the extension is loaded.  The new
** CSV virtual table module is registered with the calling database
** connection.
*/
int sqlite3_csv_init(
  sqlite3 *db, 
  char **pzErrMsg, 
  const sqlite3_api_routines *pApi
){
#ifndef SQLITE_OMIT_VIRTUALTABLE
  int rc;
  SQLITE_EXTENSION_INIT2(pApi);
  rc = sqlite3_create_module(db, "csv", &CsvModule, 0);
#ifdef SQLITE_TEST
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_module(db, "csv_wr", &CsvModuleFauxWrite, 0);
  }
#endif
  return rc;
#else
  return SQLITE_OK;
#endif
}
```

### Decimal

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_decimal_init(
  sqlite3 *db, 
  char **pzErrMsg, 
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  static const struct {
    const char *zFuncName;
    int nArg;
    int iArg;
    void (*xFunc)(sqlite3_context*,int,sqlite3_value**);
  } aFunc[] = {
    { "decimal",       1, 0,  decimalFunc        },
    { "decimal",       2, 0,  decimalFunc        },
    { "decimal_exp",   1, 1,  decimalFunc        },
    { "decimal_exp",   2, 1,  decimalFunc        },
    { "decimal_cmp",   2, 0,  decimalCmpFunc     },
    { "decimal_add",   2, 0,  decimalAddFunc     },
    { "decimal_sub",   2, 0,  decimalSubFunc     },
    { "decimal_mul",   2, 0,  decimalMulFunc     },
    { "decimal_pow2",  1, 0,  decimalPow2Func    },
  };
  unsigned int i;
  (void)pzErrMsg;  /* Unused parameter */

  SQLITE_EXTENSION_INIT2(pApi);

  for(i=0; i<(int)(sizeof(aFunc)/sizeof(aFunc[0])) && rc==SQLITE_OK; i++){
    rc = sqlite3_create_function(db, aFunc[i].zFuncName, aFunc[i].nArg,
                   SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                   aFunc[i].iArg ? db : 0, aFunc[i].xFunc, 0, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_window_function(db, "decimal_sum", 1,
                   SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC, 0,
                   decimalSumStep, decimalSumFinalize,
                   decimalSumValue, decimalSumInverse, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_collation(db, "decimal", SQLITE_UTF8,
                                  0, decimalCollFunc);
  }
  return rc;
}
```

### Regexp

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_regexp_init(
  sqlite3 *db, 
  char **pzErrMsg, 
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;  /* Unused */
  rc = sqlite3_create_function(db, "regexp", 2, 
                            SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                            0, re_sql_func, 0, 0);
  if( rc==SQLITE_OK ){
    /* The regexpi(PATTERN,STRING) function is a case-insensitive version
    ** of regexp(PATTERN,STRING). */
    rc = sqlite3_create_function(db, "regexpi", 2,
                            SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                            (void*)db, re_sql_func, 0, 0);
#if defined(SQLITE_DEBUG)
    if( rc==SQLITE_OK ){
      rc = sqlite3_create_function(db, "regexp_bytecode", 1,
                            SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                            0, re_bytecode_func, 0, 0);
    }
#endif /* SQLITE_DEBUG */
  }
  return rc;
}
```

### Series

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_series_init(
  sqlite3 *db, 
  char **pzErrMsg, 
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);
#ifndef SQLITE_OMIT_VIRTUALTABLE
  if( sqlite3_libversion_number()<3008012 && pzErrMsg!=0 ){
    *pzErrMsg = sqlite3_mprintf(
        "generate_series() requires SQLite 3.8.12 or later");
    return SQLITE_ERROR;
  }
  rc = sqlite3_create_module(db, "generate_series", &seriesModule, 0);
#endif
  return rc;
}
```

### Sha1

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_sha_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  static int one = 1;
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;  /* Unused parameter */
  rc = sqlite3_create_function(db, "sha1", 1, 
                       SQLITE_UTF8 | SQLITE_INNOCUOUS | SQLITE_DETERMINISTIC,
                                0, sha1Func, 0, 0);
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sha1b", 1, 
                       SQLITE_UTF8 | SQLITE_INNOCUOUS | SQLITE_DETERMINISTIC,
                          (void*)&one, sha1Func, 0, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sha1_query", 1, 
                                 SQLITE_UTF8|SQLITE_DIRECTONLY, 0,
                                 sha1QueryFunc, 0, 0);
  }
  return rc;
}
```

### Shathree

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_shathree_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;  /* Unused parameter */
  rc = sqlite3_create_function(db, "sha3", 1,
                      SQLITE_UTF8 | SQLITE_INNOCUOUS | SQLITE_DETERMINISTIC,
                      0, sha3Func, 0, 0);
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sha3", 2,
                      SQLITE_UTF8 | SQLITE_INNOCUOUS | SQLITE_DETERMINISTIC,
                      0, sha3Func, 0, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sha3_agg", 1,
                      SQLITE_UTF8 | SQLITE_INNOCUOUS | SQLITE_DETERMINISTIC,
                      0, 0, sha3AggStep, sha3AggFinal);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sha3_agg", 2,
                      SQLITE_UTF8 | SQLITE_INNOCUOUS | SQLITE_DETERMINISTIC,
                      0, 0, sha3AggStep, sha3AggFinal);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sha3_query", 1,
                      SQLITE_UTF8 | SQLITE_DIRECTONLY,
                      0, sha3QueryFunc, 0, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sha3_query", 2,
                      SQLITE_UTF8 | SQLITE_DIRECTONLY,
                      0, sha3QueryFunc, 0, 0);
  }
  return rc;
}
```
### Sqlar

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_sqlar_init(
  sqlite3 *db, 
  char **pzErrMsg, 
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;  /* Unused parameter */
  rc = sqlite3_create_function(db, "sqlar_compress", 1, 
                               SQLITE_UTF8|SQLITE_INNOCUOUS, 0,
                               sqlarCompressFunc, 0, 0);
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "sqlar_uncompress", 2,
                                 SQLITE_UTF8|SQLITE_INNOCUOUS, 0,
                                 sqlarUncompressFunc, 0, 0);
  }
  return rc;
}
```

### Uint

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_uint_init(
  sqlite3 *db, 
  char **pzErrMsg, 
  const sqlite3_api_routines *pApi
){
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;  /* Unused parameter */
  return sqlite3_create_collation(db, "uint", SQLITE_UTF8, 0, uintCollFunc);
}
```

### Uuid

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_uuid_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  SQLITE_EXTENSION_INIT2(pApi);
  (void)pzErrMsg;  /* Unused parameter */
  rc = sqlite3_create_function(db, "uuid", 0, SQLITE_UTF8|SQLITE_INNOCUOUS, 0,
                               sqlite3UuidFunc, 0, 0);
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "uuid_str", 1, 
                       SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                       0, sqlite3UuidStrFunc, 0, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_function(db, "uuid_blob", 1,
                       SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                       0, sqlite3UuidBlobFunc, 0, 0);
  }
  return rc;
}
```

---
---

## Example Transformation

Let's consider

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_decimal_init(
  sqlite3 *db, 
  char **pzErrMsg, 
  const sqlite3_api_routines *pApi
){
  int rc = SQLITE_OK;
  static const struct {
    const char *zFuncName;
    int nArg;
    int iArg;
    void (*xFunc)(sqlite3_context*,int,sqlite3_value**);
  } aFunc[] = {
    { "decimal",       1, 0,  decimalFunc        },
    { "decimal",       2, 0,  decimalFunc        },
    { "decimal_exp",   1, 1,  decimalFunc        },
    { "decimal_exp",   2, 1,  decimalFunc        },
    { "decimal_cmp",   2, 0,  decimalCmpFunc     },
    { "decimal_add",   2, 0,  decimalAddFunc     },
    { "decimal_sub",   2, 0,  decimalSubFunc     },
    { "decimal_mul",   2, 0,  decimalMulFunc     },
    { "decimal_pow2",  1, 0,  decimalPow2Func    },
  };
  unsigned int i;
  (void)pzErrMsg;  /* Unused parameter */

  SQLITE_EXTENSION_INIT2(pApi);

  for(i=0; i<(int)(sizeof(aFunc)/sizeof(aFunc[0])) && rc==SQLITE_OK; i++){
    rc = sqlite3_create_function(db, aFunc[i].zFuncName, aFunc[i].nArg,
                   SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                   aFunc[i].iArg ? db : 0, aFunc[i].xFunc, 0, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_window_function(db, "decimal_sum", 1,
                   SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC, 0,
                   decimalSumStep, decimalSumFinalize,
                   decimalSumValue, decimalSumInverse, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_collation(db, "decimal", SQLITE_UTF8,
                                  0, decimalCollFunc);
  }
  return rc;
}
```

The script will need:

1. Change function name and signature to `sqlite3DecimalInit(sqlite3 *db)`
2. Remove `SQLITE_EXTENSION_INIT2(pApi);` (semicolon may be missing)
3. Remove   `(void)pzErrMsg;  /* Unused parameter */`
4. Remove

```c
#ifdef _WIN32
__declspec(dllexport)
#endif
```

5. Append

```c
#ifndef SQLITE_CORE
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_decimal_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  (void)pzErrMsg;  /* Unused parameter */
  SQLITE_EXTENSION_INIT2(pApi);
  return sqlite3DecimalInit(db);
}
#endif
```

Result:

```c
int sqlite3DecimalInit(sqlite3 *db){
  int rc = SQLITE_OK;
  static const struct {
    const char *zFuncName;
    int nArg;
    int iArg;
    void (*xFunc)(sqlite3_context*,int,sqlite3_value**);
  } aFunc[] = {
    { "decimal",       1, 0,  decimalFunc        },
    { "decimal",       2, 0,  decimalFunc        },
    { "decimal_exp",   1, 1,  decimalFunc        },
    { "decimal_exp",   2, 1,  decimalFunc        },
    { "decimal_cmp",   2, 0,  decimalCmpFunc     },
    { "decimal_add",   2, 0,  decimalAddFunc     },
    { "decimal_sub",   2, 0,  decimalSubFunc     },
    { "decimal_mul",   2, 0,  decimalMulFunc     },
    { "decimal_pow2",  1, 0,  decimalPow2Func    },
  };
  unsigned int i;

  for(i=0; i<(int)(sizeof(aFunc)/sizeof(aFunc[0])) && rc==SQLITE_OK; i++){
    rc = sqlite3_create_function(db, aFunc[i].zFuncName, aFunc[i].nArg,
                   SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC,
                   aFunc[i].iArg ? db : 0, aFunc[i].xFunc, 0, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_window_function(db, "decimal_sum", 1,
                   SQLITE_UTF8|SQLITE_INNOCUOUS|SQLITE_DETERMINISTIC, 0,
                   decimalSumStep, decimalSumFinalize,
                   decimalSumValue, decimalSumInverse, 0);
  }
  if( rc==SQLITE_OK ){
    rc = sqlite3_create_collation(db, "decimal", SQLITE_UTF8,
                                  0, decimalCollFunc);
  }
  return rc;
}

#ifndef SQLITE_CORE
#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_decimal_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  (void)pzErrMsg;  /* Unused parameter */
  SQLITE_EXTENSION_INIT2(pApi);
  return sqlite3DecimalInit(db);
}
#endif
```

File paths or names provided to script as CLI should be resolved relative to tclsh current directory.

## Activation Stub

The second task is to create the necessary activation code following the pattern:

```c
/*
** Forward declarations of external module initializer functions
** for modules that need them.
*/
#ifdef SQLITE_ENABLE_FTS5
int sqlite3Fts5Init(sqlite3*);
#endif
#ifdef SQLITE_ENABLE_STMTVTAB
int sqlite3StmtVtabInit(sqlite3*);
#endif
#ifdef SQLITE_EXTRA_AUTOEXT
int SQLITE_EXTRA_AUTOEXT(sqlite3*);
#endif
/*
** An array of pointers to extension initializer functions for
** built-in extensions.
*/
static int (*const sqlite3BuiltinExtensions[])(sqlite3*) = {
#ifdef SQLITE_ENABLE_FTS3
  sqlite3Fts3Init,
#endif
#ifdef SQLITE_ENABLE_FTS5
  sqlite3Fts5Init,
#endif
#if defined(SQLITE_ENABLE_ICU) || defined(SQLITE_ENABLE_ICU_COLLATIONS)
  sqlite3IcuInit,
#endif
#ifdef SQLITE_ENABLE_RTREE
  sqlite3RtreeInit,
#endif
#ifdef SQLITE_ENABLE_DBPAGE_VTAB
  sqlite3DbpageRegister,
#endif
#ifdef SQLITE_ENABLE_DBSTAT_VTAB
  sqlite3DbstatRegister,
#endif
  sqlite3TestExtInit,
#ifdef SQLITE_ENABLE_STMTVTAB
  sqlite3StmtVtabInit,
#endif
#ifdef SQLITE_ENABLE_BYTECODE_VTAB
  sqlite3VdbeBytecodeVtabInit,
#endif
#ifdef SQLITE_EXTRA_AUTOEXT
  SQLITE_EXTRA_AUTOEXT,
#endif
};
```

The script must create a dedicated module `misc_ext_init.c`, which will be integrated into SQLite amalgamation and should include forward declarations 

```c
#ifdef SQLITE_ENABLE_<NAME>
int sqlite3<Name>5Init(sqlite3*);
#endif
```

following by a dispatcher  (to be activate via `-DSQLITE_EXTRA_AUTOEXT=sqlite3ExtraAutoExtInit`)

```c
int sqlite3ExtraAutoExtInit(sqlite3 *db){
  int rc;
  /* Generated initializer calls. */
  return rc;
}
```

The script should be idempotent.
