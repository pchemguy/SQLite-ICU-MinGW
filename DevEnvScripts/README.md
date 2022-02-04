## Usage Notes

This directory contains a set of Batch scripts for setting up reproducible command-line development environments on Windows based on MSVC Build Tools and MSYS2/MinGW.

These scripts should be executed from a regular non-admin account. In the directory, containing the scripts, they create three sub-directories:

  - pkg - caches downloaded packages/tools
  - bld - caches build files
  - dev - contains "installed" tools.

Each script may add the associated tool to Path or set other environment variables with build flags. If the tool is already installed in *dev*, the script skips installation and sets the environment variables only. This way, the necessary tools can be activated by calling the associtated scripts at the top of a task-specific script.

### MSVC toolchain

Setting up MSVC environment from scratch is a bit complicated, so the user of these scripts is expected to install MSVC Build Tools, Windows SDK, and CMake (all three from a Visual Studio installer). A recent doNet framework should also be installed.

Some tools are obtained as binary releases (those scripts can be executed from a regular cmd.exe shell) and some are built from sources (those scripts must be executed from an MSVC shell).

### MSYS2/MinGW toolchain

While most of these scripts are focused on the MSVC toolchain, several included scripts permit setting up an MSYS/MinGW development environment from scratch.

### Prerequisites

These scripts require cURL.exe and tar.exe and assume that they are in Path. These tools should be available in Windows 10. Otherwise, they must be downloaded and installed in Path.

cURL binaries are available from https://curl.se/windows/.

x64 Tar binaries are readily available from http://www.libarchive.org/.

For x32 Tar binatires, there are several options. An outdated version is available from GNUWin32 http://gnuwin32.sourceforge.net/packages/gtar.htm.

A second option is obtaining tar and its dependencies from MSYS2 (https://packages.msys2.org/package/tar). Note that MSYS packages are ZST packed (See https://github.com/facebook/zstd and sources referenced by the developer https://facebook.github.io/zstd/).

A third option involves building tar from sources (https://github.com/libarchive/libarchive/wiki/BuildInstructions).
