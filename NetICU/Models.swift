import Foundation
import SwiftUI

// MARK: - هدف پایش (یک سایت یا IP)

/// نوع پراکسی.
enum ProxyType: String, Codable, CaseIterable, Sendable {
    case http, socks5
    var label: String { self == .http ? "HTTP" : "SOCKS5" }
}

/// پیکربندی پراکسی برای یک مانیتور.
struct ProxyConfig: Codable, Hashable, Sendable {
    var type: ProxyType = .http
    var host: String = ""
    var port: UInt16 = 0

    var isValid: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0 }
    var display: String { "\(type.label) \(host):\(port)" }
}

/// قانون هشدار: اگر پینگ برای مدت معینی بالاتر از آستانه بماند، نوتیفیکیشن بده.
struct AlertRule: Codable, Hashable, Sendable {
    var pingThresholdMs: Double = 200   // آستانه (Y)
    var durationSeconds: Double = 10    // مدت تداوم (X)
}

/// یک مقصد که کیفیت اتصال به آن سنجیده می‌شود.
struct PingTarget: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String          // نام نمایشی دلخواه
    var host: String          // دامنه یا IP، مثل "8.8.8.8" یا "google.com"
    var port: UInt16 = 443    // پورتی که اتصال TCP روی آن سنجیده می‌شود
    var isEnabled: Bool = true
    var proxy: ProxyConfig? = nil   // پراکسیِ اختصاصیِ این مانیتور (اختیاری)
    var alert: AlertRule? = nil     // هشدار اختصاصیِ این مانیتور (اختیاری)

    /// برچسب کامل برای نمایش
    var displayHost: String { "\(host):\(port)" }

    /// آیا این مانیتور از پراکسی استفاده می‌کند؟
    var usesProxy: Bool { proxy?.isValid == true }
}

// MARK: - نمونه‌ی یک اندازه‌گیری

/// نتیجه‌ی یک بار پینگ.
struct PingSample: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let rttMs: Double?   // زمان رفت‌وبرگشت بر حسب میلی‌ثانیه؛ nil یعنی شکست (packet loss)
    var success: Bool { rttMs != nil }
}

// MARK: - آمار محاسبه‌شده برای یک هدف

/// خلاصه‌ی آماری از پنجره‌ی اخیرِ نمونه‌ها.
struct TargetStatistics {
    var current: Double? = nil      // آخرین پینگ موفق
    var average: Double? = nil
    var minimum: Double? = nil
    var maximum: Double? = nil
    var jitter: Double? = nil       // میانگین قدرمطلق اختلاف پینگ‌های متوالی
    var p95: Double? = nil          // صدک ۹۵ تأخیر (تأخیرِ «دُم»)
    var lossPercent: Double = 0     // درصد بسته‌های ازدست‌رفته
    var score: Int = 0              // امتیاز کیفیت ۰ تا ۱۰۰
    var sampleCount: Int = 0

    /// درجه‌ی حرفی از روی امتیاز.
    var grade: String {
        switch score {
        case 85...100: return "A"
        case 70..<85:  return "B"
        case 50..<70:  return "C"
        case 30..<50:  return "D"
        default:       return "F"
        }
    }

    /// رنگ متناظر با کیفیت (از پالت تم).
    var color: Color { Theme.quality(score) }

    static let empty = TargetStatistics()
}

// MARK: - محاسبه‌ی آمار از روی نمونه‌ها

enum StatisticsCalculator {

    /// اعداد/امتیاز فقط بر اساس این بازه‌ی اخیر محاسبه می‌شوند («وضعیتِ لحظه»).
    static let statsWindowSeconds: Double = 120   // ۲ دقیقه

    /// آمار را از نمونه‌های دو دقیقه‌ی اخیر محاسبه می‌کند (نمودار/لاگ کاملِ تاریخچه را دارند).
    static func compute(from allSamples: [PingSample]) -> TargetStatistics {
        let cutoff = Date().addingTimeInterval(-statsWindowSeconds)
        let samples = allSamples.filter { $0.date >= cutoff }
        guard !samples.isEmpty else { return .empty }

        var stats = TargetStatistics()
        stats.sampleCount = samples.count

        let successful = samples.compactMap { $0.rttMs }

        // packet loss
        let lost = samples.count - successful.count
        stats.lossPercent = Double(lost) / Double(samples.count) * 100.0

        if !successful.isEmpty {
            stats.current = samples.last(where: { $0.success })?.rttMs
            stats.average = successful.reduce(0, +) / Double(successful.count)
            stats.minimum = successful.min()
            stats.maximum = successful.max()
            stats.jitter = jitter(of: samples)
            stats.p95 = percentile(successful, 0.95)
        }

        stats.score = qualityScore(latency: stats.average,
                                    jitter: stats.jitter,
                                    lossPercent: stats.lossPercent,
                                    hasData: !successful.isEmpty)
        return stats
    }

    /// صدک p (۰ تا ۱) از مقادیر.
    private static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let idx = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(max(idx, 0), sorted.count - 1)]
    }

    /// جیتر = میانگین قدرمطلق اختلاف پینگ‌های موفق متوالی.
    private static func jitter(of samples: [PingSample]) -> Double? {
        let rtts = samples.compactMap { $0.rttMs }
        guard rtts.count >= 2 else { return nil }
        var diffs: [Double] = []
        for i in 1..<rtts.count {
            diffs.append(abs(rtts[i] - rtts[i - 1]))
        }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    /// ترکیب سه فاکتور در یک امتیاز ۰ تا ۱۰۰.
    static func qualityScore(latency: Double?, jitter: Double?, lossPercent: Double, hasData: Bool) -> Int {
        guard hasData, let latency = latency else { return 0 }

        // آستانه‌های پینگ از تنظیماتِ کاربر خوانده می‌شوند (کالیبره برای شبکه‌ی محلی).
        let latencyScore = scoreRamp(value: latency, best: Calibration.latencyBest, worst: Calibration.latencyWorst)
        let jitterScore  = scoreRamp(value: jitter ?? 0, best: 2, worst: 50)
        let lossScore    = scoreRamp(value: lossPercent, best: 0, worst: Calibration.lossWorst)

        // وزن‌ها از تنظیمات می‌آیند و نرمال می‌شوند (فرمولِ درصد قابل‌تنظیم است).
        let wl = Calibration.weightLatency
        let wj = Calibration.weightJitter
        let wo = Calibration.weightLoss
        let sum = max(1, wl + wj + wo)
        let combined = (wl * latencyScore + wj * jitterScore + wo * lossScore) / sum
        return Int(combined.rounded())
    }

    /// زیرـامتیازِ پینگ (۰–۱۰۰) بر اساس آستانه‌های کالیبره — برای رنگ‌دهیِ مستقل.
    static func latencySubScore(_ v: Double) -> Int {
        Int(scoreRamp(value: v, best: Calibration.latencyBest, worst: Calibration.latencyWorst).rounded())
    }
    /// زیرـامتیازِ افت بسته (۰–۱۰۰).
    static func lossSubScore(_ v: Double) -> Int {
        Int(scoreRamp(value: v, best: 0, worst: Calibration.lossWorst).rounded())
    }

    /// نگاشت خطی: value ≤ best → ۱۰۰، value ≥ worst → ۰.
    private static func scoreRamp(value: Double, best: Double, worst: Double) -> Double {
        if value <= best { return 100 }
        if value >= worst { return 0 }
        return (worst - value) / (worst - best) * 100
    }
}

// MARK: - کالیبراسیونِ آستانه‌ها (قابل‌تنظیم توسط کاربر)

/// آستانه‌های امتیازدهی که کاربر می‌تواند با شبکه‌ی محلی‌اش تنظیم کند
/// (مثلاً در ایران که پینگ معمولاً بالاتر است). در UserDefaults ذخیره می‌شوند.
enum Calibration {
    static let latBestKey = "latBest"
    static let latWorstKey = "latWorst"
    static let lossWorstKey = "lossWorst"

    // پیش‌فرض‌های کالیبره‌شده برای اینترنت ایران (پینگِ معمولاً بالاتر و افتِ بیشتر)
    static let defaultLatBest: Double = 60     // پینگِ عالی تا ۶۰ms
    static let defaultLatWorst: Double = 700   // پینگِ بد از ۷۰۰ms
    static let defaultLossWorst: Double = 15   // افتِ بد از ۱۵٪

    static var latencyBest: Double {
        let v = UserDefaults.standard.double(forKey: latBestKey)
        return v > 0 ? v : defaultLatBest
    }
    static var latencyWorst: Double {
        let v = UserDefaults.standard.double(forKey: latWorstKey)
        let best = latencyBest
        return v > best ? v : max(defaultLatWorst, best + 50)
    }
    static var lossWorst: Double {
        let v = UserDefaults.standard.double(forKey: lossWorstKey)
        return v > 0 ? v : defaultLossWorst
    }

    // وزن‌های فرمولِ درصد (قابل‌تنظیم)
    static let wLatKey = "wLat"
    static let wJitKey = "wJit"
    static let wLossKey = "wLoss"
    static let defaultWLat: Double = 50
    static let defaultWJit: Double = 25
    static let defaultWLoss: Double = 25

    private static func weight(_ key: String, _ def: Double) -> Double {
        let v = UserDefaults.standard.object(forKey: key) as? Double
        return v ?? def
    }
    static var weightLatency: Double { weight(wLatKey, defaultWLat) }
    static var weightJitter: Double { weight(wJitKey, defaultWJit) }
    static var weightLoss: Double { weight(wLossKey, defaultWLoss) }
}

// MARK: - تجزیه‌ی زمانِ یک درخواست (DNS / TCP / TLS / TTFB)

/// شکستِ زمانِ برقراری اتصال و پاسخ به اجزای آن، بر حسب میلی‌ثانیه.
/// (اجزای DNS/TCP/TLS فقط هنگام برقراریِ اتصالِ جدید مقدار دارند؛ TTFB تقریباً همیشه.)
struct PingBreakdown: Sendable {
    var dnsMs: Double? = nil    // زمان resolve نام
    var tcpMs: Double? = nil    // دست‌دادن TCP
    var tlsMs: Double? = nil    // دست‌دادن TLS
    var ttfbMs: Double? = nil   // زمان تا اولین بایتِ پاسخ سرور
    var date: Date = Date()

    var hasAny: Bool { dnsMs != nil || tcpMs != nil || tlsMs != nil || ttfbMs != nil }

    /// مقادیر تازه را روی مقادیر قبلی ادغام می‌کند (هر جزء اگر مقدار جدید داشت به‌روز می‌شود).
    func merged(with new: PingBreakdown) -> PingBreakdown {
        PingBreakdown(
            dnsMs:  new.dnsMs  ?? dnsMs,
            tcpMs:  new.tcpMs  ?? tcpMs,
            tlsMs:  new.tlsMs  ?? tlsMs,
            ttfbMs: new.ttfbMs ?? ttfbMs,
            date:   new.date
        )
    }

    /// تشخیصِ تقریبیِ گلوگاه: مشکل از سرور است یا شبکه یا DNS؟
    enum Bottleneck { case server, network, dns, none }

    var bottleneck: Bottleneck {
        guard let ttfb = ttfbMs else { return .none }
        if let dns = dnsMs, dns > 120, dns >= ttfb { return .dns }
        if let tcp = tcpMs {
            // TCP ≈ یک رفت‌وبرگشتِ شبکه؛ مازادِ TTFB یعنی زمانِ پردازشِ سرور.
            let serverThink = ttfb - tcp
            if ttfb > tcp * 1.5 && serverThink > 80 { return .server }
            return .network
        }
        return .none   // بدونِ TCP (اتصالِ بازاستفاده‌شده) قضاوتِ مطمئن نمی‌کنیم
    }
}
