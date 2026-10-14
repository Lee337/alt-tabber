import SwiftUI

struct EmbeddedWidgetView: View {
    @ObservedObject var switcher: SwitcherModel
    @ObservedObject var settings: AppSettings
    let calendar: CalendarWidgetModel?
    let media: MediaWidgetModel?
    var body: some View {
        HStack(spacing: 12) {
            SwitcherView(model: switcher, settings: settings).frame(minWidth: 420)
            VStack {
                if let calendar { CalendarWidgetView(model: calendar) }
                if let media { MediaWidgetView(model: media, settings: settings) }
            }.padding(12).frame(width: 320)
        }.background(.regularMaterial)
    }
}
