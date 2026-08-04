export interface Row {
  tag: string;
  value: number;
}

type Cached<T> = { readonly held: T } | null;

export class Ledger {
  private rows: Row[] = [];
  private total: Cached<number> = null;

  constructor(seed: readonly number[] = []) {
    seed.forEach((v, i) => this.push(`seed${i}`, v));
  }

  push(tag: string, value: number): this {
    if (!Number.isFinite(value)) throw new TypeError(`not finite: ${value}`);
    this.rows.push({ tag, value });
    this.total = null;
    return this;
  }

  get sum(): number {
    if (this.total === null) {
      const held = this.rows.reduce((a, r) => (r.value > 0 ? a + r.value : a), 0);
      this.total = { held };
    }
    return this.total.held;
  }

  find(tag: string): Row | undefined {
    return this.rows.find((r) => r.tag === tag);
  }
}

const led = new Ledger([1, 2, 3]);
console.log(`total=${led.sum}`);
