import SwiftUI
import AppKit

/// محتوای popover نوار منو: خلاصه‌ی همه‌ی مانیتورها + آی‌پی.
struct MenuBarView: View {
    @EnvironmentObject var vm: MonitorViewModel
    @EnvironmentObject var loc: Localizer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if vm.targets.isEmpty {
                Text(loc.t("no_monitors"))
                    .font(.callout).foregroundStyle(.secondary).padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.targets) { target in
                        MenuBarRow(target: target, stats: vm.statistics(for: target))
                        if target.id != vm.targets.last?.id { Divider().padding(.leading, 12) }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()
            ipStrip
            Divider()
            footer
        }
        .frame(width: 290)
        .environment(\.layoutDirection, loc.isRTL ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cross.case.fill").foregroundStyle(Theme.accent)
            Text("NetICU").font(.headline)
            Spacer()
            Circle().fill(vm.isMonitoring ? Theme.qGreen : Theme.qGray).frame(width: 8, height: 8)
            Text(vm.isMonitoring ? loc.t("monitoring") : loc.t("stopped"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }

    private var ipStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "network").font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(loc.t("public_ip")).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(vm.publicIP ?? "…")
                .font(.system(.caption, design: .monospaced))
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Label(loc.t("open_window"), systemImage: "macwindow") }
            .buttonStyle(.borderless)

            Spacer()

            Button { vm.isMonitoring ? vm.stop() : vm.start() } label: {
                Image(systemName: vm.isMonitoring ? "pause.circle" : "play.circle")
            }
            .buttonStyle(.borderless)

            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
            .buttonStyle(.borderless).help(loc.t("quit"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct MenuBarRow: View {
    @EnvironmentObject var loc: Localizer
    let target: PingTarget
    let stats: TargetStatistics

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: stats.sampleCount > 0 ? stats.color : Theme.qGray)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.name).font(.callout)
                Text(target.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(loc.n0(stats.current)) \(loc.t("ms"))")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(stats.sampleCount > 0 ? stats.color : .secondary)
                Text("\(loc.t("jitter")) \(loc.n1(stats.jitter))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .opacity(target.isEnabled ? 1 : 0.45)
    }
}
