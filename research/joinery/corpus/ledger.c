#include <stdio.h>
#include <stdlib.h>

typedef struct Ledger {
    int *rows;
    size_t len, cap;
    long total;
    int dirty;
} Ledger;

static int ledger_push(Ledger *l, int v) {
    if (l->len == l->cap) {
        size_t cap = l->cap ? l->cap * 2 : 8;
        int *grown = realloc(l->rows, cap * sizeof *grown);
        if (!grown) return -1;
        l->rows = grown;
        l->cap = cap;
    }
    l->rows[l->len++] = v;
    l->dirty = 1;
    return 0;
}

long ledger_total(Ledger *l) {
    if (l->dirty) {
        long acc = 0;
        for (size_t i = 0; i < l->len; i++)
            if (l->rows[i] > 0) acc += l->rows[i];
        l->total = acc;
        l->dirty = 0;
    }
    return l->total;
}

int main(int argc, char **argv) {
    Ledger l = {0};
    for (int i = 1; i < argc; i++) ledger_push(&l, atoi(argv[i]));
    printf("total=%ld\n", ledger_total(&l));
    free(l.rows);
    return 0;
}
