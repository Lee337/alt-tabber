import SwiftUI

struct SurfaceAppearance: Codable, Equatable {
    var showHeader = true
    var iconOnly = false
    var iconSize = 24.0
    var titleVisibility = ContentVisibility.always
    var titleAbovePreview = false
    var titleFontSize = 12.0
    var titleOverflow = TitleOverflow.tail
    var controlsVisibility = ContentVisibility.hover
    var controlsAtTop = true
    var controlsOnRight = false
    var enabledActions: [WindowAction] = [.close, .minimize, .fullscreen, .quit]
    var monochromeControls = false
    var controlScale = 1.0
    var embedControls = true
    var statusBadges = true
    var spaceBadges = false
    var hideCardBackground = false
    var hideContainerBackground = false
    var opaqueBackground = false
    var backgroundHex = "18202C"
    var highlightHex = "007AFF"
    var selectedOpacity = 0.15
    var unselectedOpacity = 0.75
    var showShadow = true
    var shadowRadius = 20.0
    var shadowOpacity = 0.3
    var gradientEnabled = false
    var gradientStartHex = "007AFF"
    var gradientEndHex = "AA66FF"
    var gradientSpeed = 1.0
    var gradientBlur = 8.0
    var appearance = AppAppearance.system
    var glassSaturation = 1.0
    var glassBlur = 0.0
    var borderOpacity = 0.15
    var borderWidth = 1.0
    var maxRows = 8
    var maxColumns = 4
    var itemHeight = 56.0
    var compactAppAndTitle = true
    var compactHideControls = false
    mutating func normalize() {
        maxRows = min(12, max(1, maxRows)); maxColumns = min(8, max(1, maxColumns))
        iconSize = min(64, max(12, iconSize)); titleFontSize = min(24, max(9, titleFontSize))
        selectedOpacity = min(1, max(0, selectedOpacity)); unselectedOpacity = min(1, max(0.1, unselectedOpacity))
        controlScale = min(1.5, max(0.5, controlScale))
        itemHeight = min(90, max(32, itemHeight))
        enabledActions = Array(Set(enabledActions)).sorted { $0.rawValue < $1.rawValue }
    }
}
enum ContentVisibility: String, Codable, CaseIterable { case always, hover, dimmed, never }
enum TitleOverflow: String, Codable, CaseIterable { case head, middle, tail, marquee }
enum AppAppearance: String, Codable, CaseIterable { case system, light, dark }
extension FeatureSettings {
    func style(for surface: PresentationSurface) -> SurfaceAppearance {
        switch surface { case .switcher: switcherStyle; case .dock: dockStyle; case .commandTab: commandTabStyle }
    }
}
extension Color {
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x007AFF
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
struct SurfaceStyleEditor: View {
    @Binding var style: SurfaceAppearance
    var body: some View {
        Section("Titles and Controls") {
            Toggle("Show app header", isOn: $style.showHeader).id("Show app header")
            Toggle("Use app icon only", isOn: $style.iconOnly).id("Use app icon only")
            SliderRow(title: "App icon size", value: $style.iconSize, range: 12...64)
            Picker("Title visibility", selection: $style.titleVisibility) { ForEach(ContentVisibility.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.id("Title visibility")
            Toggle("Title above preview", isOn: $style.titleAbovePreview).id("Title above preview")
            SliderRow(title: "Title font size", value: $style.titleFontSize, range: 9...24)
            Picker("Title overflow", selection: $style.titleOverflow) { ForEach(TitleOverflow.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.id("Title overflow")
            Picker("Control visibility", selection: $style.controlsVisibility) { ForEach(ContentVisibility.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.id("Control visibility")
            Toggle("Controls at top", isOn: $style.controlsAtTop).id("Controls at top")
            Toggle("Controls on right", isOn: $style.controlsOnRight).id("Controls on right")
            Toggle("Embed controls in previews", isOn: $style.embedControls).id("Embed controls in previews")
            Toggle("Monochrome controls", isOn: $style.monochromeControls).id("Monochrome controls")
            SliderRow(title: "Control scale", value: $style.controlScale, range: 0.5...1.5)
            ForEach([WindowAction.close, .minimize, .fullscreen, .quit], id: \.self) { action in
                Toggle(action.title + " button", isOn: Binding(get: { style.enabledActions.contains(action) }, set: { enabled in
                    style.enabledActions.removeAll { $0 == action }; if enabled { style.enabledActions.append(action) }
                }))
            }
            Toggle("Show minimized and hidden badges", isOn: $style.statusBadges).id("Show minimized and hidden badges")
            Toggle("Show Space badges", isOn: $style.spaceBadges).id("Show Space badges")
        }
        Section("Colors and Effects") {
            Picker("Appearance", selection: $style.appearance) { ForEach(AppAppearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.id("Appearance")
            HexColorPicker(title: "Highlight color", hex: $style.highlightHex)
            HexColorPicker(title: "Background color", hex: $style.backgroundHex)
            Toggle("Opaque background", isOn: $style.opaqueBackground).id("Opaque background")
            Toggle("Hide card backgrounds", isOn: $style.hideCardBackground).id("Hide card backgrounds")
            Toggle("Hide container background", isOn: $style.hideContainerBackground).id("Hide container background")
            SliderRow(title: "Selection opacity", value: $style.selectedOpacity, range: 0...1)
            SliderRow(title: "Unselected content opacity", value: $style.unselectedOpacity, range: 0.1...1)
            Toggle("Show shadow", isOn: $style.showShadow).id("Show shadow")
            SliderRow(title: "Shadow radius", value: $style.shadowRadius, range: 0...40)
            SliderRow(title: "Shadow opacity", value: $style.shadowOpacity, range: 0...1)
            Toggle("Animated highlight gradient", isOn: $style.gradientEnabled).id("Animated highlight gradient")
            HexColorPicker(title: "Gradient start", hex: $style.gradientStartHex)
            HexColorPicker(title: "Gradient end", hex: $style.gradientEndHex)
            SliderRow(title: "Gradient speed", value: $style.gradientSpeed, range: 0.1...3)
            SliderRow(title: "Gradient blur", value: $style.gradientBlur, range: 0...30)
            SliderRow(title: "Glass saturation", value: $style.glassSaturation, range: 0...3)
            SliderRow(title: "Glass blur", value: $style.glassBlur, range: 0...20)
            SliderRow(title: "Border opacity", value: $style.borderOpacity, range: 0...1)
            SliderRow(title: "Border width", value: $style.borderWidth, range: 0...4)
        }
        Section("Sizing and Compact Lists") {
            Stepper("Maximum visible rows: \(style.maxRows)", value: $style.maxRows, in: 1...12)
            Stepper("Maximum columns: \(style.maxColumns)", value: $style.maxColumns, in: 1...8)
            SliderRow(title: "Compact row height", value: $style.itemHeight, range: 32...90)
            Toggle("Compact app and window title", isOn: $style.compactAppAndTitle).id("Compact app and window title")
            Toggle("Hide controls in compact mode", isOn: $style.compactHideControls).id("Hide controls in compact mode")
        }
    }
}
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(value, format: .number.precision(.fractionLength(0...2))).foregroundStyle(.secondary) }
            Slider(value: $value, in: range).accessibilityLabel(title)
        }.id(title)
    }
}
struct HexColorPicker: View {
    let title: String
    @Binding var hex: String
    var body: some View {
        ColorPicker(title, selection: Binding(get: { Color(hex: hex) }, set: { color in
            if let rgb = NSColor(color).usingColorSpace(.sRGB) {
                hex = String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
            }
        }), supportsOpacity: false).id(title)
    }
}
