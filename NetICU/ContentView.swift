import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case dashboard
    case target(UUID)
}

/// Main window: sidebar (dashboard + monitors) and the detail pane.
struct ContentView: View {
    @EnvironmentObject var vm: MonitorViewModel
    @EnvironmentObject var loc: Localizer
    @State private var selection: SidebarItem? = .dashboard
    @State private var showAddSheet = false
    @State private var editingTarget: PingTarget?
    @State private var showAbout = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 270)
        } detail: {
            detail
                .background(Theme.bg)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, loc.isRTL ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showAddSheet) {
            AddTargetView { target in
                vm.addTarget(target)
                selection = .target(target.id)
            }
        }
        .sheet(item: $editingTarget) { target in
            AddTargetView(existing: target) { updated in vm.updateTarget(updated) }
        }
        .sheet(isPresented: $showAbout) {
            AboutView().environmentObject(loc)
        }
        .task {
            // Start monitoring in a separate task, after the current layout pass,
            // so a state change during layout can't cause a recursive
            // Update Constraints crash.
            if !vm.isMonitoring { vm.start() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            brandHeader
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8))
                .listRowBackground(Color.clear)

            Label(loc.t("dashboard"), systemImage: "square.grid.2x2.fill")
                .tag(SidebarItem.dashboard)

            Section(loc.t("monitors")) {
                ForEach(vm.sortedTargets) { target in
                    TargetRow(target: target, stats: vm.statistics(for: target))
                        .tag(SidebarItem.target(target.id))
                        .contextMenu {
                            Button(loc.t("edit")) { editingTarget = target }
                            Button(loc.t("delete"), role: .destructive) { vm.removeTarget(target) }
                        }
                }
                .onMove { source, destination in
                    vm.moveTargets(from: source, to: destination)
                }
            }

            Section {
                Button { showAbout = true } label: {
                    Label("\(loc.t("about")) NetICU", systemImage: "info.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgElevated)
        .toolbar {
            ToolbarItem {
                Button { showAddSheet = true } label: {
                    Label(loc.t("add_monitor"), systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { vm.isMonitoring ? vm.stop() : vm.start() } label: {
                    Label(vm.isMonitoring ? loc.t("stop") : loc.t("start"),
                          systemImage: vm.isMonitoring ? "pause.fill" : "play.fill")
                }
            }
            ToolbarItem {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            vm.sortOrder = order
                        } label: {
                            if vm.sortOrder == order {
                                Label(sortLabel(order), systemImage: "checkmark")
                            } else {
                                Text(sortLabel(order))
                            }
                        }
                    }
                } label: {
                    Label(loc.t("sort"), systemImage: "arrow.up.arrow.down")
                }
                .help(loc.t("sort"))
            }
            ToolbarItem {
                Button { showAbout = true } label: {
                    Label(loc.t("about"), systemImage: "info.circle")
                }
                .help(loc.t("about"))
            }
        }
    }

    private func sortLabel(_ order: SortOrder) -> String {
        switch order {
        case .manual:  return loc.t("sort_manual")
        case .name:    return loc.t("sort_name")
        case .ping:    return loc.t("sort_ping")
        case .quality: return loc.t("sort_quality")
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text("NetICU").font(.system(size: 17, weight: .bold))
                Text(loc.t("tagline"))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .dashboard, .none:
            DashboardView(onSelect: { id in selection = .target(id) })
        case .target(let id):
            if let target = vm.targets.first(where: { $0.id == id }) {
                TargetDetailView(target: target).id(target.id)
            } else {
                DashboardView(onSelect: { id in selection = .target(id) })
            }
        }
    }
}

// MARK: - Monitor row in the sidebar

struct TargetRow: View {
    @EnvironmentObject var loc: Localizer
    let target: PingTarget
    let stats: TargetStatistics

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: stats.sampleCount > 0 ? stats.color : Theme.qGray)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.body)
                Text(target.displayHost)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(loc.n0(stats.current)) \(loc.t("ms"))")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(stats.sampleCount > 0 ? stats.color : Theme.textSecondary)
        }
        .padding(.vertical, 2)
        .opacity(target.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Monitor detail view

struct TargetDetailView: View {
    @EnvironmentObject var vm: MonitorViewModel
    @EnvironmentObject var loc: Localizer
    let target: PingTarget
    @State private var showBreakdownHelp = false
    @State private var showClearConfirm = false
    @State private var logsExpanded = false

    private var stats: TargetStatistics { vm.statistics(for: target) }
    private var samples: [PingSample] { vm.history(for: target) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    StatCard(title: loc.t("ping"),    value: loc.n0(stats.current), unit: loc.t("ms"), color: stats.color, help: loc.t("current_help"))
                    StatCard(title: loc.t("average"), value: loc.n0(stats.average), unit: loc.t("ms"), help: loc.t("average_help"))
                    StatCard(title: loc.t("jitter"),  value: loc.n1(stats.jitter),  unit: loc.t("ms"), color: Theme.accent, help: loc.t("jitter_help"))
                    StatCard(title: loc.t("loss"),    value: loc.pct(stats.lossPercent), unit: "",
                             color: stats.lossPercent > 1 ? Theme.qOrange : Theme.textPrimary, help: loc.t("loss_help"))
                }
                HStack(spacing: 12) {
                    StatCard(title: loc.t("min"), value: loc.n0(stats.minimum), unit: loc.t("ms"), help: loc.t("min_help"))
                    StatCard(title: loc.t("max"), value: loc.n0(stats.maximum), unit: loc.t("ms"), help: loc.t("max_help"))
                    StatCard(title: loc.t("p95"), value: loc.n0(stats.p95), unit: loc.t("ms"),
                             color: Theme.qYellow, help: loc.t("p95_help"))
                    StatCard(title: loc.t("samples"), value: loc.int(stats.sampleCount), unit: "", help: loc.t("samples_help"))
                }

                chartCard(title: loc.t("ping_trend"),
                          chart: TrendChart(points: samples.pingPoints, color: Theme.accent, markLoss: true))
                chartCard(title: loc.t("jitter_trend"),
                          chart: TrendChart(points: samples.jitterPoints, color: Theme.qYellow))

                if let bd = vm.breakdown(for: target), bd.hasAny {
                    breakdownCard(bd)
                }

                logsCard
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle(target.name)
        .navigationSubtitle(target.displayHost)
    }

    private var logsCard: some View {
        let logs = Array(samples.suffix(100).reversed())
        return DisclosureGroup(isExpanded: $logsExpanded) {
            VStack(spacing: 0) {
                ForEach(logs) { s in
                    HStack {
                        Text(s.date.formatted(.dateTime.hour().minute().second()))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(s.rttMs != nil ? "\(Int(s.rttMs!)) \(loc.t("ms"))" : loc.t("logs_timeout"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(s.rttMs != nil ? Theme.textPrimary : Theme.qRed)
                    }
                    .padding(.vertical, 5)
                    if s.id != logs.last?.id { Divider().opacity(0.25) }
                }
                if logs.isEmpty {
                    Text(loc.t("collecting")).font(.caption).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("\(loc.t("recent_logs")) (\(logs.count))").font(.headline)
        }
        .tint(Theme.accent)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ScoreBadge(stats: stats)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(target.name).font(.title2).bold()
                    Button { showClearConfirm = true } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.t("clear_history"))
                    .confirmationDialog(loc.t("clear_history_confirm"),
                                        isPresented: $showClearConfirm, titleVisibility: .visible) {
                        Button(loc.t("clear"), role: .destructive) { vm.clearHistory(for: target) }
                        Button(loc.t("cancel"), role: .cancel) {}
                    }
                }
                Text(target.displayHost).font(.callout).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    if let proxy = target.proxy, proxy.isValid {
                        Label("\(loc.t("via_proxy")): \(proxy.display)", systemImage: "shield.lefthalf.filled")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                    }
                    if let alert = target.alert {
                        Label("\(loc.t("alert_on")): >\(Int(alert.pingThresholdMs))ms · \(Int(alert.durationSeconds))s",
                              systemImage: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.qYellow)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.qYellow.opacity(0.14), in: Capsule())
                    }
                }
            }
            Spacer()
            Button {
                var t = target; t.isEnabled.toggle(); vm.updateTarget(t)
            } label: {
                Label(target.isEnabled ? loc.t("enabled") : loc.t("disabled"),
                      systemImage: target.isEnabled ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func chartCard<C: View>(title: String, chart: C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            chart
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
    }

    private func breakdownCard(_ bd: PingBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(loc.t("timing_breakdown")).font(.headline)
                Button { showBreakdownHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showBreakdownHelp) {
                    Text(loc.t("breakdown_help"))
                        .font(.callout).foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14).frame(width: 320)
                }
                Spacer()
                diagnosisBadge(bd)
            }
            HStack(spacing: 12) {
                StatCard(title: loc.t("dns"),  value: loc.n0(bd.dnsMs),  unit: loc.t("ms"), help: loc.t("dns_help"))
                StatCard(title: "TCP",         value: loc.n0(bd.tcpMs),  unit: loc.t("ms"), help: loc.t("tcp_help"))
                StatCard(title: "TLS",         value: loc.n0(bd.tlsMs),  unit: loc.t("ms"), help: loc.t("tls_help"))
                StatCard(title: loc.t("ttfb"), value: loc.n0(bd.ttfbMs), unit: loc.t("ms"), color: Theme.accent, help: loc.t("ttfb_help"))
            }
            Text(loc.t("breakdown_note"))
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder
    private func diagnosisBadge(_ bd: PingBreakdown) -> some View {
        switch bd.bottleneck {
        case .server:  badge(loc.t("diag_server"),  Theme.qOrange)
        case .network: badge(loc.t("diag_network"), Theme.qYellow)
        case .dns:     badge(loc.t("diag_dns"),     Theme.accent)
        case .none:    EmptyView()
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}
