// ============================================================================
// db-dual.js — sambungan Firebase untuk dual-write (Server 1 + Server 2).
// Isi SECONDARY_CONFIG dengan config project Firebase ke-2. Selama masih
// "ISI_..." app jalan normal hanya dengan Server 1.
// ============================================================================
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-app.js";
import {
  getDatabase, ref, get, child, update, set, remove,
} from "https://www.gstatic.com/firebasejs/10.4.0/firebase-database.js";
import {
  getAuth, signInWithCredential, signInWithPopup, GoogleAuthProvider, signOut,
} from "https://www.gstatic.com/firebasejs/10.4.0/firebase-auth.js";
import { createDualStore } from "./dual-core.js";

export const PRIMARY_CONFIG = {
  apiKey: "AIzaSyBRuCNCG24CAwdOJNPSTKXvtRWRL1qIPL8",
  authDomain: "banksampahtp2xetos.firebaseapp.com",
  databaseURL:
    "https://banksampahtp2xetos-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "banksampahtp2xetos",
  storageBucket: "banksampahtp2xetos.firebasestorage.app",
  messagingSenderId: "306920049631",
  appId: "1:306920049631:web:2f8e35b8051a8f6b01d26a",
};

// Server 2 (cadangan): project server-backup1-tp2
export const SECONDARY_CONFIG = {
  apiKey: "AIzaSyCh1D3uL3bmJGF-auByzG6hlx378rT_v5g",
  authDomain: "server-backup1-tp2.firebaseapp.com",
  databaseURL:
    "https://server-backup1-tp2-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "server-backup1-tp2",
  storageBucket: "server-backup1-tp2.firebasestorage.app",
  messagingSenderId: "212555470914",
  appId: "1:212555470914:web:a4a7fa9b0e662f7419f5db",
};

// admin_emails sengaja tidak ikut: node itu diatur lewat Firebase console
// (Rules biasanya melarang tulis dari aplikasi). Salin manual/import JSON.
const SYNC_NODES = [
  "email_to_uid", "kategori", "users",
  "transactions", "waste_out", "bank_withdrawals", "pengumuman",
];

const secondaryReady = !SECONDARY_CONFIG.apiKey.startsWith("ISI_");

export const app1 = initializeApp(PRIMARY_CONFIG);
export const db1 = getDatabase(app1);
export const auth1 = getAuth(app1);
const app2 = secondaryReady ? initializeApp(SECONDARY_CONFIG, "server2") : null;
const db2 = app2 ? getDatabase(app2) : null;
export const auth2 = app2 ? getAuth(app2) : null;

const fb = (name, db) => ({
  name,
  get: async (path) => {
    const s = await get(child(ref(db), path));
    return s.exists() ? s.val() : null;
  },
  update: (u) => update(ref(db), u),
  set: (p, v) => set(ref(db, p), v),
  remove: (p) => remove(ref(db, p)),
});

const backends = [fb("Server 1", db1)];
if (db2) backends.push(fb("Server 2", db2));

const panel = document.getElementById("syncPanel");
const syncBtn = document.getElementById("syncBtn");

function renderStatus(st) {
  if (!panel) return;
  panel.querySelectorAll(".sync-row").forEach((row) => {
    const s = st[Number(row.dataset.server)];
    const stateEl = row.querySelector(".sync-state");
    row.classList.remove("is-ok", "is-bad", "is-off");
    if (!s) {
      row.classList.add("is-off");
      stateEl.textContent = "Belum diatur";
      return;
    }
    row.classList.add(s.healthy ? "is-ok" : "is-bad");
    stateEl.textContent = s.pending
      ? `${s.pending} antri`
      : !s.healthy ? "Terputus" : s.lastOk ? "Tersambung" : "Siap";
    row.title = s.lastError || "";
  });
}

const store = createDualStore({
  backends,
  storage: window.localStorage,
  timeoutMs: 8000,
  onStatus: renderStatus,
});
renderStatus(store.status());

// retry antrian berkala + saat internet balik
setInterval(() => store.flushAll(), 15000);
window.addEventListener("online", () => store.flushAll());
store.flushAll();

syncBtn?.addEventListener("click", async () => {
  syncBtn.classList.add("is-busy");
  try {
  // Server 2 butuh login sendiri (token Server 1 ditolak project lain).
  // Harus dipanggil langsung dari klik supaya popup tidak diblokir.
  if (db2 && !auth2.currentUser) {
    try {
      const p = new GoogleAuthProvider();
      p.setCustomParameters({ prompt: "select_account" });
      await signInWithPopup(auth2, p);
    } catch (e) {
      return alert(
        "Login ke Server 2 gagal (" + (e.code || e.message) + ").\n" +
          "Izinkan popup, pakai akun admin yang sama, dan pastikan Google Sign-In aktif di project Server 2."
      );
    }
  }
  const st = store.status();
  if (st.some((s) => s.pending)) {
    if (confirm("Ada data yang belum masuk ke salah satu server. Kirim ulang sekarang?")) {
      await store.flushAll();
      renderStatus(store.status());
    }
    return;
  }
  if (!db2) return alert("Server 2 belum dikonfigurasi (lihat db-dual.js).");
  const pick = prompt(
    "SINKRON PENUH (menimpa server tujuan!)\n1 = salin Server 1 → Server 2\n2 = salin Server 2 → Server 1\nKosongkan untuk batal."
  );
  if (pick !== "1" && pick !== "2") return;
  const [from, to] = pick === "1" ? [0, 1] : [1, 0];
  try {
    const { copied, failed } = await store.syncAll(from, to, SYNC_NODES);
    if (!failed.length) {
      alert(`Selesai: ${copied} node disalin.`);
    } else {
      alert(
        `Selesai sebagian: ${copied} node berhasil, ${failed.length} gagal.\n\n` +
          failed.map((f) => `• ${f.node} — ${f.step}: ${f.message}`).join("\n") +
          "\n\n'Permission denied' di 'tulis Server 2' = Rules Server 2 belum mengizinkan " +
          "(atau login Server 2 belum berhasil). Di 'baca Server 1' = Rules Server 1 melarang baca node itu."
      );
    }
  } catch (e) {
    alert("Sinkron gagal: " + e.message);
  }
  } finally {
    syncBtn.classList.remove("is-busy");
  }
});

// ---- API untuk app.js ------------------------------------------------------
export const dualUpdate = (updates) => store.update(updates);
export const dualSet = (path, value) => store.set(path, value);
export const dualRemove = (path) => store.remove(path);
export async function dualGet(path) {
  const v = await store.read(path);
  return { exists: () => v !== null && v !== undefined, val: () => v };
}

// Login admin di Server 2 memakai kredensial Google yang sama (best-effort).
export async function signInSecondary(popupResult) {
  if (!auth2) return;
  try {
    const cred = GoogleAuthProvider.credentialFromResult(popupResult);
    await signInWithCredential(auth2, cred);
  } catch (e) {
    console.warn("Login Server 2 gagal (tulis ke S2 akan ditolak kalau rules butuh auth):", e);
  }
}
export async function signOutSecondary() {
  if (auth2) try { await signOut(auth2); } catch (_) {}
}
