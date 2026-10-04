// ============================================================================
// dual-core.js — logika dual-write + failover (tanpa dependensi Firebase,
// jadi bisa dites di Node). Dipakai oleh db-dual.js.
//
// Aturan main:
//  • TULIS  : op dimasukkan ke antrian KEDUA server, lalu masing-masing
//             antrian di-flush berurutan. Sukses kalau minimal 1 server
//             menerima. Server yang gagal/timeout tetap menyimpan op di
//             antriannya (disimpan di localStorage) dan di-retry otomatis,
//             urutan tulis dijaga → data kedua server konvergen.
//  • BACA   : coba server yang paling "sehat" (antrian terpendek, bukan yang
//             baru gagal), timeout → lanjut ke server berikutnya.
//  • Semua op idempotent (multi-path update / set / remove dengan nilai
//    absolut), jadi aman diulang.
// ============================================================================

export function withTimeout(promise, ms, label = "operasi") {
  let t;
  const timeout = new Promise((_, reject) => {
    t = setTimeout(
      () => reject(new Error(`Timeout ${ms}ms (${label})`)),
      ms,
    );
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(t));
}

export function createDualStore({
  backends, // [{ name, get(path), update(obj), set(path, val), remove(path) }]
  storage = null, // objek mirip localStorage (opsional)
  storageKey = "dual_outbox_v1",
  timeoutMs = 8000,
  cooldownMs = 30000, // server yang baru gagal dilewati sebentar saat baca
  onStatus = () => {},
  now = () => Date.now(),
}) {
  const n = backends.length;
  const queues = backends.map(() => []);
  const flushing = backends.map(() => null);
  const state = backends.map(() => ({
    lastOk: 0,
    lastFail: 0,
    lastError: "",
  }));
  let opSeq = 0;

  // ---- persistensi antrian -------------------------------------------------
  try {
    const raw = storage && storage.getItem(storageKey);
    if (raw) {
      const saved = JSON.parse(raw);
      if (Array.isArray(saved) && saved.length === n) {
        saved.forEach((q, i) => queues[i].push(...q));
        opSeq = Math.max(
          0,
          ...queues.flat().map((o) => Number(String(o.id).split("-")[1]) || 0),
        );
      }
    }
  } catch (_) {
    /* antrian rusak → mulai kosong */
  }

  function persist() {
    try {
      storage && storage.setItem(storageKey, JSON.stringify(queues));
    } catch (_) {}
  }

  function status() {
    return backends.map((b, i) => ({
      name: b.name,
      pending: queues[i].length,
      lastOk: state[i].lastOk,
      lastFail: state[i].lastFail,
      lastError: state[i].lastError,
      healthy:
        state[i].lastFail === 0 || state[i].lastOk > state[i].lastFail,
    }));
  }
  const emit = () => {
    try {
      onStatus(status());
    } catch (_) {}
  };

  function markOk(i) {
    state[i].lastOk = now();
  }
  function markFail(i, err) {
    state[i].lastFail = now();
    state[i].lastError = String((err && err.message) || err);
  }

  function apply(i, op) {
    const b = backends[i];
    switch (op.type) {
      case "update":
        return b.update(op.updates);
      case "set":
        return b.set(op.path, op.value);
      case "remove":
        return b.remove(op.path);
      default:
        return Promise.reject(new Error("op tidak dikenal: " + op.type));
    }
  }

  // ---- flush antrian satu server ------------------------------------------
  function flush(i) {
    if (flushing[i]) return flushing[i];
    flushing[i] = (async () => {
      try {
        while (queues[i].length) {
          const op = queues[i][0];
          try {
            await withTimeout(apply(i, op), timeoutMs, backends[i].name);
          } catch (err) {
            markFail(i, err);
            return false; // berhenti di op pertama yang gagal → urutan aman
          }
          queues[i].shift();
          markOk(i);
          persist();
          emit();
        }
        return true;
      } finally {
        flushing[i] = null;
        emit();
      }
    })();
    return flushing[i];
  }

  const flushAll = () => Promise.all(backends.map((_, i) => flush(i)));

  // ---- tulis -------------------------------------------------------------
  async function write(opBody) {
    const id = `op-${++opSeq}`;
    queues.forEach((q) => q.push({ id, ...opBody }));
    persist();
    emit();

    await flushAll();

    const applied = queues.map((q) => !q.some((o) => o.id === id));
    if (!applied.some(Boolean)) {
      // Dua-duanya gagal → batalkan (jangan jadi "tulisan hantu" nanti).
      queues.forEach((q) => {
        const idx = q.findIndex((o) => o.id === id);
        if (idx >= 0) q.splice(idx, 1);
      });
      persist();
      emit();
      throw new Error(
        "Semua server tidak merespons. Data TIDAK tersimpan, coba lagi.",
      );
    }
    return applied; // mis. [true,false] = server 2 tertinggal (masuk antrian)
  }

  const update = (updates) => write({ type: "update", updates });
  const set = (path, value) => write({ type: "set", path, value });
  const remove = (path) => write({ type: "remove", path });

  // ---- baca --------------------------------------------------------------
  function readOrder() {
    const t = now();
    return backends
      .map((_, i) => i)
      .sort((a, b) => {
        const coolA = t - state[a].lastFail < cooldownMs && state[a].lastFail > state[a].lastOk ? 1 : 0;
        const coolB = t - state[b].lastFail < cooldownMs && state[b].lastFail > state[b].lastOk ? 1 : 0;
        if (coolA !== coolB) return coolA - coolB; // yang baru gagal belakangan
        if (queues[a].length !== queues[b].length)
          return queues[a].length - queues[b].length; // data paling lengkap dulu
        return a - b;
      });
  }

  async function read(path) {
    let lastErr;
    for (const i of readOrder()) {
      try {
        const v = await withTimeout(
          backends[i].get(path),
          timeoutMs,
          backends[i].name,
        );
        markOk(i);
        emit();
        return v === undefined ? null : v;
      } catch (err) {
        markFail(i, err);
        lastErr = err;
      }
    }
    emit();
    throw lastErr || new Error("Tidak ada server yang bisa dibaca.");
  }

  // ---- sinkron penuh (salin node dari server A ke B) -----------------------
  // Tiap node dicoba sendiri-sendiri; yang ditolak/gagal dilaporkan lengkap
  // (node, server, operasi) dan tidak menghentikan node lainnya.
  async function syncAll(from, to, nodes) {
    await flush(from);
    if (queues[from].length)
      throw new Error(
        `Server sumber (${backends[from].name}) masih punya antrian — belum bisa jadi sumber.`,
      );
    queues[to].length = 0; // antrian target sudah tidak relevan setelah ditimpa
    persist();
    const failed = [];
    let copied = 0;
    for (const node of nodes) {
      let step = `baca ${backends[from].name}`;
      try {
        const v = await withTimeout(
          backends[from].get(node),
          timeoutMs * 3,
          backends[from].name,
        );
        step = `tulis ${backends[to].name}`;
        if (v === null || v === undefined) {
          await withTimeout(backends[to].remove(node), timeoutMs * 3, backends[to].name);
        } else {
          await withTimeout(backends[to].set(node, v), timeoutMs * 3, backends[to].name);
        }
        copied++;
      } catch (err) {
        failed.push({ node, step, message: String((err && err.message) || err) });
      }
    }
    if (copied) markOk(to);
    emit();
    return { copied, failed };
  }

  return { update, set, remove, read, flush, flushAll, syncAll, status };
}
