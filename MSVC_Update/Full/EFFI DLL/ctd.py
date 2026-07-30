from cffi import FFI

ffibuilder = FFI()

ffibuilder.cdef(
"""
    int ctd_add(int a, int b);
"""
)

ffibuilder.set_source(
    "_ctd",

    """
    #include "ctd.h"
    """,

    include_dirs=["include"],
    libraries=["ctd"],
    library_dirs=["lib"],
)

if __name__ == "__main__":
    ffibuilder.compile(verbose=True)
