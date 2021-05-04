#!/usr/make
#
# The current directory is switched to the SQLite3 build directory via the "-C" flag,
# and this file is copied to the the SQLite3 build directory by the shell script.
#

SQLITE3_DIR := $(abspath $(lastword $(MAKEFILE_LIST)))
SQLITE3_DIR := $(patsubst %/,%,$(dir $(SQLITE3_DIR)))/sqlite3
SQLITE3_BLD := $(SQLITE3_DIR)/build
SQLITE3_INC := $(SQLITE3_BLD)
SQLITE3_SRC := $(SQLITE3_BLD)

LIBS :=
DEFAULT_LIBS := -lpthread -ldl -lm
LIBOPTS := -static-libgcc -static-libstdc++

MAKEDEF = -Wl,--subsystem,windows \
          -Wl,--output-def,$@

MAKEDLL = -Wl,--subsystem,windows,--kill-at

MAKELIB = dlltool --kill-at -D $< -d $(<:.dll=.def) -l $@


ICU_LD := $(strip $(shell pkg-config --cflags --libs --static icu-i18n))
CYGPATH := $(shell which cygpath || echo "")
ifneq ($(CYGPATH),)
	ICU_LD := $(subst $(shell cygpath -m /),/,$(ICU_LD))
endif
LIBS += $(ICU_LD)
LIBS += $(filter-out $(LIBS),$(DEFAULT_LIBS))

#  Keep deprecated for the outdated ODBC driver
#  -DSQLITE_OMIT_DEPRECATED
FEATURES := \
  -D_HAVE_SQLITE_CONFIG_H \
  -DSQLITE_DQS=0 \
  -DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
  -DSQLITE_MAX_EXPR_DEPTH=0 \
  -DSQLITE_DEFAULT_FOREIGN_KEYS=1 \
  -DSQLITE_DEFAULT_SYNCHRONOUS=1 \
  -DSQLITE_ENABLE_COLUMN_METADATA \
  -DSQLITE_ENABLE_DBPAGE_VTAB \
  -DSQLITE_ENABLE_DBSTAT_VTAB \
  -DSQLITE_ENABLE_EXPLAIN_COMMENTS \
  -DSQLITE_ENABLE_FTS3 \
  -DSQLITE_ENABLE_FTS3_PARENTHESIS \
  -DSQLITE_ENABLE_FTS3_TOKENIZER \
  -DSQLITE_ENABLE_FTS4 \
  -DSQLITE_ENABLE_FTS5 \
  -DSQLITE_ENABLE_GEOPOLY \
  -DSQLITE_ENABLE_MATH_FUNCTIONS \
  -DSQLITE_ENABLE_JSON1 \
  -DSQLITE_ENABLE_QPSG \
  -DSQLITE_ENABLE_RBU \
  -DSQLITE_ENABLE_ICU \
  -DSQLITE_ENABLE_RTREE \
  -DSQLITE_ENABLE_STMTVTAB \
  -DSQLITE_ENABLE_STAT4 \
  -DSQLITE_SOUNDEX \
  -DNDEBUG

LD_OPTS := \
  -DNDEBUG \
  -DDLL_EXPORT \
  -DPIC

CC = gcc -Wall -O2

LOG_FILE ?= makelog.log
LOG_SECT_LABEL = >>$(LOG_FILE) echo '_______________________________$@_______________________________'
LOG_SECT_SEP   = >>$(LOG_FILE) echo ""
LOG_FMT_CLI    = >>$(LOG_FILE) sed -e 's/^[\t]* *//g; s/ +/ /g; s/ -/ \\\n-/g' <<<

# FarManager Colorer does not like unpaired quotes even as a literal, hence this construct
#QOUTE = $(shell echo '"')
#SOURCES = $(addprefix $(QOUTE),$(addsuffix $(QOUTE),$^))
BASE_CC = $(CC) -c $< $(FEATURES) $(CFLAGS) -o $@
#
# IMPORTANT: SOURCES MUST COME BEFORE ANY (REQUIRED) LIBRARIES IN THE LINK OR COMPILE/LINK COMMAND LINE!
#
BASE_LD = $(CC) -shared $^ $(LD_OPTS) $(CFLAGS) $(LIBS) $(LIBOPTS) $(EXPORT_OPTS)

define log_cli
	$(LOG_SECT_LABEL); \
	$(LOG_FMT_CLI) '$(CLI)'; \
	$(LOG_SECT_SEP);
endef

#
###############################################################################
all: src obj def dll lib

src: sqlite3.c
sqlite3.c: Makefile
	$(MAKE) $@

libshell.c: sqlite3.c shell.c
	@cp shell.c libshell.c; \
	sed -e 's/^int SQLITE_CDECL main/int SQLITE_CDECL sqlite3_main/;' \
		-e 's/appendText/shAppendText/g;' \
		-i libshell.c;
	@echo "#ifndef LIBSHELL_C"        >>sqlite3.c
	@echo "#define LIBSHELL_C"        >>sqlite3.c
	@echo "  #include \"libshell.c\"" >>sqlite3.c
	@echo "#endif /* _LIBSHELL_C_ */" >>sqlite3.c

obj: sqlite3.o
sqlite3.o: CLI = $(BASE_CC)
sqlite3.o: sqlite3.c libshell.c
    ifeq ($(NDEBUG),)
		@$(log_cli)
    endif
	$(CLI)

def: sqlite3.def
sqlite3.def: EXPORT_OPTS = $(MAKEDEF)
sqlite3.def: CLI = $(BASE_LD) -o $(@:.def=.dll)
sqlite3.def: sqlite3.o
    ifeq ($(NDEBUG),)
		@$(log_cli)
    endif
	$(CLI)
	rm $(<:.o=.dll)

dll: sqlite3.dll
sqlite3.dll: EXPORT_OPTS = $(MAKEDLL)
sqlite3.dll: CLI = $(BASE_LD) -o $@
sqlite3.dll: sqlite3.o
    ifeq ($(NDEBUG),)
		@$(log_cli)
    endif
	$(CLI)

lib: libsqlite3.a
libsqlite3.a: CLI = $(MAKELIB)
libsqlite3.a: sqlite3.dll sqlite3.def
    ifeq ($(NDEBUG),)
		@$(log_cli)
    endif
	$(CLI)
