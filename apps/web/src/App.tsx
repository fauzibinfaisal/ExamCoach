import { useEffect, useState } from "react";
import {
  invalidLink,
  linkStates,
  parseLinkStatus,
  type LandingState,
  type LinkRepository,
  type LinkState,
} from "./domain/link-contract";
import type { Route } from "./route";

const stateCopy: Record<
  LinkState,
  { label: string; title: string; description: string }
> = {
  validating: {
    label: "Memeriksa",
    title: "Memeriksa akses tryout",
    description: "Tunggu sebentar. Status akses sedang diperiksa.",
  },
  ready: {
    label: "Siap",
    title: "Siapkan ruang fokus Anda.",
    description:
      "Kenali format tryout sebelum mulai. Gunakan laptop dan koneksi yang stabil.",
  },
  claimed: {
    label: "Sudah digunakan",
    title: "Link terikat ke browser lain",
    description:
      "Kembali ke browser yang pertama digunakan. Jika tidak dapat mengaksesnya, cabut link melalui aplikasi dan buat yang baru.",
  },
  expired: {
    label: "Kedaluwarsa",
    title: "Masa berlaku link telah berakhir",
    description:
      "Link ini tidak dapat digunakan kembali. Buat link baru melalui aplikasi ExamCoach.",
  },
  revoked: {
    label: "Dicabut",
    title: "Akses link telah dicabut",
    description:
      "Link ini tidak lagi aktif. Gunakan aplikasi ExamCoach untuk menyiapkan akses baru.",
  },
  completed: {
    label: "Selesai",
    title: "Sesi tryout telah selesai",
    description:
      "Link ini sudah tidak aktif. Periksa hasil melalui akun Anda di aplikasi ExamCoach.",
  },
  invalid: {
    label: "Tidak tersedia",
    title: "Akses tryout belum tersedia",
    description:
      "Link tidak valid atau layanan akses belum tersedia. Periksa link dari aplikasi ExamCoach.",
  },
};

export function App({
  route,
  repository,
}: {
  route: Route;
  repository: LinkRepository;
}) {
  return (
    <>
      <a className="skip-link" href="#main">
        Lewati ke konten utama
      </a>
      <header className="site-header">
        <a
          className="brand"
          href="/profile"
          aria-label="ExamCoach, profil utama"
        >
          <span className="brand-mark" aria-hidden="true">
            E<span>↗</span>
          </span>
          ExamCoach<span className="web-tag">WEB</span>
        </a>
        <nav aria-label="Navigasi utama">
          <a
            href="/profile"
            aria-current={route.page === "profile" ? "page" : undefined}
          >
            Profil utama
          </a>
          <a
            href={route.preview ? "/mock-test?preview=ready" : "/mock-test"}
            aria-current={route.page === "mock-test" ? "page" : undefined}
          >
            Mock test
          </a>
        </nav>
        <span className="development-label">Pratinjau pengembangan</span>
      </header>
      <div className="page-wrap">
        <main id="main" tabIndex={-1}>
          {route.page === "profile" ? (
            <Profile preview={route.preview} />
          ) : route.page === "mock-test" ? (
            <LinkLanding repository={repository} preview={route.preview} />
          ) : (
            <section className="status-card">
              <p className="eyebrow">EXAMCOACH WEB</p>
              <h1>Halaman tidak ditemukan</h1>
              <p>Gunakan navigasi untuk kembali ke ruang belajar.</p>
              <a className="button" href="/profile">
                Ke profil utama
              </a>
            </section>
          )}
        </main>
        {route.preview && route.page === "mock-test" && (
          <aside className="preview-tools" aria-label="Pratinjau status link">
            <p>
              <strong>Laboratorium W1</strong>
              <span>Data contoh · tidak membuat sesi atau token</span>
            </p>
            <div>
              {linkStates.map((state) => (
                <a
                  key={state}
                  href={`/mock-test?preview=${state}`}
                  aria-current={route.scenario === state ? "true" : undefined}
                >
                  {state}
                </a>
              ))}
            </div>
          </aside>
        )}
        <footer>
          <span>ExamCoach · Belajar dengan arah.</span>
          <span>Fondasi web 0.1.0 · Data contoh</span>
        </footer>
      </div>
    </>
  );
}

function Profile({ preview }: { preview: boolean }) {
  return (
    <>
      <section className="page-intro">
        <p className="eyebrow">RUANG BELAJAR ANDA</p>
        <h1>
          Langkah kecil.
          <br />
          <span>Kesiapan yang terukur.</span>
        </h1>
        <p>Kenali arah belajar Anda, lalu berlatih dengan lebih fokus.</p>
      </section>
      <div className="profile-grid">
        <section className="profile-card" aria-labelledby="profile-title">
          <div className="card-top">
            <span className="eyebrow">PROFIL UTAMA</span>
            <span className="pill">Contoh tampilan</span>
          </div>
          <div className="identity">
            <span className="avatar" aria-hidden="true">
              EC
            </span>
            <div>
              <h2 id="profile-title">Calon peserta</h2>
              <p>Belum masuk ke akun web</p>
            </div>
          </div>
          <dl className="profile-details">
            <div>
              <dt>Target ujian</dt>
              <dd>CPNS</dd>
            </div>
            <div>
              <dt>Fokus latihan</dt>
              <dd>Tes Intelegensia Umum</dd>
            </div>
            <div>
              <dt>Riwayat belajar</dt>
              <dd>Belum terhubung</dd>
            </div>
          </dl>
          <p className="muted">
            Ini adalah profil contoh. Data akun dan riwayat asli belum dimuat
            pada fondasi web ini.
          </p>
        </section>
        <section className="hero-card" aria-labelledby="desktop-title">
          <span className="eyebrow">MOCK TEST DI LAPTOP</span>
          <h2 id="desktop-title">
            Ruang lebih luas.
            <br />
            Fokus lebih penuh.
          </h2>
          <p>
            Pengalaman tryout komputer yang terhubung dengan perjalanan belajar
            di aplikasi ExamCoach.
          </p>
          <div className="desktop-art" aria-hidden="true">
            <div className="monitor">
              <div className="monitor-sidebar">
                <i />
                <i />
                <i />
              </div>
              <div className="monitor-content">
                <b />
                <i />
                <i />
                <span />
                <span />
              </div>
            </div>
            <div className="monitor-base" />
          </div>
          <a
            className="button button-light"
            href={preview ? "/mock-test?preview=ready" : "/mock-test"}
          >
            {preview ? "Lihat pratinjau tryout" : "Buka halaman mock test"}
            <span aria-hidden="true">↗</span>
          </a>
        </section>
      </div>
      <section className="journey" aria-labelledby="journey-title">
        <div>
          <p className="eyebrow">SATU PERJALANAN BELAJAR</p>
          <h2 id="journey-title">Dari genggaman ke meja belajar.</h2>
          <p>Alur yang direncanakan untuk sesi tryout Anda.</p>
        </div>
        <ol>
          <li>
            <span>01</span>
            <div>
              <h3>Pilih di aplikasi</h3>
              <p>Masuk ke akun, pilih tryout, lalu “Kerjakan di laptop”.</p>
            </div>
          </li>
          <li>
            <span>02</span>
            <div>
              <h3>Buka link di laptop</h3>
              <p>Periksa akses dan siapkan browser untuk satu sesi.</p>
            </div>
          </li>
          <li>
            <span>03</span>
            <div>
              <h3>Belajar dari hasil</h3>
              <p>Gunakan hasil terukur untuk menentukan latihan berikutnya.</p>
            </div>
          </li>
        </ol>
      </section>
    </>
  );
}

function LinkLanding({
  repository,
  preview,
}: {
  repository: LinkRepository;
  preview: boolean;
}) {
  const [state, setState] = useState<LandingState>({ status: "validating" });
  useEffect(() => {
    const controller = new AbortController();
    repository
      .readLanding(controller.signal)
      .then((value) => {
        if (!controller.signal.aborted) setState(parseLinkStatus(value));
      })
      .catch(() => {
        if (!controller.signal.aborted) setState(invalidLink);
      });
    return () => controller.abort();
  }, [repository]);
  const copy = stateCopy[state.status];
  return (
    <>
      <div className="breadcrumb">
        <a href="/profile">Profil utama</a>
        <span aria-hidden="true">/</span>
        <span>Mock test</span>
      </div>
      <section
        className={`status-card status-${state.status}`}
        aria-labelledby="link-title"
      >
        <div className="card-top">
          <p className="eyebrow">AKSES MOCK TEST</p>
          <span
            className={`pill ${state.status === "ready" ? "pill-ready" : ""}`}
          >
            {copy.label}
          </span>
        </div>
        <div role="status" aria-live="polite" aria-atomic="true">
          <h1 id="link-title">{copy.title}</h1>
          <p className="status-description">{copy.description}</p>
        </div>
        {state.status === "ready" ? (
          <>
            <div className="tryout-summary">
              <p className="eyebrow">TRYOUT CONTOH</p>
              <h2>{state.tryout.title}</h2>
              <div className="subtests">
                {state.tryout.subtests.map((subtest) => (
                  <span key={subtest}>{subtest}</span>
                ))}
              </div>
              <dl className="test-facts">
                <div>
                  <dt>Jumlah soal</dt>
                  <dd>
                    {state.tryout.questionCount}
                    <small>soal</small>
                  </dd>
                </div>
                <div>
                  <dt>Durasi pengerjaan</dt>
                  <dd>
                    {Math.ceil(state.tryout.durationSeconds / 60)}
                    <small>menit</small>
                  </dd>
                </div>
                <div>
                  <dt>Sisa masa berlaku</dt>
                  <dd>
                    {Math.floor(
                      (state.expiresAtMs - state.serverNowMs) / 3_600_000,
                    )}
                    <small>jam pada snapshot contoh</small>
                  </dd>
                </div>
              </dl>
            </div>
            <div className="landing-bottom">
              <div>
                <h3>Sebelum Anda mulai</h3>
                <ul>
                  <li>Gunakan browser dan koneksi yang stabil.</li>
                  <li>
                    Satu link disiapkan untuk satu pengguna dan satu sesi.
                  </li>
                  <li>Hasil belajar dihitung dengan aturan yang konsisten.</li>
                </ul>
              </div>
              <div className="start-panel">
                <button
                  className="button"
                  disabled
                  aria-describedby="start-note"
                >
                  Mulai tryout
                </button>
                <p id="start-note">
                  Pengerjaan soal belum tersedia pada pratinjau ini.
                </p>
              </div>
            </div>
          </>
        ) : (
          state.status !== "validating" && (
            <a className="button" href="/profile">
              Kembali ke profil utama<span aria-hidden="true">→</span>
            </a>
          )
        )}
        <p className="foundation-note">
          {preview
            ? "Pratinjau lokal: seluruh status dan waktu adalah data contoh."
            : "Fondasi web: layanan link dari aplikasi belum terhubung."}
        </p>
      </section>
      <p className="privacy-note">
        <span aria-hidden="true">◇</span> Akses link hanya untuk satu tryout.
        Informasi akun tidak ditampilkan melalui link.
      </p>
    </>
  );
}
