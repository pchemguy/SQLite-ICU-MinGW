---
layout: default
title: Alternative Approach
nav_order: 7
permalink: /alternative
---

The approach discussed in the previous section is based on a single shell script, which prepares the environment and runs SQLite Makefile. Alternatively, a custom [make][CustomSQLiteMake] script can "include" the SQLite Makefile and run custom recipes. In this case, the associated shell [script][Custom SQLite Make Shell] is responsible for minimum preparation.

<!---
### References
--->

[CustomSQLiteMake]: https://raw.githubusercontent.com/pchemguy/SQLite-ICU-MinGW/master/MinGW/Independent/sqlite3.ref.mk
[Custom SQLite Make Shell]: https://raw.githubusercontent.com/pchemguy/SQLite-ICU-MinGW/master/MinGW/Independent/sqlite3.ref.sh
