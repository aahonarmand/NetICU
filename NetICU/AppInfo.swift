import Foundation

/// اطلاعات نسخه‌ی اپ — منبعِ واحد و قابل‌اعتماد (مستقل از تنظیمات پروژه‌ی Xcode).
/// در هر به‌روزرسانی، `version` و `changelog` همین‌جا به‌روز می‌شوند.
enum AppInfo {
    static let version = "1.4.0"
    static let build = "8"

    /// تاریخچه‌ی تغییرات (جدیدترین بالا).
    static let changelog: [(version: String, fa: String, en: String)] = [
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
