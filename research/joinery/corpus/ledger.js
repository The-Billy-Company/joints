import { readFile } from "node:fs/promises";

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
console.log(`total=${led.total}`);
