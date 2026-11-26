import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
import type { ReactNode } from "react";
import { Link } from "@/i18n/navigation";
import { LanguageSwitch } from "./language-switch";
import { AppleLogo, type Look, type Mode, type Shape, Strip } from "./menu-bar";

const REPO = "https://github.com/piro0919/ice-ball";
const DOWNLOAD = `${REPO}/releases/latest`;
const BREW = "brew install --cask piro0919/tap/ice-ball";

type Row = { title: string; body: string };
type Permission = { label: string; body: string };
type Detail = { lead: string; rest: string };

type PageProps = {
  params: Promise<{ locale: string }>;
};

/// 見本の一覧。手本の Boring Old Menu Bar が全スタイルをアプリの値で描いて並べるのにならい、
/// 形3つをダークとライトで、加えて半径 0 に境界線を付けた例を置く
const TILES: { key: string; shape: Shape; mode: Mode; look?: Look }[] = [
  { key: "default", shape: "default", mode: "dark" },
  { key: "roundedDark", shape: "rounded", mode: "dark" },
  { key: "splitDark", shape: "split", mode: "dark" },
  { key: "roundedLight", shape: "rounded", mode: "light" },
  { key: "splitLight", shape: "split", mode: "light" },
  { key: "square", shape: "rounded", mode: "dark", look: { radius: 0, border: 1 } },
];

/// ページの上の帯。手本の Hand Mirror がページの一番上を macOS のメニューバーにしているのにならい、
/// Ice Ball の Rounded の形で描く。項目は区画への移動
async function TopBar() {
  const t = await getTranslations("nav");
  const item = "hidden rounded-[5px] px-2 py-0.5 transition hover:bg-black/8 md:inline";

  return (
    <div className="sticky top-0 z-50 px-1.5 pt-1.5">
      <nav className="flex h-[30px] items-center justify-between rounded-[10px] bg-white/55 px-3 text-[13px] text-black/85 shadow-[0_1px_4px_rgb(0_0_0/0.18)] ring-1 ring-black/5 backdrop-blur-xl">
        <div className="flex items-center gap-1">
          <AppleLogo className="mr-2 h-[14px] w-[14px]" />
          <Link className="mr-1 flex items-center gap-1.5 font-semibold" href="/">
            <Image alt="" className="h-4 w-4" height={64} src="/icon.png" width={64} />
            Ice Ball
          </Link>
          <a className={item} href="#shapes">
            {t("shapes")}
          </a>
          <a className={item} href="#how">
            {t("how")}
          </a>
          <a className={item} href="#details">
            {t("details")}
          </a>
        </div>
        <div className="flex items-center gap-3">
          <LanguageSwitch />
          <a className="font-semibold text-[var(--color-accent)]" href={DOWNLOAD}>
            {t("download")}
          </a>
        </div>
      </nav>
    </div>
  );
}

/// 手本と同じく、黒の主ボタンと白の副ボタン。どちらも2行で、下の行に中身を書く
function Buttons({
  download,
  downloadSub,
  homebrew,
  homebrewSub,
}: {
  download: string;
  downloadSub: string;
  homebrew: string;
  homebrewSub: string;
}) {
  return (
    <div className="flex w-full flex-col justify-center gap-3 sm:w-auto sm:flex-row">
      <a
        className="flex items-center gap-3 rounded-lg bg-[#1d1d1f] px-6 py-3 text-left text-white transition hover:bg-black"
        href={DOWNLOAD}
      >
        <DownloadIcon />
        <span className="flex flex-col">
          <span className="font-semibold text-[15px]">{download}</span>
          <span className="text-[12px] text-white/65">{downloadSub}</span>
        </span>
      </a>
      <a
        className="flex items-center gap-3 rounded-lg bg-white px-6 py-3 text-left ring-1 ring-black/12 transition hover:bg-black/[0.03]"
        href="#get"
      >
        <TerminalIcon />
        <span className="flex flex-col">
          <span className="font-semibold text-[15px]">{homebrew}</span>
          <span className="font-mono text-[12px] text-[var(--color-mute)]">{homebrewSub}</span>
        </span>
      </a>
    </div>
  );
}

function Label({ children }: { children: ReactNode }) {
  return <p className="mb-2 font-semibold text-[13px] text-[var(--color-ink-2)]">{children}</p>;
}

export default async function Page({ params }: PageProps) {
  const { locale } = await params;
  setRequestLocale(locale);

  const t = await getTranslations();
  const rows = t.raw("rows") as Row[];
  const how = t.raw("how.body") as string[];
  const permissions = t.raw("how.aside.items") as Permission[];
  const details = t.raw("details.items") as Detail[];
  const buttons = (
    <Buttons
      download={t("hero.download")}
      downloadSub={t("hero.downloadSub")}
      homebrew={t("hero.homebrew")}
      homebrewSub={t("hero.homebrewSub")}
    />
  );

  return (
    <>
      <TopBar />

      {/* 見出し。名前と一文、ボタン、その下に使う前と使った後を同じ壁紙で上下に並べる */}
      <section className="bg-[var(--color-band)] px-4 pt-16 pb-16 sm:pt-24">
        <div className="mx-auto flex max-w-[960px] flex-col items-center text-center">
          <Image
            alt=""
            className="h-24 w-24 sm:h-28 sm:w-28"
            height={512}
            priority
            src="/icon-512.png"
            width={512}
          />
          <h1 className="mt-6 max-w-3xl text-balance font-bold text-[40px] leading-[1.1] tracking-[-0.03em] sm:text-[56px]">
            {t("hero.title")}
          </h1>
          <p className="mt-6 max-w-[720px] text-pretty text-[17px] text-[var(--color-ink-2)] leading-relaxed sm:text-[19px]">
            {t("hero.lead")}
          </p>
          <div className="mt-8 flex w-full justify-center">{buttons}</div>
          <p className="mt-4 text-[13px] text-[var(--color-mute)]">{t("hero.requirement")}</p>

          <div className="mt-14 flex w-full max-w-[640px] flex-col gap-6 text-left">
            <div>
              <Label>{t("hero.before")}</Label>
              <Strip mode="dark" shape="default" tall />
            </div>
            <div>
              <Label>{t("hero.after")}</Label>
              <Strip mode="dark" shape="rounded" tall />
            </div>
            <p className="text-[14px] text-[var(--color-mute)] leading-relaxed">
              {t("hero.caption")}
            </p>
          </div>
        </div>
      </section>

      <main className="px-4">
        {/* 見出しの下の、見出しと本文の2列。手本の「何を直すか」の並び */}
        <section className="mx-auto max-w-[960px] pt-8 pb-16">
          {rows.map((row) => (
            <div
              className="grid gap-3 border-black/10 border-b py-8 sm:grid-cols-[2fr_3fr] sm:gap-10"
              key={row.title}
            >
              <h2 className="text-balance font-bold text-[21px] leading-snug tracking-[-0.01em]">
                {row.title}
              </h2>
              <p className="text-[16px] text-[var(--color-ink-2)] leading-relaxed">{row.body}</p>
            </div>
          ))}
        </section>
      </main>

      {/* 形の一覧 */}
      <section className="scroll-mt-12 bg-[var(--color-band)] px-4 py-20" id="shapes">
        <div className="mx-auto max-w-[960px]">
          <h2 className="text-balance font-bold text-[32px] leading-tight tracking-[-0.02em] sm:text-[36px]">
            {t("gallery.title")}
          </h2>
          <p className="mt-3 max-w-[720px] text-[17px] text-[var(--color-ink-2)] leading-relaxed">
            {t("gallery.lead")}
          </p>
          <div className="mt-10 grid gap-x-6 gap-y-8 sm:grid-cols-2 lg:grid-cols-3">
            {TILES.map((tile) => {
              const note = t(`gallery.tiles.${tile.key}.note`);
              return (
                <figure key={tile.key}>
                  <Strip compact look={tile.look} mode={tile.mode} shape={tile.shape} />
                  <figcaption className="mt-2 text-[14px]">
                    {t(`gallery.tiles.${tile.key}.name`)}
                    {note && <span className="text-[var(--color-mute)]"> ({note})</span>}
                  </figcaption>
                </figure>
              );
            })}
          </div>
          <p className="mt-10 max-w-[720px] text-[14px] text-[var(--color-mute)] leading-relaxed">
            {t("gallery.footnote")}
          </p>
        </div>
      </section>

      {/* 仕組み。本文と、必要な許可の枠 */}
      <section className="scroll-mt-12 px-4 py-20" id="how">
        <div className="mx-auto grid max-w-[960px] gap-10 lg:grid-cols-[3fr_2fr]">
          <div>
            <h2 className="font-bold text-[32px] leading-tight tracking-[-0.02em] sm:text-[36px]">
              {t("how.title")}
            </h2>
            <div className="mt-6 flex flex-col gap-5 text-[16px] text-[var(--color-ink-2)] leading-relaxed">
              {how.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </div>
          </div>
          <aside className="self-start rounded-2xl bg-[var(--color-band)] p-7 ring-1 ring-black/8">
            <h3 className="font-semibold text-[16px]">{t("how.aside.title")}</h3>
            <dl className="mt-4 flex flex-col gap-4 text-[15px] leading-relaxed">
              {permissions.map((permission) => (
                <div key={permission.label}>
                  <dt className="font-semibold">{permission.label}</dt>
                  <dd className="text-[var(--color-ink-2)]">{permission.body}</dd>
                </div>
              ))}
            </dl>
            <p className="mt-5 text-[14px] text-[var(--color-mute)] leading-relaxed">
              {t("how.aside.note")}
            </p>
          </aside>
        </div>
      </section>

      {/* 細かい仕様。手本と同じく、四角の印を付けた2列 */}
      <section
        className="scroll-mt-12 border-black/8 border-t bg-[var(--color-band)] px-4 py-20"
        id="details"
      >
        <div className="mx-auto max-w-[960px]">
          <h2 className="font-bold text-[32px] leading-tight tracking-[-0.02em] sm:text-[36px]">
            {t("details.title")}
          </h2>
          <ul className="mt-8 grid gap-x-10 sm:grid-cols-2">
            {details.map((detail) => (
              <li
                className="flex gap-3 border-black/10 border-b py-3.5 text-[15px] leading-relaxed"
                key={detail.lead}
              >
                <span className="mt-[7px] h-2.5 w-2.5 shrink-0 rounded-[3px] bg-[var(--color-accent)]/70" />
                <span>
                  <strong className="font-semibold">{detail.lead}</strong>{" "}
                  <span className="text-[var(--color-ink-2)]">{detail.rest}</span>
                </span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* 入れ方 */}
      <section className="scroll-mt-12 px-4 py-24" id="get">
        <div className="mx-auto flex max-w-[720px] flex-col items-center text-center">
          <h2 className="text-balance font-bold text-[32px] leading-tight tracking-[-0.02em] sm:text-[40px]">
            {t("cta.title")}
          </h2>
          <p className="mt-5 text-pretty text-[16px] text-[var(--color-ink-2)] leading-relaxed">
            {t("cta.lead")}
          </p>
          <div className="mt-8 flex w-full justify-center">{buttons}</div>
          <pre className="mt-6 w-full overflow-x-auto rounded-lg bg-[var(--color-band)] px-5 py-3.5 font-mono text-[14px] ring-1 ring-black/8">
            <code>{BREW}</code>
          </pre>
        </div>
      </section>

      <footer className="border-black/8 border-t px-4 py-10 text-[14px] text-[var(--color-mute)]">
        <div className="mx-auto flex max-w-[960px] flex-col gap-5">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-2">
              <Image alt="" className="h-5 w-5" height={64} src="/icon.png" width={64} />
              <span className="font-semibold text-[var(--color-ink)]">Ice Ball</span>
            </div>
            <div className="flex flex-wrap gap-x-6 gap-y-2">
              <a className="transition hover:text-[var(--color-ink)]" href={REPO}>
                {t("footer.source")}
              </a>
              <a className="transition hover:text-[var(--color-ink)]" href={`${REPO}/releases`}>
                {t("footer.releases")}
              </a>
              <Link className="transition hover:text-[var(--color-ink)]" href="/privacy">
                {t("footer.privacy")}
              </Link>
              <a
                className="transition hover:text-[var(--color-ink)]"
                href="https://buymeacoffee.com/piro0919"
              >
                Buy Me a Coffee
              </a>
            </div>
          </div>
          {/* 名前が似ているので、README と同じ断り書きを置く */}
          <p className="text-[13px]">{t("footer.independent")}</p>
        </div>
      </footer>
    </>
  );
}

function DownloadIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5 fill-none stroke-current"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
    >
      <path d="M12 4v11" />
      <path d="m7 10 5 5 5-5" />
      <path d="M5 20h14" />
    </svg>
  );
}

function TerminalIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5 fill-none stroke-current"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="2"
      viewBox="0 0 24 24"
    >
      <path d="m5 7 5 5-5 5" />
      <path d="M12 18h7" />
    </svg>
  );
}
