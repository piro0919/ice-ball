import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { routing } from "@/i18n/routing";

export const alt = "Ice Ball";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/* ビルド時に焼く。動的なままだと public/ が関数側に含まれず、
   本番で icon.png を読めずに 500 になる */
export function generateStaticParams(): { locale: string }[] {
  return routing.locales.map((locale) => ({ locale }));
}

/* 出るのは kk-web の一覧で176px、X のカードで500px 前後。
   その大きさで残るのはアイコンと名前と1行だけ。地はサイトの見出しの帯と同じ明るい灰色 */
const BAND = "#f5f5f7";
const ACCENT = "#2f63d6";
const INK = "#1d1d1f";

export default async function OgImage({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<ImageResponse> {
  const { locale } = await params;
  const isJa = locale === "ja";
  /* 書体は Noto Sans JP の太字。使う文字だけに絞ったものを同梱している。
     文言を変えたら assets/README.md の手順で作り直す */
  const [icon, font] = await Promise.all([
    readFile(join(process.cwd(), "public/icon.png")),
    readFile(join(process.cwd(), "assets/NotoSansJP-Bold-subset.ttf")),
  ]);
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        alignItems: "center",
        /* 地をアイコンと同じ紺にすると、アイコンの輪郭が溶けて消えるので、サイトと同じ明るい地にする */
        background: BAND,
        display: "flex",
        gap: 56,
        height: "100%",
        justifyContent: "center",
        width: "100%",
      }}
    >
      {/* biome-ignore lint/performance/noImgElement: next/image is not available in ImageResponse */}
      <img alt="" height={250} src={iconSrc} width={250} />
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ color: INK, fontSize: 124, letterSpacing: -4 }}>Ice Ball</div>
        <div style={{ color: ACCENT, display: "flex", fontSize: 34, marginTop: 14 }}>
          {isJa ? "メニューバーに、新しい形を。" : "A new shape for your menu bar."}
        </div>
      </div>
    </div>,
    {
      ...size,
      fonts: [{ data: font, name: "Noto Sans JP", style: "normal", weight: 700 }],
    },
  );
}
