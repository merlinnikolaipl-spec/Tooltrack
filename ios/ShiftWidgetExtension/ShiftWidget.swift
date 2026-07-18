import WidgetKit
import SwiftUI

struct ShiftEntry: TimelineEntry {
      let date: Date
      let shiftActive: Bool
      let siteName: String
      let startMillis: Double
}

struct ShiftProvider: TimelineProvider {
      let appGroupId = "group.com.toolkeeper.app.widget"

      func placeholder(in context: Context) -> ShiftEntry {
                ShiftEntry(date: Date(), shiftActive: false, siteName: "", startMillis: 0)
      }

      func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
                completion(loadEntry())
      }

      func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
                let entry = loadEntry()
                let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
                completion(timeline)
      }

      private func loadEntry() -> ShiftEntry {
                let defaults = UserDefaults(suiteName: appGroupId)
                let active = defaults?.bool(forKey: "shiftActive") ?? false
                let site = defaults?.string(forKey: "shiftSiteName") ?? ""
                let millis = defaults?.double(forKey: "shiftStartMillis") ?? 0
                return ShiftEntry(date: Date(), shiftActive: active, siteName: site, startMillis: millis)
      }
}

struct ShiftWidgetEntryView: View {
      var entry: ShiftProvider.Entry

      private var elapsedText: String {
                guard entry.shiftActive, entry.startMillis > 0 else { return "" }
                let start = Date(timeIntervalSince1970: entry.startMillis / 1000)
                let interval = Date().timeIntervalSince(start)
                let hours = Int(interval) / 3600
                let minutes = (Int(interval) % 3600) / 60
                return String(format: "%02d:%02d", hours, minutes)
      }

      var body: some View {
                VStack(alignment: .leading, spacing: 6) {
                              Text(entry.shiftActive ? "Shift Active" : "No Active Shift")
                                  .font(.headline)
                              if entry.shiftActive {
                                                Text(entry.siteName.isEmpty ? "Unknown site" : entry.siteName)
                                                    .font(.subheadline)
                                                Text(elapsedText)
                                                    .font(.title2)
                                                    .monospacedDigit()
                                                Link(destination: URL(string: "toolkeeperwidget://end")!) {
                                                                      Text("End Shift")
                                                                          .font(.caption).bold()
                                                }
                              } else {
                                                Link(destination: URL(string: "toolkeeperwidget://start")!) {
                                                                      Text("Start Shift")
                                                                          .font(.caption).bold()
                                                }
                              }
                }
                .padding()
      }
}

struct ShiftWidget: Widget {
      let kind: String = "ShiftWidget"

      var body: some WidgetConfiguration {
                StaticConfiguration(kind: kind, provider: ShiftProvider()) { entry in
                                                                                        ShiftWidgetEntryView(entry: entry)
                                                                           }
                .configurationDisplayName("Shift Tracker")
                .description("Shows your current shift status.")
                .supportedFamilies([.systemSmall, .systemMedium])
      }
}

@main
struct ShiftWidgetBundle: WidgetBundle {
      var body: some Widget {
                ShiftWidget()
      }
}
