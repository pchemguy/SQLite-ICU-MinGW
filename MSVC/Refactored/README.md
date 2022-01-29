PREREQUISITES

These scripts require cURL.exe and tar.exe and assume that they are in Path. These
tools should be available in Windows 10. Otherwise, they must be downloaded and
installed in Path.

cURL binaries are available from https://curl.se/windows/.

x64 Tar binaries are readily available forom http://www.libarchive.org/.

For x32 Tas binatires, there are several options. A very old x32 version is
available from GNUWin32 http://gnuwin32.sourceforge.net/packages/gtar.htm.

A second option is obtaining tar and its dependencies from MSYS2
(https://packages.msys2.org/package/tar). Note that MSYS packages are ZST packed
(ZST archiver binaries are available from https://github.com/facebook/zstd and
from sources referenced by the developer https://facebook.github.io/zstd/).

A third option involves building tar from sources
(https://github.com/libarchive/libarchive/wiki/BuildInstructions).

Some of these scripts can be executed from a regular cmd shell. However, in
general, they should be executed from an MS Build Tools shell. At least,
MSVC Build Tools and a system specific Windows Resource Kit should be installed
before using these scripts. A recent doNet framework should also be installed.