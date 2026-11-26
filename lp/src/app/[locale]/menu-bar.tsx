import { getTranslations } from "next-intl/server";

export type Shape = "default" | "rounded" | "split";
export type Mode = "light" | "dark";

/// 形の寸法と色。既定値はアプリ（IceBall/Settings/AppearanceConfiguration.swift）と同じ。
/// 変えるときは両方そろえる
export type Look = {
  radius?: number;
  border?: number;
};

/// 壁紙の上にメニューバーを置いた帯。手本の Boring Old Menu Bar が、メニューバーの見本を
/// 同じ壁紙の帯で並べて比べさせるのにならう。壁紙はライトなら明るい空色、ダークなら紺
export async function Strip({
  shape,
  mode,
  look,
  tall = false,
  compact = false,
}: {
  shape: Shape;
  mode: Mode;
  look?: Look;
  tall?: boolean;
  compact?: boolean;
}) {
  return (
    <div
      className={`wallpaper-${mode} relative w-full overflow-hidden rounded-xl ring-1 ring-black/8 ${
        tall ? "h-28 sm:h-32" : "h-20 sm:h-24"
      }`}
    >
      <MenuBar compact={compact} look={look} mode={mode} shape={shape} />
    </div>
  );
}

/// メニューバー。default は macOS 26 の標準どおり背景なし、rounded は全体を1つの角丸で、
/// split はメニューとステータスアイコンの2つの角丸で囲む。
/// 中身はアプリのプレビュー（IceBall/UI/Localization.swift の previewMenus）と同じ並び。
/// compact は一覧の小さな帯の版で、メニューを2つ、時刻を短くして、左右がぶつからないようにする
export async function MenuBar({
  shape,
  mode,
  look,
  compact = false,
}: {
  shape: Shape;
  mode: Mode;
  look?: Look;
  compact?: boolean;
}) {
  const t = await getTranslations("menuBar");
  const radius = look?.radius ?? 10;
  const border = look?.border ?? 0;
  const ink = mode === "dark" ? "text-white" : "text-black/85";

  const menus = (
    <div
      className={`flex min-w-0 items-center whitespace-nowrap ${compact ? "gap-3" : "gap-3.5 sm:gap-4"}`}
    >
      <AppleLogo />
      <span className="font-semibold">Finder</span>
      <span>{t("file")}</span>
      {!compact && <span className="hidden sm:inline">{t("edit")}</span>}
      {!compact && <span className="hidden sm:inline">{t("view")}</span>}
    </div>
  );
  const status = (
    <div
      className={`flex shrink-0 items-center whitespace-nowrap ${compact ? "gap-2.5" : "gap-3"}`}
    >
      <Wifi />
      <Battery />
      {compact ? (
        <span className="tabular-nums">10:42</span>
      ) : (
        <span className="hidden tabular-nums sm:inline">{t("clock")}</span>
      )}
    </div>
  );

  if (shape === "default") {
    return (
      <div className={`flex h-8 items-center justify-between px-4 text-[13px] ${ink}`}>
        {menus}
        {status}
      </div>
    );
  }

  // 既定値: 左右の余白 6、上下の余白 3、ライトは白・ダークは #1c1c1f、どちらも 55%、影あり
  const fill = mode === "dark" ? "rgb(28 28 31 / 0.55)" : "rgb(255 255 255 / 0.55)";
  const pillStyle = {
    background: fill,
    borderRadius: radius,
    boxShadow: [
      "0 1px 4px rgb(0 0 0 / 0.3)",
      border > 0 ? `inset 0 0 0 ${border}px rgb(128 128 128 / 0.6)` : "",
    ]
      .filter(Boolean)
      .join(", "),
  };
  const pill = `flex h-[26px] items-center backdrop-blur-md ${compact ? "px-2.5" : "px-3"}`;

  return (
    <div className={`flex h-8 items-center justify-between gap-2 px-1.5 text-[13px] ${ink}`}>
      {shape === "rounded" ? (
        <div className={`${pill} w-full justify-between`} style={pillStyle}>
          {menus}
          {status}
        </div>
      ) : (
        <>
          <div className={`${pill} shrink-0`} style={pillStyle}>
            {menus}
          </div>
          <div className={pill} style={pillStyle}>
            {status}
          </div>
        </>
      )}
    </div>
  );
}

export function AppleLogo({ className = "h-[14px] w-[14px]" }: { className?: string }) {
  return (
    <svg aria-hidden="true" className={`${className} fill-current`} viewBox="0 0 24 24">
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
  );
}

function Wifi() {
  return (
    <svg
      aria-hidden="true"
      className="h-[13px] w-[16px] fill-none stroke-current"
      strokeLinecap="round"
      strokeWidth="2.2"
      viewBox="0 0 24 18"
    >
      <path d="M2 6.5a15 15 0 0 1 20 0" />
      <path d="M5.5 10.2a10 10 0 0 1 13 0" />
      <path d="M9 13.8a5 5 0 0 1 6 0" />
      <circle className="fill-current stroke-none" cx="12" cy="16.6" r="1.4" />
    </svg>
  );
}

function Battery() {
  return (
    <svg aria-hidden="true" className="h-[12px] w-[25px]" viewBox="0 0 27 13">
      <rect
        className="fill-none stroke-current opacity-50"
        height="11"
        rx="3"
        strokeWidth="1"
        width="22"
        x="0.5"
        y="1"
      />
      <rect className="fill-current" height="7" rx="1.5" width="15" x="2.5" y="3" />
      <path className="fill-current opacity-50" d="M24.5 4.5v4a2 2 0 0 0 0-4z" />
    </svg>
  );
}
