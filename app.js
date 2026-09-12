// ============================================================================
// Resik For Schooling — Admin Dashboard
// Firebase Realtime Database (REST via modular SDK) + rendering logic
// ============================================================================

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.4.0/firebase-app.js";

import {
  getDatabase,
  ref,
  get,
  child,
  update,
  push,
  set,
  remove,
} from "https://www.gstatic.com/firebasejs/10.4.0/firebase-database.js";

import {
  getAuth,
  onAuthStateChanged,
  GoogleAuthProvider,
  signInWithPopup,
  signOut,
} from "https://www.gstatic.com/firebasejs/10.4.0/firebase-auth.js";

const firebaseConfig = {
  apiKey: "AIzaSyBRuCNCG24CAwdOJNPSTKXvtRWRL1qIPL8",
  authDomain: "banksampahtp2xetos.firebaseapp.com",
  databaseURL:
    "https://banksampahtp2xetos-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "banksampahtp2xetos",
  storageBucket: "banksampahtp2xetos.firebasestorage.app",
  messagingSenderId: "306920049631",
  appId: "1:306920049631:web:2f8e35b8051a8f6b01d26a",
};

const app = initializeApp(firebaseConfig);
const db = getDatabase(app);
const auth = getAuth(app);

// ============================================================================
// Auth — login admin pakai Google Sign-In, dibatasi ke email yang terdaftar
// di node RTDB `admin_emails` (diatur langsung dari Firebase console / RTDB,
// tanpa perlu ubah kode untuk nambah/hapus admin).
// ============================================================================

// Kunci RTDB tidak boleh mengandung '.', jadi '.' diganti ',' saat dipakai
// sebagai key. Rules di server melakukan replace yang sama.
function sanitizeEmailKey(email) {
  return email.trim().toLowerCase().replace(/\./g, ",");
}

const authShell = document.getElementById("authShell");
const appShell = document.getElementById("appShell");
const authGoogleBtn = document.getElementById("authGoogleBtn");
const authNote = document.getElementById("authNote");
const authCheckingBox = document.getElementById("authCheckingBox");

function showAuthScreen() {
  authShell.classList.remove("hidden");
  appShell.classList.add("hidden");
}

function showAppScreen() {
  authShell.classList.add("hidden");
  appShell.classList.remove("hidden");
}

function setAuthNote(msg) {
  authNote.textContent = msg || "";
}

async function isEmailAllowedAsAdmin(email) {
  const key = sanitizeEmailKey(email);
  const snap = await get(child(ref(db), `admin_emails/${key}`));
  return snap.exists() && snap.val() === true;
}

authGoogleBtn.addEventListener("click", async () => {
  authGoogleBtn.disabled = true;
  setAuthNote("");
  try {
    const provider = new GoogleAuthProvider();
    await signInWithPopup(auth, provider);
    // Hasilnya ditangani di onAuthStateChanged di bawah.
  } catch (err) {
    console.error(err);
    if (err.code !== "auth/popup-closed-by-user") {
      setAuthNote(`Gagal login Google (${err.code || "unknown"}). Cek Google Sign-In/Firebase Auth.`);
    }
  } finally {
    authGoogleBtn.disabled = false;
  }
});

// --- Gerbang utama: pantau status login & cek allowlist ---
onAuthStateChanged(auth, async (user) => {
  if (!user) {
    showAuthScreen();
    authCheckingBox.classList.add("hidden");
    authGoogleBtn.classList.remove("hidden");
    return;
  }

  authGoogleBtn.classList.add("hidden");
  authCheckingBox.classList.remove("hidden");

  const allowed = await isEmailAllowedAsAdmin(user.email || "");
  if (!allowed) {
    await signOut(auth);
    showAuthScreen();
    authCheckingBox.classList.add("hidden");
    authGoogleBtn.classList.remove("hidden");
    setAuthNote(
      `Akun ${user.email} belum diizinkan mengakses admin. Hubungi pengelola sistem.`,
    );
    return;
  }

  showAppScreen();
  loadDashboard().catch((err) => {
    console.error(err);
    const msg = `Gagal memuat data (${err.code || err.message || "unknown"}). Cek koneksi internet atau Firebase Realtime Database Rules.`;

    document.getElementById("lastTxList").innerHTML =
      `<p class="empty-note">${msg}</p>`;

    // Tampilkan juga di area statistik utama supaya jelas kelihatan
    // dashboard-nya bukan "kosong" tapi memang gagal ambil data.
    ["statTotalNasabah", "statTotalKategori", "statTxHariIni"].forEach(
      (id) => {
        const el = document.getElementById(id);
        if (el) el.textContent = "!";
      },
    );

    document.getElementById("donutLegend").innerHTML =
      `<p class="empty-note">${msg}</p>`;
  });
});

// ============================================================================
// Kategori
// ============================================================================

const DEFAULT_KATEGORI = [
  { nama: "Plastik", harga: 3000 },
  { nama: "Kertas", harga: 2000 },
  { nama: "Logam", harga: 5000 },
];

const DONUT_COLORS = [
  "#1E7A4C",
  "#12A883",
  "#E3A23B",
  "#3B5B9B",
  "#D65D4E",
  "#8B978F",
];

const KATEGORI_PILL_COLORS = [
  "#1E7A4C",
  "#B9791F",
  "#3B5B9B",
  "#0A7A6E",
  "#A14A9C",
  "#B04A3B",
];

function warnaKategori(nama) {
  const idx = cache.kategori.findIndex((k) => k.nama === nama);

  return KATEGORI_PILL_COLORS[
    (idx < 0 ? 0 : idx) % KATEGORI_PILL_COLORS.length
  ];
}

function hargaKategoriOf(nama) {
  return cache.kategori.find((k) => k.nama === nama)?.harga || 0;
}

// ============================================================================
// Helpers
// ============================================================================

const formatRp = (angka) =>
  new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: "IDR",
    minimumFractionDigits: 0,
  }).format(angka || 0);

const formatKg = (kg) =>
  `${(kg || 0).toLocaleString("id-ID", {
    maximumFractionDigits: 1,
  })} kg`;

function isoDate(d) {
  return d.toISOString().slice(0, 10);
}

// Escape karakter HTML spesial supaya string dari data (nama kategori,
// nama nasabah, dll.) aman disisipkan ke dalam template innerHTML.
function escapeHtml(str) {
  return String(str ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[ch]);
}

function last30Days() {
  const days = [];

  for (let i = 29; i >= 0; i -= 1) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    days.push(d);
  }

  return days;
}


// ============================================================================
// Data layer
// ============================================================================

async function fetchAllUsers() {
  try {
    const snap = await get(child(ref(db), "users"));
    return snap.exists() ? snap.val() : {};
  } catch (err) {
    console.error("Gagal membaca node 'users':", err);
    return {};
  }
}

async function fetchAllTransactions() {
  try {
    const snap = await get(child(ref(db), "transactions"));
    return snap.exists() ? snap.val() : {};
  } catch (err) {
    console.error("Gagal membaca node 'transactions':", err);
    return {};
  }
}

async function fetchAllWasteOut() {
  try {
    const snap = await get(child(ref(db), "waste_out"));
    return snap.exists() ? snap.val() : {};
  } catch (err) {
    // Node waste_out bisa belum punya permission di Firebase Rules.
    // Jangan biarkan kegagalan node opsional ini membuat seluruh dashboard kosong.
    console.warn("Pengeluaran sampah belum bisa dibaca:", err);
    return {};
  }
}

async function fetchKategori() {
  try {
    const snap = await get(child(ref(db), "kategori"));

    if (!snap.exists()) {
      const seeded = {};

      DEFAULT_KATEGORI.forEach((k) => {
        const newKey = push(ref(db, "kategori")).key;

        if (newKey) {
          seeded[newKey] = k;
        }
      });

      try {
        await update(
          ref(db),
          Object.fromEntries(
            Object.entries(seeded).map(([key, val]) => [
              `kategori/${key}`,
              val,
            ]),
          ),
        );
      } catch (err) {
        // Gagal menulis default kategori (mis. rules cuma izinkan read) —
        // tetap tampilkan kategori default di dashboard walau belum tersimpan.
        console.warn("Gagal menyimpan kategori default ke Firebase:", err);
      }

      return Object.entries(seeded).map(([key, val]) => ({
        key,
        ...val,
      }));
    }

    return Object.entries(snap.val()).map(([key, val]) => ({
      key,
      ...val,
    }));
  } catch (err) {
    // Node kategori gagal dibaca (mis. permission-denied di Firebase Rules).
    // Jangan biarkan ini membuat seluruh dashboard gagal render — pakai
    // kategori default sebagai fallback supaya UI tetap jalan.
    console.error("Gagal membaca node 'kategori':", err);
    return DEFAULT_KATEGORI.map((k, i) => ({ key: `local-${i}`, ...k }));
  }
}

// ============================================================================
// Flatten transaksi
// ============================================================================

function flattenTransactions(users, transactionsByUser, wasteOut = {}) {
  const flat = [];

  Object.entries(transactionsByUser || {}).forEach(([uid, txMap]) => {
    Object.entries(txMap || {}).forEach(([txId, tx]) => {
      flat.push({
        ...tx,
        uid,
        txId,
        nama: users[uid]?.nama || "Nasabah",
        kelas: users[uid]?.kelas || "-",
      });
    });
  });

  Object.entries(wasteOut || {}).forEach(([txId, tx]) => {
    flat.push({
      ...tx,
      uid: null,
      txId,
      isWasteOut: true,
      nama: tx.pengepul || tx.penerima || "Pengeluaran Sampah",
      kelas: "-",
    });
  });

  flat.sort(
    (a, b) => new Date(b.tanggal) - new Date(a.tanggal),
  );

  return flat;
}

// ============================================================================
// Helpers transaksi setor multi-kategori
// ============================================================================

function getSetorItems(tx) {
  if (tx?.tipe !== "Setor") return [];
  if (Array.isArray(tx.items) && tx.items.length) return tx.items;
  if (tx?.kategori) {
    return [{
      kategori: tx.kategori,
      berat_kg: Number(tx.berat_kg) || 0,
      harga_per_kg: Number(tx.harga_per_kg) || hargaKategoriOf(tx.kategori),
      total_rp: Number(tx.total_rp) || 0,
    }];
  }
  return [];
}

function totalBeratTx(tx) {
  return getSetorItems(tx).reduce((sum, item) => sum + (Number(item.berat_kg) || 0), 0);
}

function totalNilaiItems(items) {
  return items.reduce((sum, item) => sum + ((Number(item.berat_kg) || 0) * (Number(item.harga_per_kg) || hargaKategoriOf(item.kategori))), 0);
}

function getWasteOutItems(tx) {
  if (!tx?.isWasteOut && tx?.tipe !== "Pengeluaran Sampah") return [];
  if (Array.isArray(tx.items) && tx.items.length) return tx.items;
  if (tx?.kategori) {
    return [{ kategori: tx.kategori, berat_kg: Number(tx.berat_kg) || 0 }];
  }
  return [];
}

function totalBeratWasteOut(tx) {
  return getWasteOutItems(tx).reduce((sum, item) => sum + (Number(item.berat_kg) || 0), 0);
}

// ============================================================================
// Rendering: donut chart
// ============================================================================

function renderSetoranDonut(flat) {
  const totals = {};
  const dayKeys = new Set(last30Days().map(isoDate));

  flat.filter((t) => dayKeys.has(t.tanggal?.slice(0, 10)))
    .filter((t) => t.tipe === "Setor")
    .forEach((t) => {
      getSetorItems(t).forEach((item) => {
        const kategori = item.kategori || "Lainnya";
        const berat = Number(item.berat_kg) || 0;
        totals[kategori] = (totals[kategori] || 0) + berat;
      });
    });

  const entries = Object.entries(totals)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6);

  // fraction tiap slice tetap dihitung dari total kg (bukan persentase
  // hardcoded) — cuma label yang ditampilkan diganti ke kg, bukan %.
  const totalKg =
    entries.reduce((sum, [, v]) => sum + v, 0) || 1;

  const size = 150;
  const stroke = 20;
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;

  let offset = 0;

  const segments = entries
    .map(([, value], i) => {
      const fraction = value / totalKg;
      const dash = fraction * circumference;

      const circle = `
        <circle
          cx="${size / 2}"
          cy="${size / 2}"
          r="${radius}"
          fill="none"
          stroke="${DONUT_COLORS[i % DONUT_COLORS.length]}"
          stroke-width="${stroke}"
          stroke-dasharray="${dash} ${circumference - dash}"
          stroke-dashoffset="${-offset}"
          stroke-linecap="butt"
          transform="rotate(-90 ${size / 2} ${size / 2})"
        />
      `;

      offset += dash;

      return circle;
    })
    .join("");

  document.getElementById("donutFigure").innerHTML = `
    <svg
      width="${size}"
      height="${size}"
      viewBox="0 0 ${size} ${size}"
    >
      ${segments}
    </svg>

    <div class="donut-center">
      <strong>${formatKg(totalKg)}</strong>
      <span>Total Setoran</span>
    </div>
  `;

  document.getElementById("donutLegend").innerHTML =
    entries
      .map(
        ([kategori, value], i) => `
          <div class="legend-item">
            <span
              class="legend-dot"
              style="background:${DONUT_COLORS[i % DONUT_COLORS.length]}"
            ></span>

            <span>${kategori}</span>

            <span>${formatKg(value)}</span>
          </div>
        `,
      )
      .join("") ||
    '<p class="empty-note">Belum ada data setoran.</p>';
}

// ============================================================================
// Rendering: line chart
// ============================================================================

function renderAccumulationChart(days, masukRp, tarikRp) {
  const w = 640;
  const h = 300;
  const padL = 52;
  const padR = 16;
  const padT = 22;
  const padB = 30;
  const plotW = w - padL - padR;
  const plotH = h - padT - padB;

  const rawMax = Math.max(1, ...masukRp, ...tarikRp);
  const maxVal = Math.ceil((rawMax * 1.15) / 10000) * 10000 || 10000;
  const stepX = plotW / (days.length - 1 || 1);

  const makePoints = (values) => values.map((v, i) => ({
    x: padL + i * stepX,
    y: padT + plotH - (v / maxVal) * plotH,
    v,
  }));

  const masukPoints = makePoints(masukRp);
  const tarikPoints = makePoints(tarikRp);

  const gridSteps = [0, 0.25, 0.5, 0.75, 1];
  const gridLines = gridSteps.map((f) => {
    const y = padT + plotH * f;
    const label = formatRp(maxVal * (1 - f));
    return `
      <line x1="${padL}" y1="${y.toFixed(2)}" x2="${w - padR}" y2="${y.toFixed(2)}"
        stroke="#D8E1DC" stroke-width="1" />
      <text x="0" y="${(y + 3.5).toFixed(2)}" font-size="9.5" fill="#7C8982">${label}</text>
    `;
  }).join("");

  const labelEvery = Math.ceil(days.length / 6);
  const dayLabels = days.map((d, i) => {
    if (i % labelEvery !== 0 && i !== days.length - 1) return "";
    const x = padL + i * stepX;
    return `<text x="${x.toFixed(2)}" y="${h - 8}" text-anchor="middle" font-size="9.5" fill="#68766F">${d.getDate()}/${d.getMonth() + 1}</text>`;
  }).join("");

  const linePath = (points) => points.map((p, i) =>
    `${i === 0 ? "M" : "L"} ${p.x.toFixed(2)},${p.y.toFixed(2)}`
  ).join(" ");

  const makeDots = (points, color) => points.map((p, i) => {
    const last = i === points.length - 1;
    return `<circle cx="${p.x.toFixed(2)}" cy="${p.y.toFixed(2)}" r="${last ? 4.5 : 2.7}"
      fill="${last ? color : "#FFFFFF"}" stroke="${color}" stroke-width="${last ? 2.5 : 1.5}">
      <title>${days[i].getDate()}/${days[i].getMonth() + 1}: ${formatRp(p.v)}</title>
    </circle>`;
  }).join("");

  const masukColor = "#1E7A4C";
  const tarikColor = "#12A883";

  document.getElementById("lineChart").innerHTML = `
    ${gridLines}

    <path d="${linePath(masukPoints)}" fill="none" stroke="${masukColor}"
      stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" />
    <path d="${linePath(tarikPoints)}" fill="none" stroke="${tarikColor}"
      stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" />

    ${makeDots(masukPoints, masukColor)}
    ${makeDots(tarikPoints, tarikColor)}
    ${dayLabels}
  `;
}

function renderMiniBars(values) {
  const max = Math.max(1, ...values);

  document.getElementById("darkMiniBars").innerHTML =
    values
      .map(
        (v) =>
          `<i style="height:${Math.max(
            4,
            (v / max) * 38,
          )}px"></i>`,
      )
      .join("");
}

// ============================================================================
// Transaction rows
// ============================================================================

function txRowHtml(tx) {
  const isSetor = tx.tipe === "Setor";
  const isWasteOut = tx.isWasteOut || tx.tipe === "Pengeluaran Sampah";

  const setorItems = isSetor ? getSetorItems(tx) : [];
  const totalKg = isSetor ? totalBeratTx(tx) : isWasteOut ? totalBeratWasteOut(tx) : 0;
  const title = isSetor
    ? `Setor ${setorItems.length} kategori · ${totalKg.toLocaleString("id-ID", { maximumFractionDigits: 1 })} Kg`
    : isWasteOut
      ? `Pengeluaran Sampah · ${totalKg.toLocaleString("id-ID", { maximumFractionDigits: 1 })} Kg`
      : "Penarikan Saldo";

  const date = tx.tanggal
    ? new Date(tx.tanggal)
    : null;

  const dateStr = date
    ? `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`
    : "-";

  const icon = isSetor
    ? `
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M12 5v14M5 12l7 7 7-7"/>
      </svg>
    `
    : `
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M12 19V5M5 12l7-7 7 7"/>
      </svg>
    `;

  return `
    <div class="tx-row">
      <div class="tx-icon ${isSetor ? "is-in" : "is-out"}">
        ${icon}
      </div>

      <div class="tx-body">
        <p class="tx-title">${title}</p>

        <p class="tx-sub">
          ${tx.nama} · ${dateStr}
        </p>
      </div>

      <span class="tx-amount ${isSetor ? "is-in" : "is-out"}">
        ${isSetor ? "+" : isWasteOut ? "" : "-"} ${isWasteOut ? formatKg(totalKg) : formatRp(tx.total_rp)}
      </span>
    </div>
  `;
}

// ============================================================================
// Cache
// ============================================================================

let cache = {
  users: {},
  transactions: {},
  flat: [],
  kategori: [],
};

// ============================================================================
// Dashboard
// ============================================================================

async function loadDashboard() {
  const [
    users,
    transactionsByUser,
    kategori,
    wasteOut,
  ] = await Promise.all([
    fetchAllUsers(),
    fetchAllTransactions(),
    fetchKategori(),
    fetchAllWasteOut(),
  ]);

  const flat = flattenTransactions(
    users,
    transactionsByUser,
    wasteOut,
  );

  cache = {
    users,
    transactions: transactionsByUser,
    wasteOut,
    flat,
    kategori,
  };

  populateKategoriSelect();
  initMonthlyReport();

  const days = last30Days();
  const dayKeys = days.map(isoDate);
  const todayKey = isoDate(new Date());

  const days30 = last30Days();
  const dayKeys30 = days30.map(isoDate);

  // Arus uang 30 hari: dua garis — uang masuk dari setor dan uang keluar dari tarik.
  const masukRp30 = dayKeys30.map((key) =>
    flat
      .filter((t) => t.tanggal?.slice(0, 10) === key && t.tipe === "Setor")
      .reduce((sum, t) => sum + (Number(t.total_rp) || 0), 0),
  );

  const tarikRp30 = dayKeys30.map((key) =>
    flat
      .filter((t) => t.tanggal?.slice(0, 10) === key && t.tipe === "Tarik")
      .reduce((sum, t) => sum + (Number(t.total_rp) || 0), 0),
  );

  const setorCounts = dayKeys.map(
    (key) =>
      flat.filter(
        (t) =>
          t.tanggal?.slice(0, 10) === key &&
          t.tipe === "Setor",
      ).length,
  );

  const txHariIni = flat.filter(
    (t) =>
      t.tanggal?.slice(0, 10) === todayKey,
  ).length;

  const last30 = flat.filter((t) =>
    dayKeys.includes(
      t.tanggal?.slice(0, 10),
    ),
  );

  const wasteInKg = last30
    .filter((t) => t.tipe === "Setor")
    .reduce(
      (sum, t) =>
        sum +
        totalBeratTx(t),
      0,
    );

  const saldoDitarik = last30
    .filter((t) => t.tipe === "Tarik")
    .reduce(
      (sum, t) =>
        sum + (t.total_rp || 0),
      0,
    );

  const saldoAktifTotal =
    Object.values(users).reduce(
      (sum, u) =>
        sum +
        (u.saldo_terakhir || 0),
      0,
    );

  // Stat row

  document.getElementById(
    "statTotalNasabah",
  ).textContent =
    Object.keys(users).length;

  document.getElementById(
    "statTotalKategori",
  ).textContent =
    cache.kategori.length;

  document.getElementById(
    "statTxHariIni",
  ).textContent =
    txHariIni;

  // Donut

  renderSetoranDonut(flat);

  // Dark panel

  document.getElementById(
    "darkTotalKategori",
  ).textContent =
    cache.kategori.length;

  document.getElementById(
    "darkWasteIn",
  ).textContent =
    formatKg(wasteInKg);

  document.getElementById(
    "darkWasteOut",
  ).textContent =
    formatRp(saldoDitarik);

  renderMiniBars(setorCounts);

  // Line chart

  renderAccumulationChart(
    days30,
    masukRp30,
    tarikRp30,
  );

  // Balance

  document.getElementById(
    "balanceValue",
  ).textContent =
    formatRp(saldoAktifTotal);

  // Last transactions

  const lastTx = flat.slice(0, 6);

  document.getElementById(
    "lastTxList",
  ).innerHTML =
    lastTx.map(txRowHtml).join("") ||
    '<p class="empty-note">Belum ada transaksi.</p>';

  return {
    users,
    flat,
    days,
    dayKeys,
    wasteInKg,
    saldoDitarik,
    saldoAktifTotal,
  };
}

// ============================================================================
// Nasabah
// ============================================================================

function renderNasabahTable(users) {
  const rows = Object.entries(users);

  document.getElementById(
    "tableNasabah",
  ).innerHTML =
    rows
      .map(
        ([uid, u]) => `
          <tr>
            <td>${u.nama || "-"}</td>

            <td>${u.tipe || "Siswa"}</td>

            <td>${u.kelas || "-"}</td>

            <td style="font-size:12px">
              ${u.email || '<span class="empty-note" style="margin:0">belum diisi</span>'}
            </td>

            <td
              style="
                font-family:var(--font-mono);
                font-size:11.5px;
                color:var(--color-muted)
              "
            >
              ${uid}
            </td>

            <td style="font-family:var(--font-mono)">
              ${formatRp(u.saldo_terakhir || 0)}
            </td>
            <td class="table-actions">
              <button class="link-btn" data-edit-user="${uid}">Edit</button>
              <button class="link-btn is-danger" data-delete-user="${uid}">Hapus</button>
            </td>
          </tr>
        `,
      )
      .join("") ||
    `
      <tr class="loading-row">
        <td colspan="7">
          Belum ada nasabah terdaftar.
        </td>
      </tr>
    `;
}

// ============================================================================
// Tambah nasabah
// ============================================================================

const KELAS_LABEL = {
  Siswa: {
    label: "Kelas",
    placeholder: "Misal: 7A",
  },

  "Guru & Staff": {
    label: "Unit / Jabatan",
    placeholder: "Misal: Tata Usaha",
  },

  Umum: {
    label: "Alamat / Keterangan",
    placeholder: "Misal: Warga sekitar",
  },
};

const nasabahTipeSelect =
  document.getElementById(
    "nasabahTipe",
  );

const nasabahKelasLabel =
  document.getElementById(
    "nasabahKelasLabel",
  );

const nasabahKelasInput =
  document.getElementById(
    "nasabahKelas",
  );

function syncNasabahTipeField() {
  const cfg =
    KELAS_LABEL[
      nasabahTipeSelect.value
    ] || KELAS_LABEL.Siswa;

  nasabahKelasLabel.textContent =
    cfg.label;

  nasabahKelasInput.placeholder =
    cfg.placeholder;
}

nasabahTipeSelect.addEventListener(
  "change",
  syncNasabahTipeField,
);

syncNasabahTipeField();

document
  .getElementById("btnTambahNasabah")
  .addEventListener(
    "click",
    async () => {
      const nama =
        document
          .getElementById(
            "nasabahNama",
          )
          .value.trim();

      const tipe =
        nasabahTipeSelect.value;

      const kelas =
        nasabahKelasInput.value.trim();

      const email = document
        .getElementById("nasabahEmail")
        .value.trim()
        .toLowerCase();

      const errorEl =
        document.getElementById(
          "nasabahAddError",
        );

      errorEl.textContent = "";

      errorEl.classList.remove(
        "field-error",
      );

      if (!nama) {
        errorEl.textContent =
          "Nama nasabah wajib diisi.";

        errorEl.classList.add(
          "field-error",
        );

        return;
      }

      // Kalau email diisi, pastikan belum dipakai nasabah lain (satu
      // akun Google cuma boleh nge-link ke satu kartu nasabah).
      if (email) {
        const emailKey = sanitizeEmailKey(email);
        const existing = await get(
          child(ref(db), `email_to_uid/${emailKey}`),
        );
        if (existing.exists()) {
          errorEl.textContent =
            "Email ini sudah dipakai nasabah lain.";
          errorEl.classList.add("field-error");
          return;
        }
      }

      const newUid =
        push(ref(db, "users")).key;

      if (!newUid) {
        errorEl.textContent =
          "Gagal membuat UID nasabah.";

        errorEl.classList.add(
          "field-error",
        );

        return;
      }

      const updates = {};
      updates[`users/${newUid}`] = {
        nama,
        tipe,
        kelas: kelas || "-",
        email: email || null,
        saldo_terakhir: 0,
      };
      if (email) {
        updates[`email_to_uid/${sanitizeEmailKey(email)}`] = newUid;
      }

      await update(ref(db), updates);

      // Tampilkan QR

      document
        .getElementById(
          "nasabahResultEmpty",
        )
        .classList.add("hidden");

      const card =
        document.getElementById(
          "nasabahResultCard",
        );

      card.classList.remove(
        "hidden",
      );

      document.getElementById(
        "nasabahResultNama",
      ).textContent = nama;

      document.getElementById(
        "nasabahResultUid",
      ).textContent = newUid;

      const qrBox =
        document.getElementById(
          "nasabahResultQr",
        );

      qrBox.innerHTML = "";

      // eslint-disable-next-line no-undef
      new QRCode(qrBox, {
        text: newUid,
        width: 150,
        height: 150,
        colorDark: "#10241B",
        colorLight: "#ffffff",
      });

      document.getElementById(
        "nasabahNama",
      ).value = "";

      nasabahKelasInput.value =
        "";

      await loadDashboard();

      renderNasabahTable(
        cache.users,
      );
    },
  );

// ============================================================================
// Edit / hapus nasabah
// ============================================================================

document.getElementById("tableNasabah")?.addEventListener("click", async (e) => {
  const editBtn = e.target.closest("[data-edit-user]");
  const deleteBtn = e.target.closest("[data-delete-user]");
  const uid = editBtn?.dataset.editUser || deleteBtn?.dataset.deleteUser;
  if (!uid || !cache.users[uid]) return;
  const user = cache.users[uid];

  if (editBtn) {
    const nama = prompt("Nama nasabah:", user.nama || "");
    if (nama === null) return;
    const tipe = prompt("Tipe (Siswa / Guru & Staff / Umum):", user.tipe || "Siswa");
    if (tipe === null) return;
    const kelas = prompt("Kelas / Unit / Keterangan:", user.kelas || "-");
    if (kelas === null) return;
    const email = prompt("Email Google (kosongkan jika tidak ada):", user.email || "");
    if (email === null) return;
    if (!nama.trim()) { alert("Nama wajib diisi."); return; }
    const cleanEmail = email.trim().toLowerCase();
    if (cleanEmail && cleanEmail !== (user.email || "").toLowerCase()) {
      const exists = await get(child(ref(db), `email_to_uid/${sanitizeEmailKey(cleanEmail)}`));
      if (exists.exists() && exists.val() !== uid) { alert("Email sudah dipakai nasabah lain."); return; }
    }
    const updates = {};
    updates[`users/${uid}/nama`] = nama.trim();
    updates[`users/${uid}/tipe`] = tipe.trim() || "Siswa";
    updates[`users/${uid}/kelas`] = kelas.trim() || "-";
    updates[`users/${uid}/email`] = cleanEmail || null;
    if (user.email && user.email.toLowerCase() !== cleanEmail) {
      updates[`email_to_uid/${sanitizeEmailKey(user.email)}`] = null;
    }
    if (cleanEmail) updates[`email_to_uid/${sanitizeEmailKey(cleanEmail)}`] = uid;
    try {
      await update(ref(db), updates);
      await loadDashboard();
      renderNasabahTable(cache.users);
    } catch (err) { console.error(err); alert("Gagal mengedit nasabah."); }
    return;
  }

  if (deleteBtn) {
    if (!confirm(`Hapus nasabah "${user.nama}" beserta seluruh riwayat transaksinya?`)) return;
    const updates = { [`users/${uid}`]: null, [`transactions/${uid}`]: null };
    if (user.email) updates[`email_to_uid/${sanitizeEmailKey(user.email)}`] = null;
    try {
      await update(ref(db), updates);
      await loadDashboard();
      renderNasabahTable(cache.users);
    } catch (err) { console.error(err); alert("Gagal menghapus nasabah."); }
  }
});

// ============================================================================
// Dropdown kategori transaksi
// ============================================================================

function populateKategoriSelect() {
  if (typeof setorItemsEl !== "undefined" && setorItemsEl) {
    resetSetorItems();
  }
  if (typeof wasteOutItemsEl !== "undefined" && wasteOutItemsEl) {
    resetWasteOutItems();
    kalkulasiWasteOut();
  }
}

// ============================================================================
// Kategori view
// ============================================================================

function renderKategoriTable(flat) {
  const dayKeys =
    last30Days().map(isoDate);

  const last30 = flat.filter(
    (t) =>
      dayKeys.includes(
        t.tanggal?.slice(0, 10),
      ) &&
      t.tipe === "Setor",
  );

  document.getElementById(
    "tableKategori",
  ).innerHTML =
    cache.kategori
      .map((k) => {
        const totalKg = last30.reduce((sum, t) => {
          return sum + getSetorItems(t)
            .filter((item) => item.kategori === k.nama)
            .reduce((sub, item) => sub + (Number(item.berat_kg) || 0), 0);
        }, 0);

        const warna =
          warnaKategori(k.nama);

        return `
          <tr>
            <td>
              <input type="text" class="kategori-nama-input text-input" data-key="${k.key}" value="${k.nama}" />
            </td>
            <td>
              <div class="price-edit-row">
                <input type="number" class="kategori-harga-input" data-key="${k.key}" value="${k.harga}" />
                <button class="link-btn" data-save-kategori="${k.key}">Simpan</button>
              </div>
            </td>

            <td>
              ${formatKg(totalKg)}
            </td>

            <td class="table-actions">
              <button class="link-btn is-danger" data-delete-kategori="${k.key}">Hapus</button>
            </td>
          </tr>
        `;
      })
      .join("") ||
    `
      <tr class="loading-row">
        <td colspan="4">
          Belum ada kategori.
          Tambah dulu di atas.
        </td>
      </tr>
    `;
}

async function tambahKategori(
  nama,
  harga,
) {
  const newKey =
    push(ref(db, "kategori")).key;

  if (!newKey) {
    throw new Error(
      "Gagal membuat key kategori.",
    );
  }

  await set(
    ref(db, `kategori/${newKey}`),
    {
      nama,
      harga,
    },
  );
}

async function simpanKategori(key, nama, harga) {
  const old = cache.kategori.find((k) => k.key === key);
  const updates = {
    [`kategori/${key}/nama`]: nama,
    [`kategori/${key}/harga`]: harga,
  };

  // Saat nama kategori diubah, ikut migrasikan nama kategori pada transaksi
  // lama supaya riwayat dan analitik tetap nyambung ke kategori yang sama.
  if (old && old.nama !== nama) {
    cache.flat
      .filter((tx) => tx.tipe === "Setor")
      .forEach((tx) => {
        if (Array.isArray(tx.items)) {
          tx.items.forEach((item, index) => {
            if (item.kategori === old.nama) {
              updates[`transactions/${tx.uid}/${tx.txId}/items/${index}/kategori`] = nama;
            }
          });
        } else if (tx.kategori === old.nama) {
          updates[`transactions/${tx.uid}/${tx.txId}/kategori`] = nama;
        }
      });
  }

  await update(ref(db), updates);
}

async function hapusKategori(key) {
  await remove(ref(db, `kategori/${key}`));
}

document
  .getElementById("btnTambahKategori")
  .addEventListener(
    "click",
    async () => {
      const nama =
        document
          .getElementById(
            "kategoriNamaBaru",
          )
          .value.trim();

      const harga =
        parseFloat(
          document.getElementById(
            "kategoriHargaBaru",
          ).value,
        );

      const errorEl =
        document.getElementById(
          "kategoriAddError",
        );

      errorEl.textContent = "";

      errorEl.classList.remove(
        "field-error",
      );

      if (
        !nama ||
        !Number.isFinite(harga) ||
        harga <= 0
      ) {
        errorEl.textContent =
          "Isi nama kategori dan harga per kg yang valid.";

        errorEl.classList.add(
          "field-error",
        );

        return;
      }

      if (
        cache.kategori.some(
          (k) =>
            k.nama.toLowerCase() ===
            nama.toLowerCase(),
        )
      ) {
        errorEl.textContent =
          "Kategori dengan nama itu sudah ada.";

        errorEl.classList.add(
          "field-error",
        );

        return;
      }

      try {
        await tambahKategori(
          nama,
          harga,
        );

        document.getElementById(
          "kategoriNamaBaru",
        ).value = "";

        document.getElementById(
          "kategoriHargaBaru",
        ).value = "";

        await loadDashboard();

        renderKategoriTable(
          cache.flat,
        );
      } catch (err) {
        console.error(err);

        errorEl.textContent =
          "Gagal menambahkan kategori. Cek koneksi atau rules Firebase.";

        errorEl.classList.add(
          "field-error",
        );
      }
    },
  );

document
  .getElementById("tableKategori")
  .addEventListener("click", async (e) => {
    const saveBtn = e.target.closest("[data-save-kategori]");
    const deleteBtn = e.target.closest("[data-delete-kategori]");

    if (deleteBtn) {
      const key = deleteBtn.dataset.deleteKategori;
      const item = cache.kategori.find((k) => k.key === key);
      if (!item) return;
      if (!confirm(`Hapus kategori "${item.nama}"? Transaksi lama tetap tersimpan.`)) return;
      try {
        await hapusKategori(key);
        await loadDashboard();
        renderKategoriTable(cache.flat);
      } catch (err) {
        console.error(err);
        alert("Gagal menghapus kategori. Cek rules Firebase.");
      }
      return;
    }

    if (!saveBtn) return;
    const key = saveBtn.dataset.saveKategori;
    const namaInput = document.querySelector(`.kategori-nama-input[data-key="${key}"]`);
    const hargaInput = document.querySelector(`.kategori-harga-input[data-key="${key}"]`);
    const nama = namaInput?.value.trim();
    const harga = parseFloat(hargaInput?.value);
    if (!nama || !Number.isFinite(harga) || harga <= 0) {
      alert("Nama dan harga kategori harus valid.");
      return;
    }
    const duplicate = cache.kategori.some((k) => k.key !== key && k.nama.toLowerCase() === nama.toLowerCase());
    if (duplicate) {
      alert("Nama kategori sudah dipakai.");
      return;
    }
    saveBtn.textContent = "…";
    try {
      await simpanKategori(key, nama, harga);
      await loadDashboard();
      renderKategoriTable(cache.flat);
    } catch (err) {
      console.error(err);
      alert("Gagal menyimpan kategori. Cek koneksi atau rules Firebase.");
      saveBtn.textContent = "Simpan";
    }
  });

// ============================================================================
// Stok
// ============================================================================

function renderStokTable(flat) {
  const dayKeys = new Set(last30Days().map(isoDate));
  const setorAll = flat.filter((t) =>
    t.tipe === "Setor" && dayKeys.has(t.tanggal?.slice(0, 10)),
  );
  const wasteOutAll = flat.filter((t) =>
    (t.isWasteOut || t.tipe === "Pengeluaran Sampah") && dayKeys.has(t.tanggal?.slice(0, 10)),
  );

  document.getElementById(
    "tableStok",
  ).innerHTML =
    cache.kategori
      .map((k) => {
        const masukKg = setorAll.reduce((sum, t) => sum + getSetorItems(t)
          .filter((item) => item.kategori === k.nama)
          .reduce((sub, item) => sub + (Number(item.berat_kg) || 0), 0), 0);
        const keluarKg = wasteOutAll.reduce((sum, t) => sum + getWasteOutItems(t)
          .filter((item) => item.kategori === k.nama)
          .reduce((sub, item) => sub + (Number(item.berat_kg) || 0), 0), 0);
        const totalKg = Math.max(0, masukKg - keluarKg);

        const nilai =
          totalKg * k.harga;

        const warna =
          warnaKategori(k.nama);

        return `
          <tr>
            <td>
              <span
                class="pill"
                style="
                  background:${warna}1A;
                  color:${warna}
                "
              >
                ${k.nama}
              </span>
            </td>

            <td>
              ${formatKg(totalKg)}
            </td>

            <td>
              ${formatRp(nilai)}
            </td>
          </tr>
        `;
      })
      .join("") ||
    `
      <tr class="loading-row">
        <td colspan="3">
          Belum ada kategori.
        </td>
      </tr>
    `;
}

// ============================================================================
// Keuangan
// ============================================================================

function renderKeuangan(
  users,
  flat,
) {
  const dayKeys =
    last30Days().map(isoDate);

  const last30 = flat.filter(
    (t) =>
      dayKeys.includes(
        t.tanggal?.slice(0, 10),
      ),
  );

  const masuk =
    last30
      .filter(
        (t) => t.tipe === "Setor",
      )
      .reduce(
        (s, t) =>
          s + (t.total_rp || 0),
        0,
      );

  const keluar =
    last30
      .filter(
        (t) => t.tipe === "Tarik",
      )
      .reduce(
        (s, t) =>
          s + (t.total_rp || 0),
        0,
      );

  const saldoAktif =
    Object.values(users).reduce(
      (s, u) =>
        s +
        (u.saldo_terakhir || 0),
      0,
    );

  document.getElementById(
    "keuanganSaldoAktif",
  ).textContent =
    formatRp(saldoAktif);

  document.getElementById(
    "keuanganMasuk",
  ).textContent =
    formatRp(masuk);

  document.getElementById(
    "keuanganKeluar",
  ).textContent =
    formatRp(keluar);

  document.getElementById(
    "keuanganTxList",
  ).innerHTML =
    flat
      .slice(0, 8)
      .map(txRowHtml)
      .join("") ||
    '<p class="empty-note">Belum ada transaksi.</p>';
}

// ============================================================================
// Raport
// ============================================================================

function renderRaport(
  users,
  flat,
) {
  const dayKeys =
    last30Days().map(isoDate);

  const last30 = flat.filter(
    (t) =>
      dayKeys.includes(
        t.tanggal?.slice(0, 10),
      ),
  );

  const setor30 = last30.filter(
    (t) => t.tipe === "Setor",
  );

  const totalKg =
    setor30.reduce(
      (s, t) =>
        s +
        (parseFloat(
          t.berat_kg,
        ) || 0),
      0,
    );

  const nasabahAktif =
    new Set(
      last30.map(
        (t) => t.uid,
      ),
    ).size;

  const totalNilaiSetor =
    setor30.reduce(
      (s, t) =>
        s +
        (t.total_rp || 0),
      0,
    );

  const rataRata =
    setor30.length
      ? Math.round(
          totalNilaiSetor /
            setor30.length,
        )
      : 0;

  const rows = [
    [
      "Total nasabah terdaftar",
      Object.keys(users).length,
    ],

    [
      "Total sampah disetor (30 hari)",
      formatKg(totalKg),
    ],

    [
      "Nasabah aktif (30 hari)",
      nasabahAktif,
    ],

    [
      "Rata-rata nilai setor per transaksi",
      formatRp(rataRata),
    ],

    [
      "Total transaksi (30 hari)",
      last30.length,
    ],
  ];

  document.getElementById(
    "tableRaport",
  ).innerHTML =
    rows
      .map(
        ([label, value]) => `
          <tr>
            <td>${label}</td>

            <td
              style="font-family:var(--font-mono)"
            >
              ${value}
            </td>
          </tr>
        `,
      )
      .join("");
}

// ============================================================================
// Laporan bulanan + PDF
// ============================================================================

function monthKey(date) {
  const d = date instanceof Date ? date : new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function monthLabel(key) {
  const [year, month] = key.split("-").map(Number);
  return new Intl.DateTimeFormat("id-ID", {
    month: "long",
    year: "numeric",
  }).format(new Date(year, month - 1, 1));
}

function getMonthlyData(flat, key) {
  const [year, month] = key.split("-").map(Number);
  const start = new Date(year, month - 1, 1);
  const end = new Date(year, month, 0);
  const days = [];

  for (let day = 1; day <= end.getDate(); day += 1) {
    days.push(new Date(year, month - 1, day));
  }

  const tx = flat.filter((t) => {
    if (!t.tanggal) return false;
    const d = new Date(t.tanggal);
    return d >= start && d <= new Date(year, month - 1, end.getDate(), 23, 59, 59, 999);
  });

  const masuk = days.map((d) => {
    const k = isoDate(d);
    return tx.filter((t) => t.tanggal?.slice(0, 10) === k && t.tipe === "Setor")
      .reduce((sum, t) => sum + (Number(t.total_rp) || 0), 0);
  });

  const tarik = days.map((d) => {
    const k = isoDate(d);
    return tx.filter((t) => t.tanggal?.slice(0, 10) === k && t.tipe === "Tarik")
      .reduce((sum, t) => sum + (Number(t.total_rp) || 0), 0);
  });

  const setor = tx.filter((t) => t.tipe === "Setor");
  const tarikTx = tx.filter((t) => t.tipe === "Tarik");
  const totalKg = setor.reduce((sum, t) => sum + totalBeratTx(t), 0);
  const totalMasuk = masuk.reduce((a, b) => a + b, 0);
  const totalTarik = tarik.reduce((a, b) => a + b, 0);
  const activeCustomers = new Set(tx.filter((t) => !t.isWasteOut && t.uid).map((t) => t.uid)).size;
  const wasteOut = tx.filter((t) => t.isWasteOut || t.tipe === "Pengeluaran Sampah");
  const totalOutKg = wasteOut.reduce((sum, t) => sum + totalBeratWasteOut(t), 0);

  const categoryTotals = {};
  setor.forEach((t) => {
    getSetorItems(t).forEach((item) => {
      const k = item.kategori || "Lainnya";
      categoryTotals[k] = (categoryTotals[k] || 0) + (Number(item.berat_kg) || 0);
    });
  });

  return {
    key,
    label: monthLabel(key),
    days,
    masuk,
    tarik,
    tx,
    setor,
    tarikTx,
    totalKg,
    totalOutKg,
    wasteOut,
    totalMasuk,
    totalTarik,
    net: totalMasuk - totalTarik,
    activeCustomers,
    categoryTotals,
  };
}

function renderMonthlyReportPreview() {
  const input = document.getElementById("reportMonth");
  const key = input?.value || monthKey(new Date());
  const data = getMonthlyData(cache.flat, key);
  const categoryRows = Object.entries(data.categoryTotals)
    .sort((a, b) => b[1] - a[1])
    .map(([name, kg]) => `<tr><td>${name}</td><td>${formatKg(kg)}</td></tr>`)
    .join("") || '<tr><td colspan="2">Belum ada setoran pada bulan ini.</td></tr>';

  const avg = data.setor.length ? Math.round(data.totalMasuk / data.setor.length) : 0;
  const bestIndex = data.masuk.reduce((best, value, i, arr) => value > arr[best] ? i : best, 0);
  const bestDay = data.masuk[bestIndex] > 0 ? `${data.days[bestIndex].getDate()} ${monthLabel(key).split(" ")[0]}` : "-";

  document.getElementById("monthlyReportStats").innerHTML = `
    <div class="report-stat"><span>Total sampah masuk</span><strong>${formatKg(data.totalKg)}</strong></div>
    <div class="report-stat"><span>Total sampah keluar</span><strong>${formatKg(data.totalOutKg)}</strong></div>
    <div class="report-stat"><span>Uang masuk / setor</span><strong>${formatRp(data.totalMasuk)}</strong></div>
    <div class="report-stat"><span>Uang ditarik</span><strong>${formatRp(data.totalTarik)}</strong></div>
    <div class="report-stat"><span>Saldo bersih arus transaksi</span><strong>${formatRp(data.net)}</strong></div>
    <div class="report-stat"><span>Nasabah aktif</span><strong>${data.activeCustomers}</strong></div>
    <div class="report-stat"><span>Total transaksi</span><strong>${data.tx.length}</strong></div>
  `;

  document.getElementById("monthlyCategoryBody").innerHTML = categoryRows;
  document.getElementById("monthlyAnalysis").textContent = data.tx.length
    ? `Bulan ${data.label}: tercatat ${data.tx.length} transaksi dari ${data.activeCustomers} nasabah aktif. Setoran menghasilkan ${formatKg(data.totalKg)} sampah dengan nilai ${formatRp(data.totalMasuk)}. Sampah yang dikeluarkan ke pengepul/pihak lain mencapai ${formatKg(data.totalOutKg)}. Penarikan saldo mencapai ${formatRp(data.totalTarik)}. Hari dengan pemasukan setor tertinggi adalah ${bestDay}. Rata-rata nilai setiap transaksi setor ${formatRp(avg)}.`
    : `Belum ada transaksi pada ${data.label}.`;
}

function drawPdfChart(doc, data, x, y, width, height) {
  const left = x + 38;
  const right = x + width - 10;
  const top = y + 12;
  const bottom = y + height - 24;
  const max = Math.max(1, ...data.masuk, ...data.tarik);
  const stepX = (right - left) / Math.max(1, data.days.length - 1);
  const py = (v) => bottom - (v / max) * (bottom - top);

  doc.setDrawColor(220, 228, 223);
  doc.setLineWidth(0.35);
  for (let i = 0; i <= 4; i += 1) {
    const gy = top + ((bottom - top) * i) / 4;
    doc.line(left, gy, right, gy);
    doc.setFontSize(7);
    doc.setTextColor(100, 112, 106);
    doc.text(formatRp(max * (1 - i / 4)), x + 2, gy + 2);
  }

  const drawSeries = (values, color) => {
    doc.setDrawColor(...color);
    doc.setFillColor(...color);
    doc.setLineWidth(1.1);
    for (let i = 1; i < values.length; i += 1) {
      doc.line(left + (i - 1) * stepX, py(values[i - 1]), left + i * stepX, py(values[i]));
    }
    values.forEach((v, i) => {
      if (v <= 0) return;
      doc.circle(left + i * stepX, py(v), 1.2, "F");
    });
  };

  drawSeries(data.masuk, [30, 122, 76]);
  drawSeries(data.tarik, [18, 168, 131]);

  doc.setFontSize(7);
  doc.setTextColor(90, 103, 96);
  data.days.forEach((d, i) => {
    if (i % 5 !== 0 && i !== data.days.length - 1) return;
    doc.text(`${d.getDate()}/${d.getMonth() + 1}`, left + i * stepX - 5, bottom + 12);
  });

  doc.setDrawColor(30, 122, 76);
  doc.setLineWidth(1.5);
  doc.line(x + 50, y + height - 5, x + 62, y + height - 5);
  doc.setTextColor(55, 70, 63);
  doc.text("Masuk", x + 65, y + height - 3);
  doc.setDrawColor(18, 168, 131);
  doc.line(x + 100, y + height - 5, x + 112, y + height - 5);
  doc.setTextColor(55, 70, 63);
  doc.text("Narik", x + 115, y + height - 3);
}

async function downloadMonthlyPdf() {
  const input = document.getElementById("reportMonth");
  const key = input?.value || monthKey(new Date());
  const data = getMonthlyData(cache.flat, key);

  if (!window.jspdf?.jsPDF) {
    alert("Library PDF belum siap. Pastikan internet aktif lalu coba lagi.");
    return;
  }

  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ unit: "mm", format: "a4" });
  const margin = 15;
  let y = 18;

  doc.setTextColor(16, 36, 27);
  doc.setFontSize(18);
  doc.setFont(undefined, "bold");
  doc.text("Resik For Schooling", margin, y);
  y += 8;
  doc.setFontSize(13);
  doc.text(`Rekapan Bulanan — ${data.label}`, margin, y);
  y += 7;
  doc.setFont(undefined, "normal");
  doc.setFontSize(8.5);
  doc.setTextColor(100, 112, 106);
  doc.text(`Dibuat: ${new Intl.DateTimeFormat("id-ID", { dateStyle: "long" }).format(new Date())}`, margin, y);
  y += 10;

  const cards = [
    ["Sampah masuk", formatKg(data.totalKg)],
    ["Uang masuk", formatRp(data.totalMasuk)],
    ["Uang ditarik", formatRp(data.totalTarik)],
    ["Saldo bersih", formatRp(data.net)],
  ];
  const cardW = 43;
  cards.forEach(([label, value], i) => {
    const x = margin + i * (cardW + 3);
    doc.setFillColor(241, 245, 241);
    doc.roundedRect(x, y, cardW, 20, 2.5, 2.5, "F");
    doc.setTextColor(100, 112, 106);
    doc.setFontSize(7.5);
    doc.text(label, x + 4, y + 7);
    doc.setTextColor(16, 36, 27);
    doc.setFontSize(10);
    doc.setFont(undefined, "bold");
    doc.text(value, x + 4, y + 15);
    doc.setFont(undefined, "normal");
  });
  y += 28;

  doc.setFontSize(11);
  doc.setFont(undefined, "bold");
  doc.setTextColor(16, 36, 27);
  doc.text("Arus Transaksi Harian", margin, y);
  y += 3;
  drawPdfChart(doc, data, margin, y, 180, 78);
  y += 86;

  doc.setFontSize(11);
  doc.setFont(undefined, "bold");
  doc.text("Analisis", margin, y);
  y += 6;
  doc.setFont(undefined, "normal");
  doc.setFontSize(8.5);
  const avg = data.setor.length ? Math.round(data.totalMasuk / data.setor.length) : 0;
  const bestIndex = data.masuk.reduce((best, value, i, arr) => value > arr[best] ? i : best, 0);
  const bestDay = data.masuk[bestIndex] > 0 ? `${data.days[bestIndex].getDate()}/${data.days[bestIndex].getMonth() + 1}` : "-";
  const analysis = `Pada ${data.label}, terdapat ${data.tx.length} transaksi dari ${data.activeCustomers} nasabah aktif. Sampah yang masuk mencapai ${formatKg(data.totalKg)} dengan nilai setor ${formatRp(data.totalMasuk)}. Sampah yang dikeluarkan ke pengepul/pihak lain mencapai ${formatKg(data.totalOutKg)}. Penarikan saldo mencapai ${formatRp(data.totalTarik)}, sehingga arus bersih sebesar ${formatRp(data.net)}. Pemasukan setor tertinggi terjadi pada ${bestDay}, dengan rata-rata nilai transaksi setor ${formatRp(avg)}.`;
  const lines = doc.splitTextToSize(analysis, 180);
  doc.text(lines, margin, y);
  y += lines.length * 4 + 7;

  doc.setFontSize(11);
  doc.setFont(undefined, "bold");
  doc.text("Rekap Kategori Sampah", margin, y);
  y += 5;
  doc.setFont(undefined, "normal");
  doc.setFillColor(30, 122, 76);
  doc.setTextColor(255, 255, 255);
  doc.rect(margin, y, 180, 7, "F");
  doc.setFontSize(8);
  doc.text("Kategori", margin + 3, y + 5);
  doc.text("Total", margin + 150, y + 5);
  y += 7;
  doc.setTextColor(45, 60, 53);

  Object.entries(data.categoryTotals).sort((a, b) => b[1] - a[1]).forEach(([name, kg], i) => {
    if (y > 275) {
      doc.addPage();
      y = 18;
    }
    if (i % 2 === 0) {
      doc.setFillColor(247, 249, 247);
      doc.rect(margin, y, 180, 7, "F");
    }
    doc.text(name, margin + 3, y + 5);
    doc.text(formatKg(kg), margin + 150, y + 5);
    y += 7;
  });

  doc.setTextColor(120, 130, 125);
  doc.setFontSize(7);
  doc.text("Laporan dibuat otomatis dari transaksi yang tersimpan di Firebase.", margin, 287);
  doc.save(`rekapan-${key}.pdf`);
}

document.getElementById("btnDownloadReport")?.addEventListener("click", downloadMonthlyPdf);

document.getElementById("reportMonth")?.addEventListener("change", renderMonthlyReportPreview);

function initMonthlyReport() {
  const input = document.getElementById("reportMonth");
  if (!input) return;
  input.value = monthKey(new Date());
  renderMonthlyReportPreview();
}

// ============================================================================
// View navigation
// ============================================================================

async function showView(name) {
  document
    .querySelectorAll(".view")
    .forEach((el) =>
      el.classList.remove(
        "is-active",
      ),
    );

  document
    .getElementById(
      `view-${name}`,
    )
    ?.classList.add("is-active");

  document
    .querySelectorAll(".nav-item")
    .forEach((el) =>
      el.classList.toggle(
        "is-active",
        el.dataset.view === name,
      ),
    );

  if (name === "nasabah") {
    renderNasabahTable(
      cache.users,
    );
  }

  if (name === "kategori") {
    renderKategoriTable(
      cache.flat,
    );
  }

  if (name === "stok") {
    renderStokTable(
      cache.flat,
    );
  }

  if (name === "keuangan") {
    renderKeuangan(
      cache.users,
      cache.flat,
    );
  }

  if (name === "raport") {
    renderRaport(
      cache.users,
      cache.flat,
    );
    renderMonthlyReportPreview();
  }
}

document
  .getElementById("navGroup")
  .addEventListener(
    "click",
    (e) => {
      const btn =
        e.target.closest(
          ".nav-item",
        );

      if (!btn) return;

      showView(
        btn.dataset.view,
      );
    },
  );

// ============================================================================
// Mobile nav drawer
// ============================================================================

const mobileMenuBtn = document.getElementById("mobileMenuBtn");
const sidebarEl = document.querySelector(".sidebar");
const sidebarOverlay = document.getElementById("sidebarOverlay");

function openSidebar() {
  sidebarEl?.classList.add("is-open");
  sidebarOverlay?.classList.add("is-open");
}

function closeSidebar() {
  sidebarEl?.classList.remove("is-open");
  sidebarOverlay?.classList.remove("is-open");
}

mobileMenuBtn?.addEventListener("click", () => {
  const isOpen = sidebarEl?.classList.contains("is-open");
  isOpen ? closeSidebar() : openSidebar();
});

sidebarOverlay?.addEventListener("click", closeSidebar);

// Tutup drawer otomatis begitu user pilih menu di layar sempit.
document
  .getElementById("navGroup")
  ?.addEventListener("click", (e) => {
    if (e.target.closest(".nav-item")) closeSidebar();
  });

// ============================================================================
// Dashboard search
// ============================================================================

document
  .getElementById("dashboardSearch")
  .addEventListener(
    "keydown",
    (e) => {
      if (e.key !== "Enter") {
        return;
      }

      const q =
        e.target.value
          .trim()
          .toLowerCase();

      showView("nasabah").then(
        () => {
          document
            .querySelectorAll(
              "#tableNasabah tr",
            )
            .forEach((row) => {
              row.style.display =
                !q ||
                row.textContent
                  .toLowerCase()
                  .includes(q)
                  ? ""
                  : "none";
            });
        },
      );
    },
  );

// ============================================================================
// Pengeluaran sampah — sampah fisik keluar untuk ditimbang/dijual di luar
// ============================================================================

const wasteOutItemsEl = document.getElementById("wasteOutItems");
const wasteOutDateEl = document.getElementById("wasteOutDate");
const wasteOutReceiverEl = document.getElementById("wasteOutReceiver");
const wasteOutNoteEl = document.getElementById("wasteOutNote");
const wasteOutTotalEl = document.getElementById("wasteOutTotal");

function wasteOutRowHtml(selected = "", berat = "") {
  return `<div class="multi-item-row waste-out-row">
    <select class="select-input waste-out-kategori">
      ${cache.kategori.map((k) => `<option value="${escapeHtml(k.nama)}" ${k.nama === selected ? "selected" : ""}>${escapeHtml(k.nama)} — ${formatRp(k.harga)}/kg</option>`).join("")}
    </select>
    <input type="number" min="0.01" step="0.01" class="text-input waste-out-berat" value="${berat}" placeholder="Kg" />
    <button type="button" class="link-btn is-danger waste-out-remove">Hapus</button>
  </div>`;
}

function resetWasteOutItems() {
  if (wasteOutItemsEl) wasteOutItemsEl.innerHTML = wasteOutRowHtml();
}

function getCurrentWasteOutItems() {
  return [...document.querySelectorAll(".waste-out-row")]
    .map((row) => ({
      kategori: row.querySelector(".waste-out-kategori")?.value || "",
      berat_kg: parseFloat(row.querySelector(".waste-out-berat")?.value) || 0,
    }))
    .filter((item) => item.kategori && item.berat_kg > 0);
}

function kalkulasiWasteOut() {
  const total = getCurrentWasteOutItems().reduce(
    (sum, item) => sum + item.berat_kg,
    0,
  );
  if (wasteOutTotalEl) wasteOutTotalEl.textContent = formatKg(total);
  return total;
}

function initWasteOutForm() {
  if (!wasteOutItemsEl) return;

  const today = isoDate(new Date());
  if (wasteOutDateEl && !wasteOutDateEl.value) wasteOutDateEl.value = today;
  resetWasteOutItems();
  kalkulasiWasteOut();

  wasteOutItemsEl.addEventListener("input", kalkulasiWasteOut);
  wasteOutItemsEl.addEventListener("change", kalkulasiWasteOut);
  wasteOutItemsEl.addEventListener("click", (event) => {
    const removeBtn = event.target.closest(".waste-out-remove");
    if (!removeBtn) return;

    const rows = document.querySelectorAll(".waste-out-row");
    if (rows.length <= 1) {
      const weightInput = removeBtn.closest(".waste-out-row")?.querySelector(".waste-out-berat");
      if (weightInput) weightInput.value = "";
    } else {
      removeBtn.closest(".waste-out-row")?.remove();
    }
    kalkulasiWasteOut();
  });

  document.getElementById("btnTambahWasteOut")?.addEventListener("click", () => {
    wasteOutItemsEl.insertAdjacentHTML("beforeend", wasteOutRowHtml());
  });

  document.getElementById("btnSimpanWasteOut")?.addEventListener("click", async () => {
    const items = getCurrentWasteOutItems();
    const totalKg = items.reduce((sum, item) => sum + item.berat_kg, 0);
    const tanggalInput = wasteOutDateEl?.value;
    const receiver = wasteOutReceiverEl?.value.trim() || "";
    const note = wasteOutNoteEl?.value.trim() || "";

    if (!tanggalInput) {
      alert("Tanggal pengeluaran wajib diisi.");
      return;
    }
    if (!items.length || totalKg <= 0) {
      alert("Tambahkan minimal satu kategori dan berat sampah.");
      return;
    }
    if (!receiver) {
      alert("Pengepul / penerima wajib diisi.");
      return;
    }

    const btn = document.getElementById("btnSimpanWasteOut");
    if (btn) btn.disabled = true;

    try {
      const key = push(ref(db, "waste_out")).key;
      if (!key) throw new Error("Gagal membuat key pengeluaran sampah.");

      const txn = {
        tipe: "Pengeluaran Sampah",
        tanggal: new Date(`${tanggalInput}T12:00:00`).toISOString(),
        pengepul: receiver,
        catatan: note,
        items,
        berat_kg: totalKg,
        total_rp: 0,
        admin_pencatat: "Admin Sekolah",
      };

      await update(ref(db), { [`waste_out/${key}`]: txn });

      alert("Pengeluaran sampah berhasil dicatat!");
      if (wasteOutReceiverEl) wasteOutReceiverEl.value = "";
      if (wasteOutNoteEl) wasteOutNoteEl.value = "";
      if (wasteOutDateEl) wasteOutDateEl.value = isoDate(new Date());
      resetWasteOutItems();
      kalkulasiWasteOut();
      await loadDashboard();
    } catch (err) {
      console.error(err);
      alert("Gagal menyimpan pengeluaran sampah. Cek koneksi atau rules Firebase.");
    } finally {
      if (btn) btn.disabled = false;
    }
  });
}

initWasteOutForm();

// ============================================================================
// Transaksi
// ============================================================================

let currentUID = null;
let currentNasabahData = null;
let finalAmount = 0;
let html5QrcodeScanner = null;
// Jenis transaksi yang mau langsung dipasang ke form setelah scan QR
// berhasil ("Setor" atau "Tarik"), dipilih lewat toggle di atas tombol
// scan. Manual "Cari" tidak kepengaruh preset ini.
let scanJenisPreset = "Setor";

const inputId =
  document.getElementById(
    "inputId",
  );

const txtNama =
  document.getElementById(
    "txtNama",
  );

const txtSaldo =
  document.getElementById(
    "txtSaldo",
  );

const divProfil =
  document.getElementById(
    "profilNasabah",
  );

const divForm =
  document.getElementById(
    "formTransaksi",
  );

const txEmptyNote =
  document.getElementById(
    "txEmptyNote",
  );

const jenisTx =
  document.getElementById(
    "jenisTx",
  );

const kategoriSelect = document.getElementById("kategori");
const wrapperSampah = document.getElementById("wrapperSampah");
const setorItemsEl = document.getElementById("setorItems");
const inputJumlah = document.getElementById("inputJumlah");
const txtTotal = document.getElementById("txtTotal");
const labelInput = document.getElementById("labelInput");
const readerEl = document.getElementById("reader");
const scanToggleButtons = document.querySelectorAll("#scanToggle .scan-toggle-btn");

scanToggleButtons.forEach((btn) => btn.addEventListener("click", () => {
  scanJenisPreset = btn.dataset.jenis;
  scanToggleButtons.forEach((b) => b.classList.toggle("is-active", b === btn));
}));

function applyScanJenisPreset() {
  jenisTx.value = scanJenisPreset;
  jenisTx.dispatchEvent(new Event("change"));
}

// ============================================================================
// Cari nasabah
// ============================================================================

async function cariNasabah(uid) {
  try {
    const snapshot = await get(child(ref(db), `users/${uid}`));
    if (!snapshot.exists()) {
      alert("Nasabah tidak ditemukan!");
      return;
    }

    currentUID = uid;
    currentNasabahData = snapshot.val();
    txtNama.textContent = `${currentNasabahData.nama} (${currentNasabahData.kelas || ""})`;
    txtSaldo.textContent = formatRp(currentNasabahData.saldo_terakhir || 0);
    divProfil.classList.remove("is-hidden", "hidden");
    divForm.classList.remove("is-hidden", "hidden");
    txEmptyNote.classList.add("hidden");

    if (html5QrcodeScanner) {
      try { await html5QrcodeScanner.clear(); } catch (err) { console.warn("QR scanner clear gagal:", err); }
      html5QrcodeScanner = null;
      readerEl.classList.add("is-hidden");
    }
    kalkulasi();
  } catch (err) {
    console.error(err);
    alert("Gagal koneksi ke database. Pastikan rules database sudah benar.");
  }
}

document.getElementById("btnCari")?.addEventListener("click", () => {
  const uid = inputId.value.trim();
  if (uid) cariNasabah(uid);
});

// ============================================================================
// QR Scanner
// ============================================================================

document.getElementById("btnScan")?.addEventListener("click", () => {
  if (typeof Html5QrcodeScanner === "undefined") {
    alert("Scanner QR belum siap. Pastikan koneksi internet aktif lalu coba lagi.");
    return;
  }

  if (html5QrcodeScanner) {
    try { html5QrcodeScanner.clear(); } catch (_) {}
    html5QrcodeScanner = null;
  }

  readerEl.classList.remove("is-hidden", "hidden");
  html5QrcodeScanner = new Html5QrcodeScanner("reader", {
    fps: 10,
    qrbox: 250,
    rememberLastUsedCamera: true,
    supportedScanTypes: [Html5QrcodeScanType.SCAN_TYPE_CAMERA]
  });

  html5QrcodeScanner.render(
    (decodedText) => {
      inputId.value = decodedText.trim();
      cariNasabah(decodedText.trim()).then(() => applyScanJenisPreset());
    },
    (errorMessage) => {
      // Error scan per-frame normal; tidak perlu ditampilkan ke user.
    }
  );
});

function kategoriRowHtml(selected = "", berat = "") {
  return `<div class="multi-item-row tx-item-row">
    <select class="select-input tx-kategori">
      ${cache.kategori.map((k) => `<option value="${escapeHtml(k.nama)}" ${k.nama === selected ? "selected" : ""}>${escapeHtml(k.nama)} — ${formatRp(k.harga)}/kg</option>`).join("")}
    </select>
    <input type="number" min="0.01" step="0.01" class="text-input tx-berat" value="${berat}" placeholder="Kg" />
    <button type="button" class="link-btn is-danger tx-remove-item" aria-label="Hapus kategori">Hapus</button>
  </div>`;
}

function resetSetorItems() {
  if (setorItemsEl) setorItemsEl.innerHTML = kategoriRowHtml();
}

function getCurrentSetorItems() {
  return [...document.querySelectorAll(".tx-item-row")].map((row) => {
    const kategori = row.querySelector(".tx-kategori")?.value || "";
    const berat = parseFloat(row.querySelector(".tx-berat")?.value) || 0;
    const harga = hargaKategoriOf(kategori);
    return { kategori, berat_kg: berat, harga_per_kg: harga, total_rp: berat * harga };
  }).filter((item) => item.kategori && item.berat_kg > 0);
}

function kalkulasi() {
  if (jenisTx.value === "Setor") {
    const total = totalNilaiItems(getCurrentSetorItems());
    finalAmount = total;
    txtTotal.textContent = formatRp(total);
    return;
  }
  finalAmount = parseFloat(inputJumlah.value) || 0;
  txtTotal.textContent = formatRp(finalAmount);
}

setorItemsEl?.addEventListener("input", kalkulasi);
setorItemsEl?.addEventListener("change", kalkulasi);
setorItemsEl?.addEventListener("click", (e) => {
  const removeBtn = e.target.closest(".tx-remove-item");
  if (!removeBtn) return;
  const rows = document.querySelectorAll(".tx-item-row");
  if (rows.length <= 1) {
    const weightInput = removeBtn.closest(".tx-item-row")?.querySelector(".tx-berat");
    if (weightInput) weightInput.value = "";
  } else {
    removeBtn.closest(".tx-item-row")?.remove();
  }
  kalkulasi();
});

document.getElementById("btnTambahJenisSampah")?.addEventListener("click", () => {
  setorItemsEl.insertAdjacentHTML("beforeend", kategoriRowHtml());
});

inputJumlah.addEventListener("input", kalkulasi);
jenisTx.addEventListener("change", (e) => {
  const isSetor = e.target.value === "Setor";
  wrapperSampah.style.display = isSetor ? "block" : "none";
  inputJumlah.style.display = isSetor ? "none" : "block";
  labelInput.style.display = isSetor ? "none" : "block";
  if (isSetor) {
    resetSetorItems();
  } else {
    inputJumlah.value = "";
  }
  kalkulasi();
});

// ============================================================================
// Proses transaksi
// ============================================================================

document
  .getElementById("btnProses")
  .addEventListener(
    "click",
    async () => {
      if (
        !currentUID ||
        finalAmount <= 0
      ) {
        alert(
          "Data tidak valid / nominal 0",
        );

        return;
      }

      const isSetor =
        jenisTx.value ===
        "Setor";

      const saldoSekarang =
        currentNasabahData
          .saldo_terakhir || 0;

      if (
        !isSetor &&
        finalAmount >
          saldoSekarang
      ) {
        alert(
          "Saldo nasabah tidak mencukupi!",
        );

        return;
      }

      const saldoBaru =
        isSetor
          ? saldoSekarang +
            finalAmount
          : saldoSekarang -
            finalAmount;

      const txnData = {
        tipe: jenisTx.value,
        total_rp: finalAmount,
        tanggal: new Date().toISOString(),
        admin_pencatat: "Admin Sekolah",
      };

      if (isSetor) {
        const items = getCurrentSetorItems();
        if (!items.length) {
          alert("Tambahkan minimal satu kategori dan berat sampah.");
          return;
        }
        txnData.items = items;
        // Tetap simpan field lama untuk kompatibilitas data/transaksi lama.
        txnData.kategori = items.length === 1 ? items[0].kategori : "Multi-kategori";
        txnData.berat_kg = items.reduce((sum, item) => sum + item.berat_kg, 0);
      }

      try {
        const newTxnKey =
          push(
            child(
              ref(db),
              `transactions/${currentUID}`,
            ),
          ).key;

        if (!newTxnKey) {
          throw new Error(
            "Gagal membuat key transaksi.",
          );
        }

        const updates = {};

        updates[
          `users/${currentUID}/saldo_terakhir`
        ] = saldoBaru;

        updates[
          `transactions/${currentUID}/${newTxnKey}`
        ] = txnData;

        await update(
          ref(db),
          updates,
        );

        alert(
          "Transaksi berhasil dicatat!",
        );

        inputJumlah.value = "";
        resetSetorItems();
        kalkulasi();

        await cariNasabah(
          currentUID,
        );

        await loadDashboard();
      } catch (err) {
        console.error(err);

        alert(
          "Gagal memproses transaksi! Cek koneksi atau rules database.",
        );
      }
    },
  );

// ============================================================================
// Boot
// (loadDashboard() dipanggil dari dalam onAuthStateChanged di atas, setelah
// login & pengecekan allowlist admin_emails berhasil)
// ============================================================================
