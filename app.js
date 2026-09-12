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
      setAuthNote("Gagal login dengan Google. Coba lagi.");
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
    document.getElementById("lastTxList").innerHTML =
      '<p class="empty-note">Gagal memuat data. Cek koneksi/rules Firebase.</p>';
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

function last7Days() {
  const days = [];

  for (let i = 6; i >= 0; i -= 1) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    days.push(d);
  }

  return days;
}

const DAY_LABEL = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"];

// ============================================================================
// Data layer
// ============================================================================

async function fetchAllUsers() {
  const snap = await get(child(ref(db), "users"));

  return snap.exists() ? snap.val() : {};
}

async function fetchAllTransactions() {
  const snap = await get(child(ref(db), "transactions"));

  return snap.exists() ? snap.val() : {};
}

async function fetchKategori() {
  const snap = await get(child(ref(db), "kategori"));

  if (!snap.exists()) {
    const seeded = {};

    DEFAULT_KATEGORI.forEach((k) => {
      const newKey = push(ref(db, "kategori")).key;

      if (newKey) {
        seeded[newKey] = k;
      }
    });

    await update(
      ref(db),
      Object.fromEntries(
        Object.entries(seeded).map(([key, val]) => [
          `kategori/${key}`,
          val,
        ]),
      ),
    );

    return Object.entries(seeded).map(([key, val]) => ({
      key,
      ...val,
    }));
  }

  return Object.entries(snap.val()).map(([key, val]) => ({
    key,
    ...val,
  }));
}

// ============================================================================
// Flatten transaksi
// ============================================================================

function flattenTransactions(users, transactionsByUser) {
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

  flat.sort(
    (a, b) => new Date(b.tanggal) - new Date(a.tanggal),
  );

  return flat;
}

// ============================================================================
// Rendering: donut chart
// ============================================================================

function renderDonut(users) {
  const counts = {};

  Object.values(users).forEach((u) => {
    const kelas = u.kelas || "Lainnya";

    counts[kelas] = (counts[kelas] || 0) + 1;
  });

  const entries = Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6);

  const total =
    entries.reduce((sum, [, v]) => sum + v, 0) || 1;

  const size = 150;
  const stroke = 20;
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;

  let offset = 0;

  const segments = entries
    .map(([, value], i) => {
      const fraction = value / total;
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
      <strong>${Object.keys(users).length}</strong>
      <span>Nasabah</span>
    </div>
  `;

  document.getElementById("donutLegend").innerHTML =
    entries
      .map(
        ([kelas, value], i) => `
          <div class="legend-item">
            <span
              class="legend-dot"
              style="background:${DONUT_COLORS[i % DONUT_COLORS.length]}"
            ></span>

            <span>${kelas}</span>

            <span>${value}</span>
          </div>
        `,
      )
      .join("") ||
    '<p class="empty-note">Belum ada data nasabah.</p>';
}

// ============================================================================
// Rendering: line chart
// ============================================================================

function renderLineChart(days, setorCounts, tarikCounts) {
  const w = 640;
  const h = 190;

  const padL = 26;
  const padB = 22;
  const padT = 14;

  const plotW = w - padL - 10;
  const plotH = h - padT - padB;

  const maxVal = Math.max(
    1,
    ...setorCounts,
    ...tarikCounts,
  );

  const stepX =
    plotW / (days.length - 1 || 1);

  const toPoints = (values) =>
    values
      .map((v, i) => {
        const x = padL + i * stepX;

        const y =
          padT +
          plotH -
          (v / maxVal) * plotH;

        return `${x},${y}`;
      })
      .join(" ");

  const gridLines = [0, 0.5, 1]
    .map((f) => {
      const y = padT + plotH * f;

      return `
        <line
          x1="${padL}"
          y1="${y}"
          x2="${w - 10}"
          y2="${y}"
          stroke="#E3E9E2"
          stroke-width="1"
        />
      `;
    })
    .join("");

  const dayLabels = days
    .map((d, i) => {
      const x = padL + i * stepX;

      return `
        <text
          x="${x}"
          y="${h - 4}"
          text-anchor="middle"
        >
          ${DAY_LABEL[d.getDay()]}
        </text>
      `;
    })
    .join("");

  const setorLine = toPoints(setorCounts);
  const tarikLine = toPoints(tarikCounts);

  document.getElementById("lineChart").innerHTML = `
    ${gridLines}

    <polyline
      points="${setorLine}"
      fill="none"
      stroke="#1E7A4C"
      stroke-width="2.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    />

    <polyline
      points="${tarikLine}"
      fill="none"
      stroke="#D65D4E"
      stroke-width="2.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    />

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

  const title = isSetor
    ? `Setor ${tx.berat_kg ?? "-"} Kg ${tx.kategori ?? ""}`
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
        ${isSetor ? "+" : "-"} ${formatRp(tx.total_rp)}
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
  ] = await Promise.all([
    fetchAllUsers(),
    fetchAllTransactions(),
    fetchKategori(),
  ]);

  const flat = flattenTransactions(
    users,
    transactionsByUser,
  );

  cache = {
    users,
    transactions: transactionsByUser,
    flat,
    kategori,
  };

  populateKategoriSelect();

  const days = last7Days();
  const dayKeys = days.map(isoDate);
  const todayKey = isoDate(new Date());

  const setorCounts = dayKeys.map(
    (key) =>
      flat.filter(
        (t) =>
          t.tanggal?.slice(0, 10) === key &&
          t.tipe === "Setor",
      ).length,
  );

  const tarikCounts = dayKeys.map(
    (key) =>
      flat.filter(
        (t) =>
          t.tanggal?.slice(0, 10) === key &&
          t.tipe === "Tarik",
      ).length,
  );

  const txHariIni = flat.filter(
    (t) =>
      t.tanggal?.slice(0, 10) === todayKey,
  ).length;

  const last7 = flat.filter((t) =>
    dayKeys.includes(
      t.tanggal?.slice(0, 10),
    ),
  );

  const wasteInKg = last7
    .filter((t) => t.tipe === "Setor")
    .reduce(
      (sum, t) =>
        sum +
        (parseFloat(t.berat_kg) || 0),
      0,
    );

  const saldoDitarik = last7
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

  renderDonut(users);

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

  renderLineChart(
    days,
    setorCounts,
    tarikCounts,
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

            <td
              style="font-family:var(--font-mono)"
            >
              ${formatRp(
                u.saldo_terakhir || 0,
              )}
            </td>
          </tr>
        `,
      )
      .join("") ||
    `
      <tr class="loading-row">
        <td colspan="6">
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
// Dropdown kategori transaksi
// ============================================================================

function populateKategoriSelect() {
  const select =
    document.getElementById(
      "kategori",
    );

  const current =
    select.value;

  select.innerHTML =
    cache.kategori
      .map(
        (k) =>
          `<option value="${k.nama}">
            ${k.nama} — ${formatRp(
              k.harga,
            )}/kg
          </option>`,
      )
      .join("") ||
    '<option value="">Belum ada kategori</option>';

  if (
    cache.kategori.some(
      (k) =>
        k.nama === current,
    )
  ) {
    select.value = current;
  }
}

// ============================================================================
// Kategori view
// ============================================================================

function renderKategoriTable(flat) {
  const dayKeys =
    last7Days().map(isoDate);

  const last7 = flat.filter(
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
        const totalKg =
          last7
            .filter(
              (t) =>
                t.kategori ===
                k.nama,
            )
            .reduce(
              (sum, t) =>
                sum +
                (parseFloat(
                  t.berat_kg,
                ) || 0),
              0,
            );

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
              <div class="price-edit-row">
                <input
                  type="number"
                  class="kategori-harga-input"
                  data-key="${k.key}"
                  value="${k.harga}"
                />

                <button
                  class="link-btn"
                  data-save-kategori="${k.key}"
                >
                  Simpan
                </button>
              </div>
            </td>

            <td>
              ${formatKg(totalKg)}
            </td>

            <td></td>
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

async function simpanHargaKategori(
  key,
  harga,
) {
  await update(ref(db), {
    [`kategori/${key}/harga`]:
      harga,
  });
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
  .addEventListener(
    "click",
    async (e) => {
      const btn =
        e.target.closest(
          "[data-save-kategori]",
        );

      if (!btn) return;

      const key =
        btn.dataset.saveKategori;

      const input =
        document.querySelector(
          `.kategori-harga-input[data-key="${key}"]`,
        );

      if (!input) return;

      const harga =
        parseFloat(input.value);

      if (
        !Number.isFinite(harga) ||
        harga <= 0
      ) {
        alert(
          "Harga tidak valid.",
        );

        return;
      }

      btn.textContent = "…";

      try {
        await simpanHargaKategori(
          key,
          harga,
        );

        await loadDashboard();

        renderKategoriTable(
          cache.flat,
        );
      } catch (err) {
        console.error(err);

        alert(
          "Gagal menyimpan harga kategori. Cek koneksi atau rules Firebase.",
        );

        btn.textContent =
          "Simpan";
      }
    },
  );

// ============================================================================
// Stok
// ============================================================================

function renderStokTable(flat) {
  const setorAll =
    flat.filter(
      (t) => t.tipe === "Setor",
    );

  document.getElementById(
    "tableStok",
  ).innerHTML =
    cache.kategori
      .map((k) => {
        const totalKg =
          setorAll
            .filter(
              (t) =>
                t.kategori ===
                k.nama,
            )
            .reduce(
              (sum, t) =>
                sum +
                (parseFloat(
                  t.berat_kg,
                ) || 0),
              0,
            );

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
    last7Days().map(isoDate);

  const last7 = flat.filter(
    (t) =>
      dayKeys.includes(
        t.tanggal?.slice(0, 10),
      ),
  );

  const masuk =
    last7
      .filter(
        (t) => t.tipe === "Setor",
      )
      .reduce(
        (s, t) =>
          s + (t.total_rp || 0),
        0,
      );

  const keluar =
    last7
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
    last7Days().map(isoDate);

  const last7 = flat.filter(
    (t) =>
      dayKeys.includes(
        t.tanggal?.slice(0, 10),
      ),
  );

  const setor7 = last7.filter(
    (t) => t.tipe === "Setor",
  );

  const totalKg =
    setor7.reduce(
      (s, t) =>
        s +
        (parseFloat(
          t.berat_kg,
        ) || 0),
      0,
    );

  const nasabahAktif =
    new Set(
      last7.map(
        (t) => t.uid,
      ),
    ).size;

  const totalNilaiSetor =
    setor7.reduce(
      (s, t) =>
        s +
        (t.total_rp || 0),
      0,
    );

  const rataRata =
    setor7.length
      ? Math.round(
          totalNilaiSetor /
            setor7.length,
        )
      : 0;

  const rows = [
    [
      "Total nasabah terdaftar",
      Object.keys(users).length,
    ],

    [
      "Total sampah disetor (7 hari)",
      formatKg(totalKg),
    ],

    [
      "Nasabah aktif (7 hari)",
      nasabahAktif,
    ],

    [
      "Rata-rata nilai setor per transaksi",
      formatRp(rataRata),
    ],

    [
      "Total transaksi (7 hari)",
      last7.length,
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

const kategoriSelect =
  document.getElementById(
    "kategori",
  );

const wrapperSampah =
  document.getElementById(
    "wrapperSampah",
  );

const inputJumlah =
  document.getElementById(
    "inputJumlah",
  );

const txtTotal =
  document.getElementById(
    "txtTotal",
  );

const labelInput =
  document.getElementById(
    "labelInput",
  );

const readerEl =
  document.getElementById(
    "reader",
  );

const scanToggleButtons =
  document.querySelectorAll(
    "#scanToggle .scan-toggle-btn",
  );

scanToggleButtons.forEach(
  (btn) => {
    btn.addEventListener(
      "click",
      () => {
        scanJenisPreset =
          btn.dataset.jenis;

        scanToggleButtons.forEach(
          (b) => {
            b.classList.toggle(
              "is-active",
              b === btn,
            );
          },
        );
      },
    );
  },
);

// Terapkan jenis transaksi hasil pilihan toggle scan ke form (dropdown
// "Jenis Transaksi"), lalu jalankan ulang logic yang sama seperti kalau
// user ganti dropdown itu manual (tampilkan/sembunyikan kategori,
// ubah label nominal, hitung ulang total).
function applyScanJenisPreset() {
  if (jenisTx.value === scanJenisPreset) {
    kalkulasi();
    return;
  }

  jenisTx.value = scanJenisPreset;
  jenisTx.dispatchEvent(new Event("change"));
}

// ============================================================================
// Cari nasabah
// ============================================================================

async function cariNasabah(uid) {
  try {
    const snapshot =
      await get(
        child(
          ref(db),
          `users/${uid}`,
        ),
      );

    if (!snapshot.exists()) {
      alert(
        "Nasabah tidak ditemukan!",
      );

      return;
    }

    currentUID = uid;

    currentNasabahData =
      snapshot.val();

    txtNama.textContent =
      `${currentNasabahData.nama} (${currentNasabahData.kelas})`;

    txtSaldo.textContent =
      formatRp(
        currentNasabahData.saldo_terakhir ||
          0,
      );

    divProfil.classList.remove(
      "is-hidden",
      "hidden",
    );

    divForm.classList.remove(
      "is-hidden",
      "hidden",
    );

    txEmptyNote.classList.add(
      "hidden",
    );

    if (html5QrcodeScanner) {
      try {
        await html5QrcodeScanner.clear();
      } catch (err) {
        console.warn(
          "QR scanner clear gagal:",
          err,
        );
      }

      html5QrcodeScanner = null;

      readerEl.classList.add(
        "is-hidden",
      );
    }

    kalkulasi();
  } catch (err) {
    console.error(err);

    alert(
      "Gagal koneksi ke database. Pastikan rules database sudah benar.",
    );
  }
}

document
  .getElementById("btnCari")
  .addEventListener(
    "click",
    () => {
      const uid =
        inputId.value.trim();

      if (uid) {
        cariNasabah(uid);
      }
    },
  );

// ============================================================================
// QR Scanner
// ============================================================================

document
  .getElementById("btnScan")
  .addEventListener(
    "click",
    () => {
      readerEl.classList.remove(
        "is-hidden",
        "hidden",
      );

      // eslint-disable-next-line no-undef
      html5QrcodeScanner =
        new Html5QrcodeScanner(
          "reader",
          {
            fps: 10,
            qrbox: 250,
          },
        );

      html5QrcodeScanner.render(
        (decodedText) => {
          inputId.value =
            decodedText;

          // Setelah nasabah ketemu, langsung pasang jenis transaksi
          // sesuai toggle yang dipilih admin (Setor/Tarik) supaya
          // penarikan tunai lewat scan QR bisa langsung diproses tanpa
          // langkah tambahan ganti dropdown manual.
          cariNasabah(
            decodedText,
          ).then(() => {
            applyScanJenisPreset();
          });
        },
      );
    },
  );

// ============================================================================
// Kalkulasi transaksi
// ============================================================================

function kalkulasi() {
  const jumlah =
    parseFloat(
      inputJumlah.value,
    ) || 0;

  if (
    jenisTx.value === "Setor"
  ) {
    const harga =
      hargaKategoriOf(
        kategoriSelect.value,
      );

    finalAmount =
      jumlah * harga;
  } else {
    finalAmount = jumlah;
  }

  txtTotal.textContent =
    formatRp(finalAmount);
}

inputJumlah.addEventListener(
  "input",
  kalkulasi,
);

kategoriSelect.addEventListener(
  "change",
  kalkulasi,
);

jenisTx.addEventListener(
  "change",
  (e) => {
    if (
      e.target.value ===
      "Tarik"
    ) {
      wrapperSampah.style.visibility =
        "hidden";

      labelInput.textContent =
        "Nominal Penarikan (Rp)";

      inputJumlah.placeholder =
        "Misal: 10000";
    } else {
      wrapperSampah.style.visibility =
        "visible";

      labelInput.textContent =
        "Berat (Kg)";

      inputJumlah.placeholder =
        "Misal: 2";
    }

    inputJumlah.value = "";

    kalkulasi();
  },
);

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
        tanggal:
          new Date().toISOString(),
        admin_pencatat:
          "Admin Sekolah",
      };

      if (isSetor) {
        txnData.kategori =
          kategoriSelect.value;

        txnData.berat_kg =
          parseFloat(
            inputJumlah.value,
          );
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
