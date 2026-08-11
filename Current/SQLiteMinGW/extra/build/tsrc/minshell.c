#ifdef SQLITE_ENABLE_LIBSHELL


#ifndef SQLITE_SHELL_IS_UTF8
#  if (defined(_WIN32) || defined(WIN32)) \
   && (defined(_MSC_VER) || (defined(UNICODE) && defined(__GNUC__)))
#    define SQLITE_SHELL_IS_UTF8          (0)
#  else
#    define SQLITE_SHELL_IS_UTF8          (1)
#  endif
#endif


#if SQLITE_SHELL_IS_UTF8
int SQLITE_CDECL libshell_main(int argc, char **argv);
#else
int SQLITE_CDECL wmain(int argc, wchar_t **wargv);
#endif


#ifdef _WIN32
__declspec(dllexport)
#endif
#if SQLITE_SHELL_IS_UTF8
int sqlite3_libshell_main(int argc, char **argv){
  return libshell_main(argc, argv);
}
#else
int sqlite3_libshell_main(int argc, wchar_t **wargv){
  return wmain(argc, wargv);
}
#endif


#endif /* SQLITE_ENABLE_LIBSHELL */
