import Foundation

/// App version info — the single source of truth (independent of Xcode project settings).
/// On every release, update `version` and `changelog` here.
enum AppInfo {
    static let version = "1.5.0"
    static let build = "10"

    /// Change history (newest first).
    static let changelog: [(version: String, fa: String, en: String)] = [
        ("1.5.0",
         "آماده‌سازی متن‌باز: ترجمه‌ی همه‌ی کامنت‌ها به انگلیسی، تست واحد برای آمار و تجزیه، اعتبارسنجی TLS فقط برای IP خام دور زده می‌شود، رفرش IP عمومی دستی/انتخابی (هر ۵ دقیقه)، کلیدهای UserDefaults متمرکز، شناسه‌ی پایدار نقاط نمودار، یکسان‌سازی تایم‌اوت، و فایل‌های CI/CONTRIBUTING/SECURITY.",
         "Open-source readiness: all code comments translated to English, unit tests for statistics/breakdown, TLS validation bypassed only for raw-IP targets, public-IP refresh now manual/opt-in (5-min cadence), centralized UserDefaults keys, stable chart-point identity, unified probe timeout, and CI/CONTRIBUTING/SECURITY files."),
        ("1.4.1",
         "پاکسازی کد: پوشش کامل پنجره‌ی آماری در بازه‌های کوتاه، رفع نشت session، توقف رفرش IP هنگام Stop، ایمن‌سازی thread در جمع‌آوری متریک‌ها و حذف کد مرده.",
         "Code cleanup: full stats-window coverage at short intervals, session-leak fix, IP refresh stops with monitoring, thread-safe metrics collection, dead-code removal."),
        ("1.4.0",
         "گِیجِ پر/خالی‌شونده در نوار منو، کالیبراسیونِ آستانه‌های کیفیت، و رفعِ افتادنِ نمودار هنگام قطعی.",
         "Fillable menu-bar gauge, quality calibration thresholds, and outage chart-drop fix."),
        ("1.3.0",
         "انگلیسی‌فقط، پراکسی به‌ازای هر مانیتور، تشخیص سرور/شبکه، نوتیفیکیشن هشدار، لاگ‌های اخیر و پاک‌کردن تاریخچه.",
         "English-only, per-monitor proxy, server/network diagnosis, alert notifications, recent logs and clear-history."),
        ("1.2.0",
         "بخش «درباره»، راهنمای معیارها (tooltip) و نمایش نسخه.",
         "About section, in-app metric help (tooltips), and version display."),
        ("1.1.0",
         "تجزیه‌ی زمان (DNS/TCP/TLS/TTFB) و صدک ۹۵ (p95).",
         "Timing breakdown (DNS/TCP/TLS/TTFB) and 95th percentile (p95)."),
        ("1.0.0",
         "نسخه‌ی نخست: پینگ، جیتر، افت بسته، داشبورد، آی‌پی، دوزبانه و مرتب‌سازی.",
         "First release: ping, jitter, loss, dashboard, IP, bilingual UI and sorting."),
    ]
}
