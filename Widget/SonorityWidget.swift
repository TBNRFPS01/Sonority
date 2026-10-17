import WidgetKit
import SwiftUI

struct Entry: TimelineEntry { let date: Date }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) { completion(Timeline(entries: [Entry(date: Date())], policy: .never)) }
}

@main
struct SonorityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SonorityQuickAccess", provider: Provider()) { _ in
            VStack(alignment: .leading, spacing: 14) {
                Label("sonority", systemImage: "waveform.path").font(.system(.title2, design: .serif))
                Text("A little room for sound.").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    Link(destination: URL(string: "sonority://playing")!) { Label("Listen", systemImage: "play.fill") }
                    Link(destination: URL(string: "sonority://import")!) { Label("Import", systemImage: "plus") }
                }.font(.caption.weight(.semibold))
            }.foregroundStyle(Color(red: 0.72, green: 0.89, blue: 0.72))
                .containerBackground(for: .widget) { Color(red: 0.045, green: 0.09, blue: 0.065) }
                .widgetURL(URL(string: "sonority://library"))
        }.configurationDisplayName("A moment of Sonority").description("Open your player or bring in new music.").supportedFamilies([.systemMedium])
    }
}
