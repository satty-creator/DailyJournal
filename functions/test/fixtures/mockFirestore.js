/* A minimal in-memory Firestore, enough to run the derived pipeline end to end
 * without emulators, network or credentials.
 *
 * This exists because `node --check` proves syntax and the unit tests prove
 * arithmetic, but neither catches the errors that actually break a deploy:
 * a mistyped field name, a missing await, a query shape Firestore rejects, a
 * batch that exceeds 500 writes. Those only show up when something walks the
 * whole orchestration, and the Firebase emulator cannot help — it does not
 * implement task queues (functions/index.js header).
 *
 * Deliberately strict where Firestore is strict:
 *   - a range/order query on a field a document lacks EXCLUDES that document,
 *     silently, which is the trap documented in mineHypothesesForUser
 *   - map keys containing "." are rejected
 *   - batches over 500 operations throw
 *   - undefined values are rejected
 */

"use strict";

const MAX_BATCH = 500;

class Timestamp {
  constructor(ms) { this._ms = ms; }
  toDate() { return new Date(this._ms); }
  toMillis() { return this._ms; }
  static fromDate(d) { return new Timestamp(d.getTime()); }
  static fromMillis(ms) { return new Timestamp(ms); }
  static now() { return new Timestamp(Date.now()); }
}

function assertWritable(value, path = "") {
  if (value === undefined) {
    throw new Error(`Firestore rejects undefined at "${path}"`);
  }
  if (value === null || value instanceof Timestamp || value instanceof Date) return;
  if (Array.isArray(value)) {
    value.forEach((v, i) => {
      if (Array.isArray(v)) {
        throw new Error(`Firestore rejects nested arrays at "${path}[${i}]"`);
      }
      assertWritable(v, `${path}[${i}]`);
    });
    return;
  }
  if (typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      if (k.includes(".")) {
        throw new Error(`Firestore map key contains "." at "${path}.${k}"`);
      }
      if (k.startsWith("__")) {
        throw new Error(`Firestore reserves keys starting with "__" at "${path}.${k}"`);
      }
      if (k === "") throw new Error(`empty map key at "${path}"`);
      assertWritable(v, `${path}.${k}`);
    }
  }
}

function deepClone(v) {
  if (v === null || typeof v !== "object") return v;
  if (v instanceof Timestamp) return v;
  if (v instanceof Date) return new Date(v.getTime());
  if (Array.isArray(v)) return v.map(deepClone);
  const out = {};
  for (const [k, x] of Object.entries(v)) out[k] = deepClone(x);
  return out;
}

function valueOf(doc, field) {
  return field.split(".").reduce((o, k) => (o == null ? undefined : o[k]), doc);
}

function cmp(a, b) {
  const av = a instanceof Timestamp ? a.toMillis() : a;
  const bv = b instanceof Timestamp ? b.toMillis() : b;
  if (av === bv) return 0;
  return av < bv ? -1 : 1;
}

class Query {
  constructor(store, path, filters = [], orders = [], lim = null, sel = null) {
    this.store = store; this.path = path;
    this.filters = filters; this.orders = orders; this._limit = lim; this._select = sel;
  }
  where(field, op, value) {
    return new Query(this.store, this.path,
      [...this.filters, { field, op, value }], this.orders, this._limit, this._select);
  }
  orderBy(field, dir = "asc") {
    return new Query(this.store, this.path, this.filters,
      [...this.orders, { field, dir }], this._limit, this._select);
  }
  limit(n) {
    return new Query(this.store, this.path, this.filters, this.orders, n, this._select);
  }
  select(...fields) {
    return new Query(this.store, this.path, this.filters, this.orders, this._limit, fields);
  }
  /** Matches the real API shape: `count()` returns an AggregateQuery, which
   *  you then `.get()` for an AggregateQuerySnapshot. Returning the snapshot
   *  directly would let a broken call site pass here and fail in production. */
  count() {
    const self = this;
    return {
      get: async () => {
        const snap = await self.get();
        return { data: () => ({ count: snap.size }) };
      },
    };
  }
  async get() {
    const col = this.store.collections.get(this.path) || new Map();
    let docs = [...col.entries()].map(([id, data]) => ({ id, data }));

    for (const f of this.filters) {
      docs = docs.filter(({ data }) => {
        const v = valueOf(data, f.field);
        // THE TRAP: a document missing the filtered field is excluded, with no
        // error. This is why the pipeline never range-queries on entryCreatedAt.
        if (v === undefined) return false;
        switch (f.op) {
          case ">=": return cmp(v, f.value) >= 0;
          case ">":  return cmp(v, f.value) > 0;
          case "<=": return cmp(v, f.value) <= 0;
          case "<":  return cmp(v, f.value) < 0;
          case "==": return cmp(v, f.value) === 0;
          default: throw new Error(`unsupported op ${f.op}`);
        }
      });
    }
    for (const o of [...this.orders].reverse()) {
      // Same exclusion rule applies to orderBy.
      docs = docs.filter(({ data }) => valueOf(data, o.field) !== undefined);
      docs.sort((a, b) => {
        const r = cmp(valueOf(a.data, o.field), valueOf(b.data, o.field));
        return o.dir === "desc" ? -r : r;
      });
    }
    if (this._limit != null) docs = docs.slice(0, this._limit);

    const self = this;
    return {
      size: docs.length,
      empty: docs.length === 0,
      docs: docs.map(({ id, data }) => ({
        id,
        exists: true,
        ref: new DocRef(self.store, self.path, id),
        data: () => {
          if (!self._select) return deepClone(data);
          const out = {};
          for (const f of self._select) if (f in data) out[f] = deepClone(data[f]);
          return out;
        },
        get: (f) => valueOf(data, f),
      })),
    };
  }
}

class DocRef {
  constructor(store, colPath, id) {
    this.store = store; this.colPath = colPath; this.id = id;
    this.path = `${colPath}/${id}`;
  }
  collection(name) { return new CollectionRef(this.store, `${this.path}/${name}`); }
  async get() {
    const col = this.store.collections.get(this.colPath);
    const data = col && col.get(this.id);
    return {
      id: this.id,
      exists: data !== undefined,
      ref: this,
      data: () => (data === undefined ? undefined : deepClone(data)),
      get: (f) => (data === undefined ? undefined : valueOf(data, f)),
    };
  }
  async set(data, opts) { this.store._set(this.colPath, this.id, data, opts); }
  async update(data) {
    const col = this.store.collections.get(this.colPath);
    if (!col || !col.has(this.id)) throw new Error(`update on missing doc ${this.path}`);
    this.store._set(this.colPath, this.id, data, { merge: true });
  }
  async delete() {
    const col = this.store.collections.get(this.colPath);
    if (col) col.delete(this.id);
  }
}

class CollectionRef extends Query {
  constructor(store, path) { super(store, path); }
  doc(id) { return new DocRef(this.store, this.path, id); }
}

class Batch {
  constructor(store) { this.store = store; this.ops = []; }
  set(ref, data, opts) { this.ops.push(["set", ref, data, opts]); return this; }
  update(ref, data) { this.ops.push(["set", ref, data, { merge: true }]); return this; }
  delete(ref) { this.ops.push(["delete", ref]); return this; }
  async commit() {
    if (this.ops.length > MAX_BATCH) {
      throw new Error(`batch has ${this.ops.length} writes, Firestore allows ${MAX_BATCH}`);
    }
    for (const [op, ref, data, opts] of this.ops) {
      if (op === "set") this.store._set(ref.colPath, ref.id, data, opts);
      else {
        const col = this.store.collections.get(ref.colPath);
        if (col) col.delete(ref.id);
      }
    }
    this.ops = [];
  }
}

class MockFirestore {
  constructor() { this.collections = new Map(); this.writes = 0; }
  collection(path) { return new CollectionRef(this, path); }
  batch() { return new Batch(this); }
  async runTransaction(fn) {
    return fn({
      get: (ref) => ref.get(),
      set: (ref, data, opts) => this._set(ref.colPath, ref.id, data, opts),
    });
  }
  _set(colPath, id, data, opts) {
    assertWritable(data, `${colPath}/${id}`);
    if (!this.collections.has(colPath)) this.collections.set(colPath, new Map());
    const col = this.collections.get(colPath);
    const prev = col.get(id);
    col.set(id, (opts && opts.merge && prev) ? { ...prev, ...deepClone(data) } : deepClone(data));
    this.writes++;
  }
  /** Test helper: seed a document directly. */
  seed(colPath, id, data) { this._set(colPath, id, data); }
  /** Test helper: read a document directly. */
  peek(colPath, id) {
    const col = this.collections.get(colPath);
    return col ? col.get(id) : undefined;
  }
  /** Test helper: list document ids in a collection. */
  ids(colPath) {
    const col = this.collections.get(colPath);
    return col ? [...col.keys()] : [];
  }
}

module.exports = { MockFirestore, Timestamp, assertWritable };
