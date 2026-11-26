import { getTranslations } from "next-intl/server";
import type { ReactNode } from "react";

export type Shape = "default" | "rounded" | "split";

/// Mac のデスクトップの見本。Sleeve の見出しの絵にならい、壁紙の上にメニューバーを置き、
/// Ice Ball の設定画面を開いた状態で見せる。メニューバーの上に重ねる形は画面写真では
/// 大きさがそろわないので、ここで組む。設定画面の並びと文言はアプリ（IceBall/UI/SettingsView.swift、
/// Localization.swift）に、形の寸法は既定値（AppearanceConfiguration.swift）に合わせる
export async function DesktopMock() {
  const t = await getTranslations("settings");

  return (
    <div className="wallpaper relative h-[520px] w-full overflow-hidden rounded-[28px] ring-1 ring-white/10 sm:h-[560px]">
      <Waves id="hero" />
      <MenuBar shape="rounded" />

      {/* 設定画面。macOS の設定の窓と同じく、区画ごとに角の丸い面にまとめる */}
      <div className="-translate-x-1/2 absolute top-16 left-1/2 w-[340px] max-w-[calc(100%-24px)] rounded-xl bg-[#1e2130]/85 text-[13px] text-white shadow-[0_24px_60px_-12px_rgba(0,0,0,0.7)] ring-1 ring-white/12 backdrop-blur-xl">
        <div className="relative flex h-9 items-center justify-center">
          <div className="absolute left-3 flex gap-2">
            <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
            <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
            <span className="h-3 w-3 rounded-full bg-[#28c840]" />
          </div>
          <span className="font-semibold text-white/85">{t("title")}</span>
        </div>
        <div className="flex flex-col gap-3 px-3 pb-4">
          <Group>
            <Row label={t("enable")}>
              <Switch />
            </Row>
          </Group>
          <Group title={t("shape")}>
            <Row label={t("shape")}>
              <div className="flex rounded-md bg-white/10 p-0.5 text-[12px]">
                <span className="px-2 py-0.5 text-white/70">Default</span>
                <span className="rounded-[5px] bg-white/25 px-2 py-0.5">Rounded</span>
                <span className="px-2 py-0.5 text-white/70">Split</span>
              </div>
            </Row>
          </Group>
          <Group title={t("shapeAndMargins")}>
            <Row label={t("cornerRadius")}>
              <Slider value="10" fill="50%" />
            </Row>
            <Row label={t("sideMargin")}>
              <Slider value="6" fill="15%" />
            </Row>
          </Group>
          <Group title={t("background")}>
            <Row label={t("opacity")}>
              <Slider value="55%" fill="55%" />
            </Row>
          </Group>
        </div>
      </div>
    </div>
  );
}

/// メニューバー。default は macOS 26 の標準どおり背景なし、rounded は全体を1つの角丸で、
/// split はメニューとステータスアイコンの2つの角丸で囲む
/// compact はカードの中に置く短い版。項目を減らし、時刻だけにする
export async function MenuBar({ shape, compact = false }: { shape: Shape; compact?: boolean }) {
  const t = await getTranslations("menuBar");
  const menus = (
    <div className="flex items-center gap-4">
      <AppleLogo />
      <span className="font-semibold">Finder</span>
      <span className={compact ? "" : "hidden sm:inline"}>{t("file")}</span>
      {!compact && (
        <>
          <span className="hidden sm:inline">{t("edit")}</span>
          <span className="hidden sm:inline">{t("view")}</span>
        </>
      )}
    </div>
  );
  const status = (
    <div className="flex items-center gap-3">
      <Wifi />
      <Battery />
      <span className="tabular-nums">{compact ? "10:42" : t("clock")}</span>
    </div>
  );

  if (shape === "default") {
    return (
      <div className="relative flex h-8 items-center justify-between px-4 text-[13px] text-white">
        {menus}
        {status}
      </div>
    );
  }

  // 既定値: 角丸 10、左右の余白 6、上下の余白 3、背景はダークで 55%、影あり
  const pill =
    "flex h-[26px] items-center rounded-[10px] bg-[#1c1c1f]/55 px-3 shadow-[0_1px_4px_rgba(0,0,0,0.35)] backdrop-blur-md";

  return (
    <div className="relative flex h-8 items-center justify-between px-1.5 py-[3px] text-[13px] text-white">
      {shape === "rounded" ? (
        <div className={`${pill} w-full justify-between`}>
          {menus}
          {status}
        </div>
      ) : (
        <>
          <div className={pill}>{menus}</div>
          <div className={pill}>{status}</div>
        </>
      )}
    </div>
  );
}

/// 壁紙の波。Sleeve の見出しの絵にある、下から立ち上がる明るい波。
/// 1ページに何枚も置くので、塗りの id は呼ぶ側で分ける
export function Waves({ id }: { id: string }) {
  return (
    <svg
      aria-hidden="true"
      className="absolute inset-x-0 bottom-0 h-[62%] w-full"
      preserveAspectRatio="none"
      viewBox="0 0 900 340"
    >
      <defs>
        <linearGradient id={`${id}-wave-a`} x1="0" x2="1" y1="0" y2="1">
          <stop offset="0" stopColor="#9fd0ff" />
          <stop offset="1" stopColor="#5a8de6" />
        </linearGradient>
        <linearGradient id={`${id}-wave-b`} x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" stopColor="#3653b8" />
          <stop offset="1" stopColor="#24358a" />
        </linearGradient>
      </defs>
      <path
        d="M0 80 C 180 40, 300 60, 420 170 S 700 330, 900 330 L 900 340 L 0 340 Z"
        fill={`url(#${id}-wave-b)`}
      />
      <path
        d="M0 170 C 160 120, 300 150, 430 240 S 720 330, 900 336 L 900 340 L 0 340 Z"
        fill={`url(#${id}-wave-a)`}
        opacity="0.9"
      />
    </svg>
  );
}

function AppleLogo() {
  return (
    <svg aria-hidden="true" className="h-[14px] w-[14px] fill-white" viewBox="0 0 24 24">
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
  );
}

function Wifi() {
  return (
    <svg
      aria-hidden="true"
      className="h-[13px] w-[16px] fill-none stroke-white"
      strokeLinecap="round"
      strokeWidth="2.2"
      viewBox="0 0 24 18"
    >
      <path d="M2 6.5a15 15 0 0 1 20 0" />
      <path d="M5.5 10.2a10 10 0 0 1 13 0" />
      <path d="M9 13.8a5 5 0 0 1 6 0" />
      <circle className="fill-white stroke-none" cx="12" cy="16.6" r="1.4" />
    </svg>
  );
}

function Battery() {
  return (
    <svg aria-hidden="true" className="h-[12px] w-[25px]" viewBox="0 0 27 13">
      <rect
        className="fill-none stroke-white/50"
        height="11"
        rx="3"
        strokeWidth="1"
        width="22"
        x="0.5"
        y="1"
      />
      <rect className="fill-white" height="7" rx="1.5" width="15" x="2.5" y="3" />
      <path className="fill-white/50" d="M24.5 4.5v4a2 2 0 0 0 0-4z" />
    </svg>
  );
}

function Group({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      {title && <span className="px-1 font-semibold text-[11px] text-white/45">{title}</span>}
      <div className="flex flex-col divide-y divide-white/8 rounded-lg bg-white/[0.06] ring-1 ring-white/8">
        {children}
      </div>
    </div>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4 px-3 py-2">
      <span className="truncate">{label}</span>
      {children}
    </div>
  );
}

function Switch() {
  return (
    <span className="flex h-[18px] w-8 items-center justify-end rounded-full bg-[#2f7cf6] px-0.5">
      <span className="h-[14px] w-[14px] rounded-full bg-white" />
    </span>
  );
}

function Slider({ value, fill }: { value: string; fill: string }) {
  return (
    <div className="flex items-center gap-2">
      <div className="relative h-1 w-24 rounded-full bg-white/20">
        <div
          className="absolute inset-y-0 left-0 rounded-full bg-[#2f7cf6]"
          style={{ width: fill }}
        />
        <div
          className="-translate-x-1/2 -translate-y-1/2 absolute top-1/2 h-3.5 w-3.5 rounded-full bg-white shadow"
          style={{ left: fill }}
        />
      </div>
      <span className="w-8 text-right text-white/70 tabular-nums">{value}</span>
    </div>
  );
}
