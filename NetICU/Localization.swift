import SwiftUI
import Combine

/// مدیریت رشته‌های رابط کاربری — اپ فقط انگلیسی است.
@MainActor
final class Localizer: ObservableObject {

    /// همیشه چپ‌چین (انگلیسی).
    var isRTL: Bool { false }

    /// رشته‌ی یک کلید؛ اگر کلید نبود خودِ کلید برگردانده می‌شود.
    func t(_ key: String) -> String {
        Localizer.table[key] ?? key
    }

    // MARK: - شکل‌دهی اعداد

    /// عدد صحیح (میلی‌ثانیه)
    func n0(_ v: Double?) -> String { v == nil ? "—" : String(Int(v!.rounded())) }
    /// عدد با یک رقم اعشار
    func n1(_ v: Double?) -> String { v == nil ? "—" : String(format: "%.1f", v!) }
    /// عدد صحیح ساده
    func int(_ v: Int) -> String { String(v) }
    /// درصد
    func pct(_ v: Double) -> String { String(Int(v.rounded())) + "%" }

    /// برچسب کیفیت بر اساس امتیاز
    func quality(_ score: Int) -> String {
        switch score {
        case 85...100: return t("excellent")
        case 70..<85:  return t("good")
        case 50..<70:  return t("medium")
        case 30..<50:  return t("poor")
        default:       return t("critical")
        }
    }

    // MARK: - جدول رشته‌ها

    private static let table: [String: String] = [
        "dashboard":      "Dashboard",
        "monitors":       "Monitors",
        "add_monitor":    "Add monitor",
        "edit_monitor":   "Edit monitor",
        "edit":           "Edit",
        "delete":         "Delete",
        "start":          "Start",
        "stop":           "Stop",
        "monitoring":     "Monitoring",
        "stopped":        "Stopped",
        "ping":           "Ping",
        "average":        "Average",
        "jitter":         "Jitter",
        "loss":           "Packet loss",
        "min":            "Min",
        "max":            "Max",
        "samples":        "Samples",
        "ping_trend":     "Ping trend",
        "jitter_trend":   "Jitter trend",
        "collecting":     "Collecting data…",
        "public_ip":      "Public IP",
        "local_ip":       "Local IP",
        "name":           "Display name",
        "host":           "Domain, IP or URL",
        "port":           "Port",
        "enabled":        "Enabled",
        "disabled":       "Disabled",
        "save":           "Save",
        "cancel":         "Cancel",
        "open_window":    "Open window",
        "quit":           "Quit",
        "interval":       "Measurement interval",
        "active":         "Active",
        "worst":          "Worst quality",
        "avg_score":      "Average score",
        "excellent":      "Excellent",
        "good":           "Good",
        "medium":         "Fair",
        "poor":           "Poor",
        "critical":       "Critical",
        "no_monitors":    "No monitors yet",
        "seconds":        "s",
        "ms":             "ms",
        "your_connection": "Your connection",
        "tagline":        "Internet, in intensive care",
        "refresh_ip":     "Refresh IP",
        "name_ph":        "e.g. Game server",
        "host_ph":        "google.com or 1.1.1.1",
        "sort":           "Sort",
        "sort_manual":    "Manual (drag)",
        "sort_name":      "Name",
        "sort_ping":      "Ping (low→high)",
        "sort_quality":   "Quality (best first)",
        "p95":            "p95",
        "timing_breakdown": "Timing breakdown",
        "dns":            "DNS",
        "ttfb":           "TTFB",
        "breakdown_note": "DNS/TCP/TLS are measured on a new connection; TTFB updates each request.",
        "breakdown_help": "This splits a request into its parts. A high number doesn't always mean a slow network: high TTFB while TCP is low means the SERVER is slow to respond (its software/load/config), not your connection. High TCP means network distance; high DNS means a resolver issue. Tip: compare several targets — if only one is slow, it's that server, not you.",
        "diag_server":    "Likely the server (slow to respond)",
        "diag_network":   "Likely the network / distance",
        "diag_dns":       "Likely DNS resolution",
        "server_vs_net":  "Server vs. your network",
        "proxy":          "Proxy",
        "use_proxy":      "Use a proxy for this monitor",
        "proxy_type":     "Type",
        "proxy_host":     "Proxy host",
        "proxy_port":     "Proxy port",
        "proxy_help":     "Requests for this monitor go through this proxy (e.g. a local SOCKS/HTTP proxy at 127.0.0.1).",
        "via_proxy":      "via proxy",
        "alerts":         "Alert",
        "enable_alert":   "Notify me when ping stays high",
        "alert_threshold": "Ping threshold (ms)",
        "alert_duration": "For at least (seconds)",
        "alert_help":     "You'll get a notification if ping stays above the threshold for this long (a timeout counts too). macOS will ask for notification permission once.",
        "alert_on":       "alert on",
        "recent_logs":    "Recent logs",
        "logs_timeout":   "timeout",
        "clear_history":  "Clear history",
        "clear_history_confirm": "Clear this monitor's history? This can't be undone.",
        "clear":          "Clear",
        "calibration":    "Quality calibration",
        "calib_excellent": "Excellent ping at or below",
        "calib_bad":      "Bad ping at or above",
        "calib_loss":     "Bad packet loss at",
        "calib_reset":    "Reset to defaults",
        "calib_help":     "Tune these to your network. On slower networks raise the thresholds so the score and the menu-bar circle aren't always red. Affects the quality score everywhere.",
        "score_formula":  "Score formula (weights)",
        "menubar_section": "Menu bar",
        "menubar_top":    "Top number (ping of)",
        "menubar_bottom": "Bottom number (ping of)",
        "menubar_auto":   "Auto (worst monitor)",
        "menubar_help":   "Each line shows the ping of the chosen monitor, colored by its status. Pick a different monitor for top and bottom.",
        "weights_help":   "How much each factor counts toward the percentage. Weights are normalized automatically.",

        // درباره
        "about":          "About",
        "about_desc":     "NetICU monitors the quality of your internet AND the performance of specific servers in real time — ping, jitter, packet loss and a DNS/TCP/TLS/TTFB breakdown — so you can tell whether a slowdown is your network or the server itself.",
        "developer":      "Developer",
        "developer_name": "Aliasghar Honarmand with the Help of Claude",
        "version":        "Version",
        "glossary":       "What the metrics mean",
        "close":          "Close",
        "score":          "Quality score",

        // راهنمای معیارها (هم برای تول‌تیپ، هم برای واژه‌نامه)
        "current_help":   "The most recent ping measurement.",
        "ping_help":      "Round-trip time of a request to the target. Lower is better.",
        "average_help":   "Average ping over the recent window.",
        "jitter_help":    "How much ping varies between consecutive measurements. Low = stable.",
        "p95_help":       "95% of measurements were better (lower) than this — your typical worst case. Averages hide the occasional bad spikes that ruin calls and gaming.",
        "loss_help":      "Percent of requests that got no reply. Even 1–2% hurts video calls.",
        "min_help":       "Lowest ping observed.",
        "max_help":       "Highest ping observed.",
        "samples_help":   "Number of measurements kept.",
        "score_help":     "Combines ping, jitter and loss into one 0–100 score with an A–F grade.",
        "dns_help":       "Time to resolve the domain name to an IP address.",
        "tcp_help":       "Time for the TCP connection handshake.",
        "tls_help":       "Time for the secure HTTPS handshake.",
        "ttfb_help":      "Time until the server's first response byte (server responsiveness).",
    ]
}
