import SwiftUI
import Combine

/// مدیریت رشته‌ها — اپ فقط انگلیسی است.
@MainActor
final class Localizer: ObservableObject {

    /// همیشه چپ‌چین (انگلیسی).
    var isRTL: Bool { false }

    /// ترجمه‌ی یک کلید (انگلیسی).
    func t(_ key: String) -> String {
        Localizer.table[key]?.en ?? key
    }

    // MARK: - شکل‌دهی اعداد (انگلیسی، ارقام لاتین)

    private func digits(_ s: String) -> String { s }
    /// عدد صحیح (میلی‌ثانیه)
    func n0(_ v: Double?) -> String { v == nil ? "—" : digits(String(Int(v!.rounded()))) }
    /// عدد با یک رقم اعشار
    func n1(_ v: Double?) -> String { v == nil ? "—" : digits(String(format: "%.1f", v!)) }
    /// عدد صحیح ساده
    func int(_ v: Int) -> String { digits(String(v)) }
    /// درصد
    func pct(_ v: Double) -> String { digits(String(Int(v.rounded()))) + "%" }

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

    // MARK: - جدول ترجمه‌ها

    private static let table: [String: (en: String, fa: String)] = [
        "dashboard":      ("Dashboard", "داشبورد"),
        "monitors":       ("Monitors", "مانیتورها"),
        "add_monitor":    ("Add monitor", "افزودن مانیتور"),
        "edit_monitor":   ("Edit monitor", "ویرایش مانیتور"),
        "edit":           ("Edit", "ویرایش"),
        "delete":         ("Delete", "حذف"),
        "start":          ("Start", "شروع"),
        "stop":           ("Stop", "توقف"),
        "monitoring":     ("Monitoring", "در حال پایش"),
        "stopped":        ("Stopped", "متوقف"),
        "ping":           ("Ping", "پینگ"),
        "average":        ("Average", "میانگین"),
        "jitter":         ("Jitter", "جیتر"),
        "loss":           ("Packet loss", "افت بسته"),
        "min":            ("Min", "کمینه"),
        "max":            ("Max", "بیشینه"),
        "samples":        ("Samples", "نمونه‌ها"),
        "ping_trend":     ("Ping trend", "روند پینگ"),
        "jitter_trend":   ("Jitter trend", "روند جیتر"),
        "collecting":     ("Collecting data…", "در حال جمع‌آوری داده…"),
        "select_monitor": ("Select a monitor", "یک مانیتور را انتخاب کنید"),
        "public_ip":      ("Public IP", "آی‌پی عمومی"),
        "local_ip":       ("Local IP", "آی‌پی محلی"),
        "name":           ("Display name", "نام نمایشی"),
        "host":           ("Domain, IP or URL", "دامنه، IP یا آدرس"),
        "port":           ("Port", "پورت"),
        "enabled":        ("Enabled", "فعال"),
        "disabled":       ("Disabled", "غیرفعال"),
        "save":           ("Save", "ذخیره"),
        "cancel":         ("Cancel", "انصراف"),
        "open_window":    ("Open window", "باز کردن پنجره"),
        "quit":           ("Quit", "خروج"),
        "interval":       ("Measurement interval", "بازه‌ی اندازه‌گیری"),
        "language":       ("Language", "زبان"),
        "settings":       ("Settings", "تنظیمات"),
        "overview":       ("Overview", "نمای کلی"),
        "active":         ("Active", "فعال"),
        "worst":          ("Worst quality", "بدترین کیفیت"),
        "best":           ("Best quality", "بهترین کیفیت"),
        "avg_score":      ("Average score", "میانگین امتیاز"),
        "excellent":      ("Excellent", "عالی"),
        "good":           ("Good", "خوب"),
        "medium":         ("Fair", "متوسط"),
        "poor":           ("Poor", "ضعیف"),
        "critical":       ("Critical", "بحرانی"),
        "no_monitors":    ("No monitors yet", "هنوز مانیتوری اضافه نشده"),
        "seconds":        ("s", "ثانیه"),
        "ms":             ("ms", "ms"),
        "your_connection":("Your connection", "اتصال شما"),
        "tagline":        ("Internet, in intensive care", "اینترنت، در مراقبت‌های ویژه"),
        "refresh_ip":     ("Refresh IP", "تازه‌سازی آی‌پی"),
        "name_ph":        ("e.g. Game server", "مثلاً سرور بازی"),
        "host_ph":        ("google.com or 1.1.1.1", "google.com یا 1.1.1.1"),
        "sort":           ("Sort", "مرتب‌سازی"),
        "sort_manual":    ("Manual (drag)", "دستی (کشیدن)"),
        "sort_name":      ("Name", "نام"),
        "sort_ping":      ("Ping (low→high)", "پینگ (کم به زیاد)"),
        "sort_quality":   ("Quality (best first)", "کیفیت (بهترین اول)"),
        "p95":            ("p95", "صدک ۹۵"),
        "timing_breakdown": ("Timing breakdown", "تجزیه‌ی زمان"),
        "dns":            ("DNS", "DNS"),
        "ttfb":           ("TTFB", "TTFB"),
        "breakdown_note": ("DNS/TCP/TLS are measured on a new connection; TTFB updates each request.",
                           "DNS/TCP/TLS هنگام اتصال جدید سنجیده می‌شوند؛ TTFB هر بار به‌روز می‌شود."),
        "breakdown_help": ("This splits a request into its parts. A high number doesn't always mean a slow network: high TTFB while TCP is low means the SERVER is slow to respond (its software/load/config), not your connection. High TCP means network distance; high DNS means a resolver issue. Tip: compare several targets — if only one is slow, it's that server, not you.",
                           "این بخش، یک درخواست را به اجزایش می‌شکند. عددِ بالا همیشه به‌معنای شبکهٔ کند نیست: TTFBِ بالا در حالی‌که TCP پایین است یعنی خودِ سرور دیر جواب می‌دهد (نرم‌افزار/بار/تنظیماتش)، نه اتصالِ تو. TCPِ بالا یعنی فاصلهٔ شبکه؛ DNSِ بالا یعنی مشکلِ resolver. نکته: چند هدف را مقایسه کن — اگر فقط یکی کند است، تقصیرِ همان سرور است نه تو."),
        "diagnosis":      ("Diagnosis", "تشخیص"),
        "diag_server":    ("Likely the server (slow to respond)", "احتمالاً خودِ سرور (دیر جواب می‌دهد)"),
        "diag_network":   ("Likely the network / distance", "احتمالاً شبکه / فاصله"),
        "diag_dns":       ("Likely DNS resolution", "احتمالاً resolveِ DNS"),
        "server_vs_net":  ("Server vs. your network", "سرور یا شبکهٔ تو؟"),
        "proxy":          ("Proxy", "پراکسی"),
        "use_proxy":      ("Use a proxy for this monitor", "استفاده از پراکسی برای این مانیتور"),
        "proxy_type":     ("Type", "نوع"),
        "proxy_host":     ("Proxy host", "هاست پراکسی"),
        "proxy_port":     ("Proxy port", "پورت پراکسی"),
        "proxy_help":     ("Requests for this monitor go through this proxy (e.g. a local SOCKS/HTTP proxy at 127.0.0.1).",
                           "درخواست‌های این مانیتور از این پراکسی عبور می‌کنند (مثلاً پراکسی محلی SOCKS/HTTP روی 127.0.0.1)."),
        "via_proxy":      ("via proxy", "از طریق پراکسی"),
        "alerts":         ("Alert", "هشدار"),
        "enable_alert":   ("Notify me when ping stays high", "وقتی پینگ بالا ماند خبرم کن"),
        "alert_threshold":("Ping threshold (ms)", "آستانه‌ی پینگ (ms)"),
        "alert_duration": ("For at least (seconds)", "به‌مدتِ حداقل (ثانیه)"),
        "alert_help":     ("You'll get a notification if ping stays above the threshold for this long (a timeout counts too). macOS will ask for notification permission once.",
                           "اگر پینگ این‌مدت بالاتر از آستانه بماند نوتیفیکیشن می‌گیری (تایم‌اوت هم حساب می‌شود). macOS یک‌بار اجازه‌ی نوتیفیکیشن می‌خواهد."),
        "alert_on":       ("alert on", "هشدار فعال"),
        "recent_logs":    ("Recent logs", "لاگ‌های اخیر"),
        "logs_timeout":   ("timeout", "تایم‌اوت"),
        "clear_history":  ("Clear history", "پاک‌کردن تاریخچه"),
        "clear_history_confirm": ("Clear this monitor's history? This can't be undone.",
                                  "تاریخچه‌ی این مانیتور پاک شود؟ قابل بازگشت نیست."),
        "clear":          ("Clear", "پاک کن"),
        "calibration":    ("Quality calibration", "کالیبراسیون کیفیت"),
        "calib_excellent":("Excellent ping at or below", "پینگِ عالی، تا"),
        "calib_bad":      ("Bad ping at or above", "پینگِ بد، از"),
        "calib_loss":     ("Bad packet loss at", "افت بسته‌ی بد، از"),
        "calib_reset":    ("Reset to defaults", "بازگردانی به پیش‌فرض"),
        "calib_help":     ("Tune these to your network. On slower networks raise the thresholds so the score and the menu-bar circle aren't always red. Affects the quality score everywhere.",
                           "این‌ها را با شبکه‌ی خود تنظیم کن. روی شبکه‌های کندتر، آستانه‌ها را بالاتر ببر تا امتیاز و دایره‌ی نوار منو همیشه قرمز نباشند. روی امتیازِ کیفیت در همه‌جا اثر می‌گذارد."),
        "score_formula":  ("Score formula (weights)", "فرمولِ امتیاز (وزن‌ها)"),
        "menubar_section":("Menu bar", "نوار منو"),
        "menubar_top":    ("Top number (ping of)", "عددِ بالا (پینگِ)"),
        "menubar_bottom": ("Bottom number (ping of)", "عددِ پایین (پینگِ)"),
        "menubar_auto":   ("Auto (worst monitor)", "خودکار (بدترین مانیتور)"),
        "menubar_help":   ("Each line shows the ping of the chosen monitor, colored by its status. Pick a different monitor for top and bottom.",
                           "هر خط پینگِ مانیتورِ انتخاب‌شده را با رنگِ وضعیتش نشان می‌دهد. برای بالا و پایین می‌توانی دو مانیتورِ متفاوت انتخاب کنی."),
        "weights_help":   ("How much each factor counts toward the percentage. Weights are normalized automatically.",
                           "سهمِ هر فاکتور در درصدِ نهایی. وزن‌ها خودکار نرمال می‌شوند."),

        // درباره
        "about":          ("About", "درباره"),
        "about_desc":     ("NetICU monitors the quality of your internet AND the performance of specific servers in real time — ping, jitter, packet loss and a DNS/TCP/TLS/TTFB breakdown — so you can tell whether a slowdown is your network or the server itself.",
                           "NetICU هم کیفیت اینترنتِ شما و هم پرفورمنسِ سرورهای مشخص را به‌صورت زنده مانیتور می‌کند — پینگ، جیتر، افت بسته و تجزیه‌ی DNS/TCP/TLS/TTFB — تا بفهمی کندی از شبکهٔ توست یا از خودِ سرور."),
        "developer":      ("Developer", "توسعه‌دهنده"),
        "developer_name": ("Aliasghar Honarmand with the Help of Claude", "علی‌اصغر هنرمند با همکاری حضرت کلاد"),
        "version":        ("Version", "نسخه"),
        "glossary":       ("What the metrics mean", "معنی معیارها"),
        "close":          ("Close", "بستن"),
        "score":          ("Quality score", "امتیاز کیفیت"),

        // راهنمای معیارها (هم برای تول‌تیپ، هم برای واژه‌نامه)
        "current_help":   ("The most recent ping measurement.", "آخرین پینگِ اندازه‌گیری‌شده."),
        "ping_help":      ("Round-trip time of a request to the target. Lower is better.",
                           "زمان رفت‌وبرگشتِ یک درخواست تا هدف. کمتر = بهتر."),
        "average_help":   ("Average ping over the recent window.", "میانگین پینگ در پنجره‌ی اخیر."),
        "jitter_help":    ("How much ping varies between consecutive measurements. Low = stable.",
                           "نوسانِ پینگ بین اندازه‌گیری‌های پیاپی. کم = پایدار."),
        "p95_help":       ("95% of measurements were better (lower) than this — your typical worst case. Averages hide the occasional bad spikes that ruin calls and gaming.",
                           "۹۵٪ اندازه‌گیری‌ها از این بهتر (کمتر) بوده‌اند؛ یعنی «بدترین حالتِ معمول». میانگین، پرش‌های بدِ گاه‌به‌گاه را پنهان می‌کند، ولی همان‌ها تماس و گیم را خراب می‌کنند."),
        "loss_help":      ("Percent of requests that got no reply. Even 1–2% hurts video calls.",
                           "درصد درخواست‌هایی که اصلاً پاسخ نگرفتند. حتی ۱–۲٪ برای تماس تصویری بد است."),
        "min_help":       ("Lowest ping observed.", "کم‌ترین پینگِ مشاهده‌شده."),
        "max_help":       ("Highest ping observed.", "بیش‌ترین پینگِ مشاهده‌شده."),
        "samples_help":   ("Number of measurements kept.", "تعداد اندازه‌گیری‌های نگه‌داری‌شده."),
        "score_help":     ("Combines ping, jitter and loss into one 0–100 score with an A–F grade.",
                           "ترکیبِ پینگ، جیتر و افت بسته در یک عددِ ۰ تا ۱۰۰ و درجه‌ی A تا F."),
        "dns_help":       ("Time to resolve the domain name to an IP address.",
                           "زمانِ تبدیلِ نامِ دامنه به IP."),
        "tcp_help":       ("Time for the TCP connection handshake.", "زمانِ دست‌دادنِ اتصالِ TCP."),
        "tls_help":       ("Time for the secure HTTPS handshake.", "زمانِ دست‌دادنِ امنِ HTTPS."),
        "ttfb_help":      ("Time until the server's first response byte (server responsiveness).",
                           "زمان تا اولین بایتِ پاسخِ سرور (پاسخ‌گوییِ سرور)."),
    ]
}
