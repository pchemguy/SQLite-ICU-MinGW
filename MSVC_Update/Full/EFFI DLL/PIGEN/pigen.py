from typing import Sequence
from pathlib import Path
import re
import platform

from cffi import FFI

PROGRAM_NAME = "PIGEN"

def load_cdef_header(path: str | Path) -> str:
    declarations = Path(path).read_text(encoding="utf-8")

    return re.sub(
        r"(?m)^[A-Z][A-Z0-9_]*_API[ \t]+",
        "",
        declarations,
    )


def main(argv: Sequence[str] | None = None) -> int:
    ffibuilder = FFI()
    declarations = load_cdef_header(f"{PROGRAM_NAME.lower()}_api.h")
    ffibuilder.cdef(declarations)

    extra_compile_args = (
        ["/TC", "/O2"]
        if platform.python_compiler().startswith("MSC")
        else []
    )

    ffibuilder.set_source(
        f"_{PROGRAM_NAME.lower()}_wrapper",
    
        f"#include \"{PROGRAM_NAME.lower()}.h\"",
        #sources=[f"{PROGRAM_NAME.lower()}.c"],
        include_dirs=[".", "include",],
        libraries=[PROGRAM_NAME.lower()],
        library_dirs=[".", "lib",],
        define_macros=[
            (f"{PROGRAM_NAME.upper()}_C_API", None),
            (f"{PROGRAM_NAME.upper()}_BUILD_EXE", None),
        ],
        extra_compile_args=extra_compile_args,
    )

    ffibuilder.compile(verbose=True)


if __name__ == "__main__":
    raise SystemExit(main())
