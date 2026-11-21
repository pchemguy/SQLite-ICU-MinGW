/* Run SQL on a plain library connection. Used for both forms of linkage. */
#include <stdio.h>
#include <sqlite3.h>

static int print_row(void *arg, int n, char **values, char **columns) {
    (void)arg;
    (void)columns;
    for (int i = 0; i < n; ++i) {
        if (i) putchar('|');
        fputs(values[i] ? values[i] : "NULL", stdout);
    }
    putchar('\n');
    return 0;
}

int main(int argc, char **argv) {
    sqlite3 *db = NULL;
    char *error = NULL;
    if (argc != 2) return 2;
    int rc = sqlite3_open(":memory:", &db);
    if (rc == SQLITE_OK) rc = sqlite3_exec(db, argv[1], print_row, NULL, &error);
    if (rc != SQLITE_OK) fprintf(stderr, "%s\n", error ? error : sqlite3_errmsg(db));
    sqlite3_free(error);
    sqlite3_close(db);
    return rc != SQLITE_OK;
}
