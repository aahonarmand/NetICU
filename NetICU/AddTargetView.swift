import SwiftUI

/// شیت افزودن یا ویرایش یک مانیتور.
struct AddTargetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var loc: Localizer

    @State private var name: String
    @State private var host: String
    @State private var portText: String
    @State private var isEnabled: Bool
    // پراکسی
    @State private var proxyEnabled: Bool
    @State private var proxyType: ProxyType
    @State private var proxyHost: String
    @State private var proxyPortText: String
    // هشدار
    @State private var alertEnabled: Bool
    @State private var alertThresholdText: String
    @State private var alertDurationText: String

    private let existingID: UUID?
    private let onSave: (PingTarget) -> Void

    init(onSave: @escaping (PingTarget) -> Void) {
        _name = State(initialValue: "")
        _host = State(initialValue: "")
        _portText = State(initialValue: "443")
        _isEnabled = State(initialValue: true)
        _proxyEnabled = State(initialValue: false)
        _proxyType = State(initialValue: .http)
        _proxyHost = State(initialValue: "")
        _proxyPortText = State(initialValue: "")
        _alertEnabled = State(initialValue: false)
        _alertThresholdText = State(initialValue: "200")
        _alertDurationText = State(initialValue: "10")
        existingID = nil
        self.onSave = onSave
    }

    init(existing: PingTarget, onSave: @escaping (PingTarget) -> Void) {
        _name = State(initialValue: existing.name)
        _host = State(initialValue: existing.host)
        _portText = State(initialValue: String(existing.port))
        _isEnabled = State(initialValue: existing.isEnabled)
        _proxyEnabled = State(initialValue: existing.proxy?.isValid ?? false)
        _proxyType = State(initialValue: existing.proxy?.type ?? .http)
        _proxyHost = State(initialValue: existing.proxy?.host ?? "")
        _proxyPortText = State(initialValue: existing.proxy.map { String($0.port) } ?? "")
        _alertEnabled = State(initialValue: existing.alert != nil)
        _alertThresholdText = State(initialValue: existing.alert.map { String(Int($0.pingThresholdMs)) } ?? "200")
        _alertDurationText = State(initialValue: existing.alert.map { String(Int($0.durationSeconds)) } ?? "10")
        existingID = existing.id
        self.onSave = onSave
    }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedProxyHost: String { proxyHost.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool {
        guard !trimmedHost.isEmpty, (UInt16(portText) ?? 0) > 0 else { return false }
        if proxyEnabled, !(!trimmedProxyHost.isEmpty && (UInt16(proxyPortText) ?? 0) > 0) {
            return false
        }
        if alertEnabled, !((Double(alertThresholdText) ?? 0) > 0 && (Double(alertDurationText) ?? 0) > 0) {
            return false
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existingID == nil ? loc.t("add_monitor") : loc.t("edit_monitor"))
                .font(.headline).padding()
            Divider()
            Form {
                Section {
                    TextField(loc.t("name"), text: $name, prompt: Text(loc.t("name_ph")))
                    TextField(loc.t("host"), text: $host, prompt: Text(loc.t("host_ph")))
                    TextField(loc.t("port"), text: $portText, prompt: Text("443"))
                    Toggle(loc.t("enabled"), isOn: $isEnabled)
                }
                Section {
                    Toggle(loc.t("use_proxy"), isOn: $proxyEnabled.animation())
                    if proxyEnabled {
                        Picker(loc.t("proxy_type"), selection: $proxyType) {
                            ForEach(ProxyType.allCases, id: \.self) { t in
                                Text(t.label).tag(t)
                            }
                        }
                        TextField(loc.t("proxy_host"), text: $proxyHost, prompt: Text("127.0.0.1"))
                        TextField(loc.t("proxy_port"), text: $proxyPortText, prompt: Text("1080"))
                        Text(loc.t("proxy_help"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(loc.t("proxy"))
                }
                Section {
                    Toggle(loc.t("enable_alert"), isOn: $alertEnabled.animation())
                    if alertEnabled {
                        TextField(loc.t("alert_threshold"), text: $alertThresholdText, prompt: Text("200"))
                        TextField(loc.t("alert_duration"), text: $alertDurationText, prompt: Text("10"))
                        Text(loc.t("alert_help"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(loc.t("alerts"))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button(loc.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(loc.t("save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400)
        .tint(Theme.accent)
    }

    private func save() {
        let port = UInt16(portText) ?? 443
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var proxy: ProxyConfig? = nil
        if proxyEnabled, !trimmedProxyHost.isEmpty, let pport = UInt16(proxyPortText), pport > 0 {
            proxy = ProxyConfig(type: proxyType, host: trimmedProxyHost, port: pport)
        }
        var alert: AlertRule? = nil
        if alertEnabled, let thr = Double(alertThresholdText), thr > 0,
           let dur = Double(alertDurationText), dur > 0 {
            alert = AlertRule(pingThresholdMs: thr, durationSeconds: dur)
        }
        let target = PingTarget(
            id: existingID ?? UUID(),
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            port: port,
            isEnabled: isEnabled,
            proxy: proxy,
            alert: alert
        )
        onSave(target)
        dismiss()
    }
}
