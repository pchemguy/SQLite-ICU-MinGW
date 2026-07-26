---
url: https://github.com/timlrx/sqlite-extension-template/blob/main/README.md
---

# SQLite Extension Template

This repository contains a template for building custom [SQLite] extensions in C / C++. It supports the following targets:

- Loadable module
- Static library
- WebAssembly build with fiddle
- Python package

Credits goes to [Alex Garcia](https://github.com/asg017/sqlite-ecosystem) for his numerous repositories which I adapted to create this scaffold. Check out his repositories for other build targets. I added a WASM target based on the official SQLite build (more info at my [blog post](https://www.timlrx.com/blog/sqlite-wasm-with-custom-extensions)). The WASM build requires compiling from the raw source tree, instead of relying on the amalgamation distribution.

The scaffold creates 2 functions (`rot13()` and `rot13_version()`), and a virtual table module with no implementation logic (`rot13`) as an SQLite extension.

The WASM build copies the contents in `src/` and the pre-processed header files to `sqlite/ext/wasm` and builds it over there. `sqlite_wasm_extra_init.c` is required to initialize the extension and `fiddle.make` overrides the default file and adds the extension to the fiddle.

If you encounter any issues, it might help to run `git clean -df` in the sqlite submodule before re-running the build process.

## Pre-requisites

In addition to platform specific build tools (e.g. llvm or build-essentials), the following tools are required:

- [CMake](https://cmake.org/)
- [Python](https://www.python.org/) with `pip install wheel`
- [Emscripten](https://github.com/emscripten-core/emsdk.git)
- [WASM Binary Toolkit](https://github.com/WebAssembly/wabt)

## Getting Started

Run the following command:

1. Clone the repository: `git clone --recurse-submodules https://github.com/username/rot13.git`
2. Build the loadable module: `make loadable`
3. Build the static library: `make static`
4. Build the Python package: `make python`
5. Build the WebAssembly module and fiddle: `make wasm`
6. Add your own files to the `src/` directory and update the code in the folders accordingly.

## Repository Structure

```
.
├── src/                          # Source code for the SQLite extension
│   ├── rot13.c
│   ├── rot13.h.in
|   |── fiddle.make               # Overrides the default make file to add the extension to the fiddle
│   └── sqlite_wasm_extra_init.c  # Required for WASM build
├── tests/                        # Contains the test suite for the SQLite extension
│   ├── test_loadable.sql         # Contains the SQL test cases for the loadable module
│   └── test_rot13.py             # Contains the Python test cases for the rot13 virtual table module
├── build/                        # Intermediate build files
├── build_release/                # Intermediate build files when making the release targets
├── vendor/
│   └── sqlite/                   # Git submodule for the SQLite library
├── dist/
│   ├── debug/                    # Debug build artifacts
│   └── release/                  # Release build artifacts
├── scripts/
|   └── rename_wheels.py
├── bindings/                     # Bindings for other builds
│   └── python/
├── CMakeLists.txt
├── Makefile
└── README.md
```

Running `make python` will generate an installable wheels in `dist/debug/wheels`.

The output of `make wasm` is located at `dist/debug/wasm` and includes a fiddle with the extension built-in. Test it out by running `python -m http.server` and browsing the directory content.

## Makefile

The Makefile in this repository contains the following targets:

- `loadable`: builds a loadable version of the extension. The module will be located in `dist/debug`, with file extensions `.dylib`, `.so`, or `.dll` depending on your operating system
- `loadable-release`: release version of the loadable module located in `dist/release`
- `static`: builds the static version of the extension. `.a` and `.h` files are located in `dist/debug` and can be used to statically link with other projects.
- `static-release`: release version of the static library located in `dist/release`
- `wasm`: builds the WebAssembly module including SQLite fiddle. Built files and demos are copied to `dist/debug/wasm`.
- `wasm-release`: builds the WebAssembly module for release. Built files are copied to `dist/release/wasm`.
- `python`: builds the Python wheels in debug mode. Built files are located at `dist/debug/wheels`.
- `python-release`: builds the Python wheels for release. Built files are located at `dist/release/wheels`.
- `python-versions`: updates the version file for the Python package
- `test-loadable`: test the Python loadable module
- `test-python`: test the Python package (requires installation)
- `test`: runs both the loadable module test and the Python package test
- `clean`: removes all dist files

[SQLite]: https://sqlite.org/index.html