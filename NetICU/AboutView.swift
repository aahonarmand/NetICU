import SwiftUI
import AppKit

/// "About" window: app introduction, metrics glossary and developer credit.
struct AboutView: View {
    @EnvironmentObject var loc: Localizer
    @Environment(\.dismiss) private var dismiss

    private var version: String { AppInfo.version }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Text(loc.t("about_desc"))
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                glossary
                developerCard
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 500, height: 600)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .environment(\.layoutDirection, loc.isRTL ? .rightToLeft : .leftToRight)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(12)
            .help(loc.t("close"))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text("NetICU").font(.system(size: 26, weight: .bold))
                Text(loc.t("tagline"))
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                Text("\(loc.t("version")) \(version)")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var glossary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("glossary")).font(.headline)
            glossaryRow(loc.t("ping"),   loc.t("ping_help"))
            glossaryRow(loc.t("jitter"), loc.t("jitter_help"))
            glossaryRow(loc.t("p95"),    loc.t("p95_help"))
            glossaryRow(loc.t("loss"),   loc.t("loss_help"))
            glossaryRow(loc.t("score"), loc.t("score_help"))
            Divider().padding(.vertical, 2)
            glossaryRow(loc.t("timing_breakdown"), loc.t("breakdown_note"))
            glossaryRow("DNS",  loc.t("dns_help"))
            glossaryRow("TCP",  loc.t("tcp_help"))
            glossaryRow("TLS",  loc.t("tls_help"))
            glossaryRow(loc.t("ttfb"), loc.t("ttfb_help"))
            Divider().padding(.vertical, 2)
            glossaryRow(loc.t("server_vs_net"), loc.t("breakdown_help"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
    }

    private func glossaryRow(_ term: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentBright)
            Text(desc).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var developerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("developer")).font(.caption).foregroundStyle(Theme.textSecondary)
                Text(loc.t("developer_name")).font(.callout.weight(.medium))
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke.opacity(0.6), lineWidth: 1))
    }
}
