/*
** pigen.h
**
** Estimates pi using a Monte Carlo simulation.
*/

#ifndef PIGEN_H
#define PIGEN_H

#include <stdlib.h>
#include <math.h>


/****************************** API Declaration ******************************/

/*
** ```markdown
** ## Build Modes
** 
** | Defines                           | `PIGEN_API`                                       |
** | --------------------------------- | ------------------------------------------------- |
** | `PIGEN_C_API` + `PIGEN_BUILD_LIB` | exported DLL/shared-library symbol                |
** | `PIGEN_C_API` + `PIGEN_BUILD_EXE` | imported DLL symbol on Windows; default elsewhere |
** | `PIGEN_C_API_DEFAULT`             | default declaration                               |
** | none                              | `static`                                          |
** ```
*/

#if defined(PIGEN_C_API)

#  if defined(PIGEN_BUILD_LIB)

#    if defined(_WIN32)
#      define PIGEN_API __declspec(dllexport)
#    elif defined(__GNUC__) || defined(__clang__)
#      define PIGEN_API __attribute__((visibility("default")))
#    else
#      define PIGEN_API
#    endif

#  elif defined(PIGEN_BUILD_EXE)

#    if defined(_WIN32)
#      define PIGEN_API __declspec(dllimport)
#    else
#      define PIGEN_API
#    endif

#  else
#    error "PIGEN_C_API requires PIGEN_BUILD_LIB or PIGEN_BUILD_EXE"
#  endif

#elif defined(PIGEN_C_API_DEFAULT)

#  define PIGEN_API

#else

#  define PIGEN_API static

#endif

/*----------------------------- API Declaration -----------------------------*/


#ifdef __cplusplus
extern "C" {
#endif

#include "pigen_api.h"

#ifdef __cplusplus
}
#endif

#endif /* PIGEN_H */
