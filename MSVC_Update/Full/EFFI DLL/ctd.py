from typing import Sequence
from pathlib import Path
import re

from cffi import FFI


def load_cdef_header(path: str | Path) -> str:
    declarations = Path(path).read_text(encoding="utf-8")

    return re.sub(
        r"(?m)^[A-Z][A-Z0-9_]*_API[ \t]+",
        "",
        declarations,
    )


def main(argv: Sequence[str] | None = None) -> int:
    ffibuilder = FFI()
    declarations = load_cdef_header("ctd_api.h")
    ffibuilder.cdef(declarations)

    ffibuilder.set_source(
        "_ctd_wrapper",
    
        """
        #include "ctd.h"
        """,
    
        include_dirs=["include"],
        libraries=["ctd"],
        library_dirs=["lib"],
        define_macros=[
            ("CTD_C_API", None),
            ("CTD_BUILD_EXE", None),
        ],
        extra_compile_args=[
            "/TC",
            "/W4",
            "/O2",
        ],
    )

    ffibuilder.compile(verbose=True)


if __name__ == "__main__":
    raise SystemExit(main())
