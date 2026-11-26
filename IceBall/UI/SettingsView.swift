import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionState
    let previewMetrics: PreviewMetrics
    /// Sparkle lives in the app target; the view only asks for the check.
    let checkForUpdates: () -> Void

    var body: some View {
        Form {
            Section {
                AppearancePreview(configuration: settings.configuration, metrics: previewMetrics)
                    .frame(height: 76)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Toggle(L.enableAppearance, isOn: $settings.isEnabled)
                Toggle(
                    L.launchAtLogin,
                    isOn: Binding(
                        get: { settings.launchesAtLogin },
                        set: { settings.setLaunchesAtLogin($0) }
                    ))
                if settings.loginItemStatus == .requiresApproval {
                    LabeledContent(L.loginItemNeedsApproval) {
                        Button(L.open) { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = settings.loginItemError {
                    Text(error).foregroundStyle(.secondary).font(.callout)
                }
            }

            Section(L.shape) {
                Picker(L.shape, selection: $settings.configuration.shape) {
                    ForEach(MenuBarShape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settings.configuration.shape == .split && !permissions.isAccessibilityTrusted {
                    LabeledContent {
                        Button(L.allow) { permissions.request() }
                    } label: {
                        Text(L.splitNeedsAccessibility)
                            .font(.callout)
                    }
                }
            }

            if settings.configuration.shape != .standard && permissions.needsDesktopPicture
                && !permissions.hasScreenCapturePermission
            {
                Section {
                    LabeledContent {
                        Button(L.allow) { permissions.requestScreenCapture() }
                    } label: {
                        Text(L.needsScreenRecording)
                            .font(.callout)
                    }
                }
            }

            Section(L.shapeAndMargins) {
                slider(
                    L.cornerRadius, value: $settings.configuration.cornerRadius,
                    in: AppearanceConfiguration.cornerRadiusRange)
                slider(
                    L.horizontalMargin, value: $settings.configuration.horizontalMargin,
                    in: AppearanceConfiguration.horizontalMarginRange)
                slider(
                    L.verticalMargin, value: $settings.configuration.verticalMargin,
                    in: AppearanceConfiguration.verticalMarginRange)
            }
            .disabled(settings.configuration.shape == .standard)

            Section(L.background) {
                Toggle(L.colorFromDesktopPicture, isOn: $settings.configuration.colorFromDesktopPicture)
                Group {
                    ColorPicker(L.lightBackground, selection: colorBinding(\.lightBackground), supportsOpacity: false)
                    ColorPicker(L.darkBackground, selection: colorBinding(\.darkBackground), supportsOpacity: false)
                }
                .disabled(settings.configuration.colorFromDesktopPicture)
                slider(L.opacity, value: $settings.configuration.backgroundOpacity, in: 0...1, format: .percent)
            }
            .disabled(settings.configuration.shape == .standard)

            Section(L.borderAndShadow) {
                ColorPicker(L.borderColor, selection: colorBinding(\.borderColor), supportsOpacity: true)
                slider(
                    L.borderWidth, value: $settings.configuration.borderWidth,
                    in: AppearanceConfiguration.borderWidthRange, step: 0.5)
                Toggle(L.dropShadow, isOn: $settings.configuration.shadowEnabled)
                slider(
                    L.shadowRadius, value: $settings.configuration.shadowRadius,
                    in: AppearanceConfiguration.shadowRadiusRange
                )
                .disabled(!settings.configuration.shadowEnabled)
            }
            .disabled(settings.configuration.shape == .standard)

            Section {
                HStack {
                    Button(L.checkForUpdates, action: checkForUpdates)
                    Spacer()
                    Button(L.restoreDefaults) { settings.resetToDefaults() }
                    Button(L.quit) { NSApp.terminate(nil) }
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
                Text(
                    format == .percent
                        ? value.wrappedValue.formatted(.percent.precision(.fractionLength(0)))
                        : "\(value.wrappedValue.formatted(.number.precision(.fractionLength(0...1)))) pt"
                )
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
