"use client";

import { useLocale } from "next-intl";
import { Link, usePathname } from "@/i18n/navigation";

/// 言語の切り替え。手本の Boring Old Menu Bar と同じく、上の帯に「EN · 日本語」と並べ、
/// いまの言語を太くする
export function LanguageSwitch() {
  const locale = useLocale();
  const pathname = usePathname();
  const labels = { en: "EN", ja: "日本語" } as const;

  return (
    <div className="flex items-center gap-1.5 text-[12px]">
      {(["en", "ja"] as const).map((target, index) => (
        <span className="flex items-center gap-1.5" key={target}>
          {index > 0 && <span className="text-black/30">·</span>}
          <Link
            className={
              locale === target ? "font-semibold" : "text-black/55 transition hover:text-black"
            }
            href={pathname}
            locale={target}
          >
            {labels[target]}
          </Link>
        </span>
      ))}
    </div>
  );
}
