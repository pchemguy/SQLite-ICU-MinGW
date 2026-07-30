from typing import Sequence
from pathlib import Path
import re
import platform

from cffi import FFI


PROGRAM_NAME = "CTD"


def load_cdef_header(path: str | Path) -> str:
    header_path = Path(path)
    declarations = header_path.read_text(encoding="utf-8")

    guard = re.sub(r"[^A-Za-z0-9]", "_", header_path.name).upper()
    escaped_guard = re.escape(guard)

    declarations = re.sub(
        rf"^[ \t]*#[ \t]*ifndef[ \t]+{escaped_guard}[ \t]*(?:\r?\n|$)",
        "",
        declarations,
        flags=re.MULTILINE,
    )

    declarations = re.sub(
        rf"^[ \t]*#[ \t]*define[ \t]+{escaped_guard}[ \t]*(?:\r?\n|$)",
        "",
        declarations,
        flags=re.MULTILINE,
    )

    declarations = re.sub(
        rf"^[ \t]*#[ \t]*endif"
        rf"(?:[ \t]*/\*[ \t]*{escaped_guard}[ \t]*\*/)?"
        rf"[ \t]*(?:\r?\n|$)",
        "",
        declarations,
        flags=re.MULTILINE,
    )

    declarations = re.sub(
        r"^[A-Z][A-Z0-9_]*_API[ \t]+",
        "",
        declarations,
        flags=re.MULTILINE,
    )

    return declarations


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
        sources=[f"{PROGRAM_NAME.lower()}.c"],
        include_dirs=[".", "include",],
        #libraries=[PROGRAM_NAME.lower()],
        library_dirs=[".", "lib",],
        define_macros=[
            (f"{PROGRAM_NAME.upper()}_C_API", None),
            (f"{PROGRAM_NAME.upper()}_BUILD_LIB", None),
        ],
        extra_compile_args=extra_compile_args,
    )

    ffibuilder.compile(verbose=True)


if __name__ == "__main__":
    raise SystemExit(main())
