import Foundation

/// Display strings in Japanese and English.
///
/// Kept as a Swift table instead of `.lproj` resources because the app is built by `swiftc`
/// from a shell script, and two languages are easier to follow side by side. Japanese is used
/// when the user's first preferred language is Japanese; English otherwise.
nonisolated enum L {
    static let isJapanese = (Locale.preferredLanguages.first ?? "en").hasPrefix("ja")

    static func t(_ ja: String, _ en: String) -> String {
        isJapanese ? ja : en
    }

    // Status item menu
    static var enableAppearance: String { t("外観の変更を有効にする", "Change the Menu Bar's Look") }
    static var settings: String { t("設定…", "Settings…") }
    static var checkForUpdates: String { t("アップデートを確認…", "Check for Updates…") }
    static var quit: String { t("Ice Ball を終了", "Quit Ice Ball") }

    // Settings window
    static var settingsTitle: String { t("Ice Ball 設定", "Ice Ball Settings") }
    static var launchAtLogin: String { t("ログイン時に起動", "Open at Login") }
    static var loginItemNeedsApproval: String {
        t("システム設定の「ログイン項目」で許可が必要です", "Needs approval in System Settings › Login Items")
    }
    static var open: String { t("開く", "Open") }
    static var shape: String { t("形状", "Shape") }
    static var allow: String { t("許可する", "Allow") }
    static var splitNeedsAccessibility: String {
        t(
            "Split はメニューとステータスアイコンの位置を読むため、アクセシビリティの許可が必要です。許可されるまでは Rounded と同じ形で表示します。",
            "Split reads where the menus and status icons are, which needs Accessibility permission. Until it is allowed, Split looks like Rounded."
        )
    }
    static var needsScreenRecording: String {
        t(
            "「メニューバーの背景を表示」がオンのため、形の外側を壁紙で塗ります。壁紙の画像ファイルを読めないときは画面収録の許可が要ります。許可したあとは Ice Ball を再起動してください。",
            "“Show menu bar background” is on, so the area outside the shape is painted with your desktop picture. When the picture file cannot be read, Screen Recording permission is needed. Restart Ice Ball after allowing it."
        )
    }
    static var shapeAndMargins: String { t("形と余白", "Shape and Margins") }
    static var cornerRadius: String { t("角丸の半径", "Corner Radius") }
    static var horizontalMargin: String { t("左右の余白", "Side Margin") }
    static var verticalMargin: String { t("上下の余白", "Top and Bottom Margin") }
    static var background: String { t("背景", "Background") }
    static var lightBackground: String { t("背景色（ライト）", "Color (Light)") }
    static var darkBackground: String { t("背景色（ダーク）", "Color (Dark)") }
    static var opacity: String { t("透明度", "Opacity") }
    static var borderAndShadow: String { t("境界線と影", "Border and Shadow") }
    static var borderColor: String { t("境界線の色", "Border Color") }
    static var borderWidth: String { t("境界線の太さ", "Border Width") }
    static var dropShadow: String { t("ドロップシャドウ", "Drop Shadow") }
    static var shadowRadius: String { t("影の広がり", "Shadow Size") }
    static var restoreDefaults: String { t("デフォルトに戻す", "Restore Defaults") }
    static var previewLabel: String { t("外観のプレビュー", "Appearance preview") }
    static var previewMenus: [String] {
        isJapanese ? ["Finder", "ファイル", "編集", "表示"] : ["Finder", "File", "Edit", "View"]
    }
}
