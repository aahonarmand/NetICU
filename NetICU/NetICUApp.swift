import SwiftUI
import AppKit

@main
struct NetICUApp: App {
    @StateObject private var vm = MonitorViewModel()
    @StateObject private var loc = Localizer()

    var body: some Scene {
        // Main window
        Window("NetICU", id: "main") {
            ContentView()
                .environmentObject(vm)
                .environmentObject(loc)
                .frame(minWidth: 880, minHeight: 580)
        }
        .windowResizability(.contentMinSize)

        // Settings
        Settings {
            SettingsView()
                .environmentObject(vm)
                .environmentObject(loc)
        }

        // Menu-bar icon
        MenuBarExtra {
            MenuBarView()
                .environmentObject(vm)
                .environmentObject(loc)
        } label: {
            MenuBarGauge(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar gauge: two stacked ping numbers, each tracking a chosen monitor.
/// Its width is fixed so it never triggers a menu-bar relayout (which can crash).
struct MenuBarGauge: View {
    @ObservedObject var vm: MonitorViewModel
    // @AppStorage (not a raw UserDefaults read) so the view also updates when only
    // the setting changes, not just when the view model publishes.
    @AppStorage(DefaultsKey.menuBarTopID) private var topSel: String = "auto"
    @AppStorage(DefaultsKey.menuBarBottomID) private var botSel: String = "auto"

    var body: some View {
        // Each number is the ping of one selected monitor (top and bottom independent).
        Image(nsImage: MenuBarGauge.render(top: vm.menuBarStats(for: topSel),
                                           bottom: vm.menuBarStats(for: botSel)))
            .help("NetICU")
    }

    /// Two ping numbers stacked — one per monitor, each colored by its own status.
    static func render(top topStats: TargetStatistics?, bottom bottomStats: TargetStatistics?) -> NSImage {
        let size = NSSize(width: 30, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()
        drawLine(topStats, atTop: true, in: size)
        drawLine(bottomStats, atTop: false, in: size)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawLine(_ st: TargetStatistics?, atTop: Bool, in size: NSSize) {
        let hasData = (st?.sampleCount ?? 0) > 0
        let text: String
        let color: NSColor
        if hasData, let st, let ping = st.current {
            text = "\(Int(ping))"
            color = NSColor(Theme.quality(StatisticsCalculator.latencySubScore(ping)))
        } else if hasData {
            text = "—"; color = NSColor.systemRed   // no reply
        } else {
            text = "—"; color = .gray
        }
        let font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let ns = text as NSString
        let ts = ns.size(withAttributes: attrs)
        ns.draw(at: NSPoint(x: (size.width - ts.width) / 2, y: atTop ? 10 : -1), withAttributes: attrs)
    }
}

/// Settings window.
struct SettingsView: View {
    @EnvironmentObject var vm: MonitorViewModel
    @EnvironmentObject var loc: Localizer

    // Threshold calibration (for the score and the menu-bar colors)
    @AppStorage(DefaultsKey.latencyBest)  private var latBest: Double = Calibration.defaultLatBest
    @AppStorage(DefaultsKey.latencyWorst) private var latWorst: Double = Calibration.defaultLatWorst
    @AppStorage(DefaultsKey.lossWorst)    private var lossWorst: Double = Calibration.defaultLossWorst
    // Score-formula weights
    @AppStorage(DefaultsKey.weightLatency) private var wLat: Double = Calibration.defaultWLat
    @AppStorage(DefaultsKey.weightJitter)  private var wJit: Double = Calibration.defaultWJit
    @AppStorage(DefaultsKey.weightLoss)    private var wLoss: Double = Calibration.defaultWLoss
    // Reference monitor for each menu-bar number (top and bottom independent)
    @AppStorage(DefaultsKey.menuBarTopID)    private var menuBarTopID: String = "auto"
    @AppStorage(DefaultsKey.menuBarBottomID) private var menuBarBottomID: String = "auto"

    var body: some View {
        Form {
            Section(loc.t("interval")) {
                Slider(value: $vm.intervalSeconds, in: 0.5...10, step: 0.5) {
                    Text(loc.t("interval"))
                } minimumValueLabel: {
                    Text(loc.n1(0.5))
                } maximumValueLabel: {
                    Text(loc.int(10))
                }
                Text("\(loc.n1(vm.intervalSeconds)) \(loc.t("seconds"))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(loc.t("auto_refresh_ip"), isOn: $vm.autoRefreshIP)
                Text(loc.t("ip_privacy_help")).font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text(loc.t("public_ip"))
            }

            Section {
                Picker(loc.t("menubar_top"), selection: $menuBarTopID) {
                    Text(loc.t("menubar_auto")).tag("auto")
                    ForEach(vm.targets) { t in Text(t.name).tag(t.id.uuidString) }
                }
                Picker(loc.t("menubar_bottom"), selection: $menuBarBottomID) {
                    Text(loc.t("menubar_auto")).tag("auto")
                    ForEach(vm.targets) { t in Text(t.name).tag(t.id.uuidString) }
                }
                Text(loc.t("menubar_help")).font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text(loc.t("menubar_section"))
            }

            Section {
                calibRow(loc.t("calib_excellent"), value: $latBest, range: 5...300, step: 5, unit: loc.t("ms"))
                calibRow(loc.t("calib_bad"), value: $latWorst, range: 100...2000, step: 25, unit: loc.t("ms"))
                calibRow(loc.t("calib_loss"), value: $lossWorst, range: 1...50, step: 1, unit: "%")
                Button(loc.t("calib_reset")) {
                    latBest = Calibration.defaultLatBest
                    latWorst = Calibration.defaultLatWorst
                    lossWorst = Calibration.defaultLossWorst
                }
                Text(loc.t("calib_help")).font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text(loc.t("calibration"))
            }

            Section {
                let total = max(1, wLat + wJit + wLoss)
                calibRow("\(loc.t("ping")) \(weightPct(wLat, total))", value: $wLat, range: 0...100, step: 5, unit: "%")
                calibRow("\(loc.t("jitter")) \(weightPct(wJit, total))", value: $wJit, range: 0...100, step: 5, unit: "%")
                calibRow("\(loc.t("loss")) \(weightPct(wLoss, total))", value: $wLoss, range: 0...100, step: 5, unit: "%")
                Button(loc.t("calib_reset")) {
                    wLat = Calibration.defaultWLat
                    wJit = Calibration.defaultWJit
                    wLoss = Calibration.defaultWLoss
                }
                Text(loc.t("weights_help")).font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text(loc.t("score_formula"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 700)
    }

    private func weightPct(_ w: Double, _ total: Double) -> String {
        "(\(Int((w / total * 100).rounded()))%)"
    }

    private func calibRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                          step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .foregroundStyle(Theme.accent).font(.callout.monospacedDigit())
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
