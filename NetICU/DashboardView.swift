import SwiftUI

/// داشبورد: نمای کلی همه‌ی مانیتورها + آی‌پی کاربر.
struct DashboardView: View {
    @EnvironmentObject var vm: MonitorViewModel
    @EnvironmentObject var loc: Localizer
    var onSelect: (UUID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topRow
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(vm.sortedTargets) { target in
                        DashboardCard(target: target, stats: vm.statistics(for: target),
                                      samples: vm.history(for: target))
                            .onTapGesture { onSelect(target.id) }
                    }
                }
                if vm.targets.isEmpty {
                    Text(loc.t("no_monitors"))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle(loc.t("dashboard"))
    }

    // MARK: - ردیف بالا: آی‌پی + خلاصه

    private var topRow: some View {
        let summary = overallSummary
        return HStack(alignment: .top, spacing: 14) {
            connectionCard
            summaryCard(summary)
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe").foregroundStyle(Theme.accent)
                Text(loc.t("your_connection")).font(.headline)
                Spacer()
                Button { Task { await vm.refreshIP() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(loc.t("refresh_ip"))
            }
            ipRow(label: loc.t("public_ip"), value: vm.publicIP, icon: "network")
            ipRow(label: loc.t("local_ip"),  value: vm.localIP,  icon: "house")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
    }

    private func ipRow(label: String, value: String?, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 16)
            Text(label).font(.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value ?? "…")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func summaryCard(_ s: Summary) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(loc.int(s.avgScore))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.quality(s.avgScore))
                Text(loc.t("avg_score")).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Divider().frame(height: 44)
            VStack(alignment: .leading, spacing: 6) {
                miniStat(loc.t("active"), "\(loc.int(s.active))/\(loc.int(vm.targets.count))", Theme.accent)
                miniStat(loc.t("worst"), s.worst == nil ? "—" : loc.quality(s.worst!),
                         s.worst == nil ? Theme.textSecondary : Theme.quality(s.worst!))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.callout.weight(.semibold)).foregroundStyle(color)
        }
    }

    // MARK: - محاسبه‌ی خلاصه

    private struct Summary { var active: Int; var avgScore: Int; var worst: Int? }

    private var overallSummary: Summary {
        let active = vm.targets.filter { $0.isEnabled }
        let scores = active.compactMap { t -> Int? in
            let s = vm.statistics(for: t); return s.sampleCount > 0 ? s.score : nil
        }
        let avg = scores.isEmpty ? 0 : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        return Summary(active: active.count, avgScore: avg, worst: scores.min())
    }
}

// MARK: - کارت یک مانیتور در داشبورد

struct DashboardCard: View {
    @EnvironmentObject var loc: Localizer
    let target: PingTarget
    let stats: TargetStatistics
    let samples: [PingSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(color: stats.sampleCount > 0 ? stats.color : Theme.qGray)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name).font(.system(size: 15, weight: .semibold))
                    Text(target.displayHost).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer()
                Text(stats.grade)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(stats.color)
            }

            HStack(spacing: 0) {
                metric(loc.t("ping"), loc.n0(stats.current), stats.color, loc.t("ping_help"))
                metric(loc.t("jitter"), loc.n1(stats.jitter), Theme.textPrimary, loc.t("jitter_help"))
                metric(loc.t("loss"), loc.pct(stats.lossPercent),
                       stats.lossPercent > 1 ? Theme.qOrange : Theme.textPrimary, loc.t("loss_help"))
            }

            TrendChart(points: samples.pingPoints, color: stats.sampleCount > 0 ? stats.color : Theme.accent,
                       markLoss: true, height: 84, compact: true)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
        .opacity(target.isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
    }

    private func metric(_ label: String, _ value: String, _ color: Color, _ help: String = "") -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .help(help)
    }
}
