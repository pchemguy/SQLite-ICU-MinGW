/*
** alphabet.c
**
** SQLite extension providing:
**
**   alpha_string(language [, start [, length]])
**
** language:
**   "en" or "English"  -> Latin alphabet
**   "ru" or "Russian"  -> Russian Cyrillic alphabet
**
** language matching is case-insensitive.
**
** start is a zero-based Unicode code-point index. A negative value counts
** backward from the end of the selected alphabet.
**
** length is an optional non-negative number of Unicode code points.
**
** Examples:
**
**   SELECT alpha_string('en');
**   SELECT alpha_string('English', 3);
**   SELECT alpha_string('ru', -5);
**   SELECT alpha_string('Russian', 2, 4);
**
** https://chatgpt.com/c/6a6618c4-48b0-83eb-851b-7a60f648fbae
*/

#ifndef SQLITE_CORE
# include "sqlite3ext.h"
  SQLITE_EXTENSION_INIT1
#else
# include "sqlite3.h"
#endif

#ifdef PYTEST_STATIC
# if defined(_WIN32)
#  define PYTEST_API __declspec(dllexport)
# else
#  define PYTEST_API __attribute__((visibility("default")))
# endif
#else
# define PYTEST_API static
#endif

#define LATIN_UTF8 \
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
  "abcdefghijklmnopqrstuvwxyz"

#define CYRILLIC_UTF8 \
  "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ" \
  "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"

/*
** Return the byte length of the UTF-8 code point beginning at z.
*/
PYTEST_API int ab_utf8_byte_count(const unsigned char *z){
  if( z[0] < 0x80 ) return 1;
  if( (z[0] & 0xE0) == 0xC0 ) return 2;
  if( (z[0] & 0xF0) == 0xE0 ) return 3;
  return 4;
}

/*
** Return the number of Unicode code points in a valid UTF-8 string.
*/
PYTEST_API sqlite3_int64 ab_utf8_length(const char *z){
  const unsigned char *p = (const unsigned char *)z;
  sqlite3_int64 n = 0;

  while( *p!=0 ){
    p += ab_utf8_byte_count(p);
    ++n;
  }
  return n;
}

/*
** Return the byte offset corresponding to Unicode code-point index i.
** The caller guarantees 0 <= i <= ab_utf8_length(z).
*/
PYTEST_API int ab_utf8_byte_offset(const char *z, sqlite3_int64 i){
  const unsigned char *p = (const unsigned char *)z;
  const unsigned char *pStart = p;

  while( i>0 ){
    p += ab_utf8_byte_count(p);
    --i;
  }
  return (int)(p - pStart);
}

/*
** Resolve language to one of the supported alphabet strings.
** Return NULL for an unsupported language.
*/
PYTEST_API const char *ab_alphabet_select(const char *zLanguage){
  if( sqlite3_stricmp(zLanguage, "en")==0
   || sqlite3_stricmp(zLanguage, "English")==0
  ){
    return LATIN_UTF8;
  }

  if( sqlite3_stricmp(zLanguage, "ru")==0
   || sqlite3_stricmp(zLanguage, "Russian")==0
  ){
    return CYRILLIC_UTF8;
  }

  return 0;
}

/*
** SQL implementation of alpha_string().
*/
static void alphabetStringFunc(
  sqlite3_context *context,
  int argc,
  sqlite3_value **argv
){
  const char *zLanguage;
  const char *zAlphabet;
  sqlite3_int64 nChars;
  sqlite3_int64 iStart = 0;
  sqlite3_int64 nResult;
  int iByteStart;
  int iByteEnd;

  /*
  ** NULL propagates. This also permits calls such as
  ** alpha_string('en', NULL) to return NULL.
  */
  if( sqlite3_value_type(argv[0])==SQLITE_NULL
   || (argc>=2 && sqlite3_value_type(argv[1])==SQLITE_NULL)
   || (argc>=3 && sqlite3_value_type(argv[2])==SQLITE_NULL)
  ){
    sqlite3_result_null(context);
    return;
  }

  if( sqlite3_value_type(argv[0])!=SQLITE_TEXT ){
    sqlite3_result_error(
      context,
      "alpha_string() language must be text",
      -1
    );
    return;
  }
  
  zLanguage = (const char *)sqlite3_value_text(argv[0]);
  if( zLanguage==0 ){
    sqlite3_result_error_nomem(context);
    return;
  }

  zAlphabet = ab_alphabet_select(zLanguage);
  if( zAlphabet==0 ){
    sqlite3_result_error(
      context,
      "alpha_string() language must be en, English, ru, or Russian",
      -1
    );
    return;
  }

  nChars = ab_utf8_length(zAlphabet);

  if( argc>=2 ){
    if( sqlite3_value_type(argv[1])!=SQLITE_INTEGER ){
      sqlite3_result_error(
        context,
        "alpha_string() start must be an integer",
        -1
      );
      return;
    }
    iStart = sqlite3_value_int64(argv[1]);

    if( iStart < -nChars || iStart > nChars ){
      sqlite3_result_error(
        context,
        "alpha_string() start index is out of range",
        -1
      );
      return;
    }
    
    if( iStart<0 ){
      iStart += nChars;
    }
  }

  nResult = nChars - iStart;

  if( argc==3 ){
    sqlite3_int64 nRequested;

    if( sqlite3_value_type(argv[2])!=SQLITE_INTEGER ){
      sqlite3_result_error(
        context,
        "alpha_string() length must be an integer",
        -1
      );
      return;
    }

    nRequested = sqlite3_value_int64(argv[2]);
    if( nRequested<0 ){
      sqlite3_result_error(
        context,
        "alpha_string() length must not be negative",
        -1
      );
      return;
    }

    if( nRequested<nResult ){
      nResult = nRequested;
    }
  }

  iByteStart = ab_utf8_byte_offset(zAlphabet, iStart);
  iByteEnd = ab_utf8_byte_offset(zAlphabet, iStart + nResult);

  sqlite3_result_text(
    context,
    zAlphabet + iByteStart,
    iByteEnd - iByteStart,
    SQLITE_TRANSIENT
  );
}

#ifndef SQLITE_CORE
# define sqlite3AlphabetInit sqlite3AlphabetInit_Standalone
#endif

/*
** Register the extension's SQL functions.
**
** Three fixed arities are registered so SQLite itself rejects calls with
** zero arguments or more than three arguments.
*/
int sqlite3AlphabetInit(sqlite3 *db){
  static const int flags =
      SQLITE_UTF8
    | SQLITE_DETERMINISTIC
    | SQLITE_INNOCUOUS;
  int rc;

  rc = sqlite3_create_function(
    db, "alpha_string", 1, flags, 0,
    alphabetStringFunc, 0, 0
  );
  if( rc!=SQLITE_OK ) return rc;

  rc = sqlite3_create_function(
    db, "alpha_string", 2, flags, 0,
    alphabetStringFunc, 0, 0
  );
  if( rc!=SQLITE_OK ) return rc;

  return sqlite3_create_function(
    db, "alpha_string", 3, flags, 0,
    alphabetStringFunc, 0, 0
  );
}

#ifndef SQLITE_CORE
# if defined(_WIN32)
__declspec(dllexport)
# endif
int sqlite3_alphabet_init(
  sqlite3 *db,
  char **pzErrMsg,
  const sqlite3_api_routines *pApi
){
  (void)pzErrMsg;
  SQLITE_EXTENSION_INIT2(pApi);
  return sqlite3AlphabetInit(db);
}
#endif
