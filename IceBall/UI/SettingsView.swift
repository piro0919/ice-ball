import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionState
    let previewMetrics: PreviewMetrics

    var body: some View {
        Form {
            Section {
                AppearancePreview(configuration: settings.configuration, metrics: previewMetrics)
                    .frame(height: 76)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Toggle("外観の変更を有効にする", isOn: $settings.isEnabled)
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { settings.launchesAtLogin },
                    set: { settings.setLaunchesAtLogin($0) }
                ))
                if settings.loginItemStatus == .requiresApproval {
                    LabeledContent("システム設定の「ログイン項目」で許可が必要です") {
                        Button("開く") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = settings.loginItemError {
                    Text(error).foregroundStyle(.secondary).font(.callout)
                }
            }

            Section("形状") {
                Picker("形状", selection: $settings.configuration.shape) {
                    ForEach(MenuBarShape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settings.configuration.shape == .split && !permissions.isAccessibilityTrusted {
                    LabeledContent {
                        Button("許可する") { permissions.request() }
                    } label: {
                        Text("Split はメニューとステータスアイコンの位置を読むため、アクセシビリティの許可が必要です。許可されるまでは Rounded と同じ形で表示します。")
                            .font(.callout)
                    }
                }
            }

            if settings.configuration.shape != .standard && permissions.needsDesktopPicture && !permissions.hasScreenCapturePermission {
                Section {
                    LabeledContent {
                        Button("許可する") { permissions.requestScreenCapture() }
                    } label: {
                        Text("「メニューバーの背景を表示」がオンのため、形の外側を壁紙で塗ります。壁紙の画像ファイルを読めないときは画面収録の許可が要ります。許可したあとは Ice Ball を再起動してください。")
                            .font(.callout)
                    }
                }
            }

            Section("形と余白") {
                slider("角丸の半径", value: $settings.configuration.cornerRadius, in: AppearanceConfiguration.cornerRadiusRange)
                slider("左右の余白", value: $settings.configuration.horizontalMargin, in: AppearanceConfiguration.horizontalMarginRange)
                slider("上下の余白", value: $settings.configuration.verticalMargin, in: AppearanceConfiguration.verticalMarginRange)
            }
            .disabled(settings.configuration.shape == .standard)

            Section("背景") {
                ColorPicker("背景色（ライト）", selection: colorBinding(\.lightBackground), supportsOpacity: false)
                ColorPicker("背景色（ダーク）", selection: colorBinding(\.darkBackground), supportsOpacity: false)
                slider("透明度", value: $settings.configuration.backgroundOpacity, in: 0...1, format: .percent)
            }
            .disabled(settings.configuration.shape == .standard)

            Section("境界線と影") {
                ColorPicker("境界線の色", selection: colorBinding(\.borderColor), supportsOpacity: true)
                slider("境界線の太さ", value: $settings.configuration.borderWidth, in: AppearanceConfiguration.borderWidthRange, step: 0.5)
                Toggle("ドロップシャドウ", isOn: $settings.configuration.shadowEnabled)
                slider("影の広がり", value: $settings.configuration.shadowRadius, in: AppearanceConfiguration.shadowRadiusRange)
                    .disabled(!settings.configuration.shadowEnabled)
            }
            .disabled(settings.configuration.shape == .standard)

            Section {
                HStack {
                    Spacer()
                    Button("デフォルトに戻す") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum ValueFormat { case points, percent }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 1,
        format: ValueFormat = .points
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: format == .percent ? 0.01 : step)
                Text(format == .percent ? value.wrappedValue.formatted(.percent.precision(.fractionLength(0))) : "\(value.wrappedValue.formatted(.number.precision(.fractionLength(0...1)))) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<AppearanceConfiguration, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.configuration[keyPath: keyPath].nsColor) },
            set: { settings.configuration[keyPath: keyPath] = RGBAColor(NSColor($0)) }
        )
    }
}
