/*
 * The corpus program: a ledger that caches its own total.
 * push invalidates the cache, total rebuilds it and holds it until the
 * next push, and every file in this folder tells that same story.
 */
import { readFile } from "node:fs/promises";

// A template literal, which is the only string in JavaScript allowed to carry
// a real newline rather than an escape for one.
const BANNER = `ledger receipt
--------------
`;

export class Ledger {
  #rows = [];
  #total = null;

  constructor(seed = []) {
    for (const v of seed) this.push(v);
  }

  push(v) {
    if (typeof v !== "number") throw new TypeError(`not a number: ${v}`);
    this.#rows.push(v);
    this.#total = null;
    return this;
  }

  get total() {
    if (this.#total === null) {
      this.#total = this.#rows.reduce((a, r) => (r > 0 ? a + r : a), 0);
    }
    return this.#total;
  }

  static async load(path) {
    const text = await readFile(path, "utf8");
    return new Ledger(JSON.parse(text).rows ?? []);
  }
}

const led = new Ledger([1, 2, 3]);
console.log(`${BANNER}total=${led.total}`);
