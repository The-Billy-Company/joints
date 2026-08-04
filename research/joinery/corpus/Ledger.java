/*
 * The corpus program: a ledger that caches its own total.
 * push invalidates the cache, total rebuilds it and holds it until the
 * next push, and every file in this folder tells that same story.
 */
package com.example;

import java.util.ArrayList;
import java.util.List;

public final class Ledger {
    // A text block. The opening delimiter must be followed by a newline, so
    // this token cannot be written on one line even if you wanted to.
    private static final String BANNER = """
            ledger receipt
            --------------
            """;

    private final List<Integer> rows = new ArrayList<>();
    private Integer total;

    public Ledger(List<Integer> seed) {
        if (seed != null) rows.addAll(seed);
    }

    public int total() {
        if (total == null) {
            int acc = 0;
            for (int r : rows) if (r > 0) acc += r;
            total = acc;
        }
        return total;
    }

    public Ledger merge(Ledger other) {
        rows.addAll(other.rows);
        total = null;
        return this;
    }

    public static void main(String[] args) {
        Ledger led = new Ledger(List.of(1, 2, 3));
        System.out.print(BANNER);
        System.out.println("total=" + led.total());
    }
}
