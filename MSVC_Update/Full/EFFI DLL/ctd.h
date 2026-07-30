/*
** ctd.h
**
** Standalone C99 DLL fixture for exploring Python CFFI.
*/

#ifndef CTD_H
#define CTD_H

#include <stddef.h>
#include <stdint.h>

#ifdef CTD_STATIC
# define CTD_API
#elif defined(_WIN32)
# ifdef CTD_BUILD_DLL
#  define CTD_API __declspec(dllexport)
# else
#  define CTD_API __declspec(dllimport)
# endif
#elif defined(__GNUC__) || defined(__clang__)
# define CTD_API __attribute__((visibility("default")))
#else
# define CTD_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*
** Constants.
*/
#define LATIN \
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
  "abcdefghijklmnopqrstuvwxyz"

#include "ctd_api.h"

#ifdef __cplusplus
}
#endif

#endif /* CTD_H */
