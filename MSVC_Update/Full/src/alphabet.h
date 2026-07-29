/*
** alphabet.h
**
*/

#include <stdint.h>

#ifndef SQLITE_CORE
# include "sqlite3ext.h"
  SQLITE_EXTENSION_INIT1
#else
# include "sqlite3.h"
#endif

#ifndef PYTEST_API
# ifdef PYTEST_C_API
#  if defined(_WIN32)
#   define PYTEST_API __declspec(dllexport)
#  else
#   define PYTEST_API __attribute__((visibility("default")))
#  endif
# else
#  define PYTEST_API static
# endif
#endif

#define LATIN_UTF8 \
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
  "abcdefghijklmnopqrstuvwxyz"

#define CYRILLIC_UTF8 \
  "ÀÁÂÃÄÅ¨ÆÇÈÉÊËÌÍÎÏĞÑÒÓÔÕÖ×ØÙÚÛÜİŞß" \
  "àáâãäå¸æçèéêëìíîïğñòóôõö÷øùúûüışÿ"

PYTEST_API int ab_utf8_byte_count(const char *zText);
PYTEST_API int64_t ab_utf8_length(const char *zText);
PYTEST_API int ab_utf8_byte_offset(const char *zText, int64_t i);
PYTEST_API const char *ab_alphabet_select(const char *zLanguage);
