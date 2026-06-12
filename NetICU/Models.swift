import Foundation
import SwiftUI

// MARK: - UserDefaults keys

/// Central registry of all UserDefaults keys, so a typo can't silently reset a setting.
enum DefaultsKey {
    static let intervalSeconds  = "intervalSeconds"
    static let savedTargets     = "savedTargets"
    static let sortOrder        = "sortOrder"
    static let menuBarTopID     = "menuBarTopID"
    static let menuBarBottomID  = "menuBarBottomID"
    static let autoRefreshIP    = "autoRefreshIP"
    // Quality-score calibration
    static let latencyBest      = "latBest"
    static let latencyWorst     = "latWorst"
    static let lossWorst        = "lossWorst"
    static let weightLatency    = "wLat"
    static let weightJitter     = "wJit"
    static let weightLoss       = "wLoss"
}

// MARK: - Monitoring target (a site or IP)

/// Proxy type.
enum ProxyType: String, Codable, CaseIterable, Sendable {
    case http, socks5
    var label: String { self == .http ? "HTTP" : "SOCKS5" }
}

/// Proxy configuration for a single monitor.
struct ProxyConfig: Codable, Hashable, Sendable {
    var type: ProxyType = .http
    var host: String = ""
    var port: UInt16 = 0

    var isValid: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0 }
    var display: String { "\(type.label) \(host):\(port)" }
}

/// Alert rule: send a notification if ping stays above a threshold for a given duration.
struct AlertRule: Codable, Hashable, Sendable {
    var pingThresholdMs: Double = 200   // threshold (Y)
    var durationSeconds: Double = 10    // sustained duration (X)
}

/// A destination whose connection quality is measured.
struct PingTarget: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String          // user-chosen display name
    var host: String          // domain or IP, e.g. "8.8.8.8" or "google.com"
    var port: UInt16 = 443    // port the connection is measured on
    var isEnabled: Bool = true
    var proxy: ProxyConfig? = nil   // optional per-monitor proxy
    var alert: AlertRule? = nil     // optional per-monitor alert

    /// Full label for display.
    var displayHost: String { "\(host):\(port)" }

    /// Whether this monitor goes through a proxy.
    var usesProxy: Bool { proxy?.isValid == true }
}

// MARK: - A single measurement sample

/// Result of one ping.
struct PingSample: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let rttMs: Double?   // round-trip time in milliseconds; nil means failure (packet loss)
    var success: Bool { rttMs != nil }
}

// MARK: - Computed statistics for a target

/// Statistical summary over the recent window of samples.
struct TargetStatistics {
    var current: Double? = nil      // most recent successful ping
    var average: Double? = nil
    var minimum: Double? = nil
    var maximum: Double? = nil
    var jitter: Double? = nil       // mean absolute difference of consecutive pings
    var p95: Double? = nil          // 95th percentile latency ("tail" latency)
    var lossPercent: Double = 0     // percentage of lost packets
    var score: Int = 0              // quality score, 0–100
    var sampleCount: Int = 0

    /// Letter grade derived from the score.
    var grade: String {
        switch score {
        case 85...100: return "A"
        case 70..<85:  return "B"
        case 50..<70:  return "C"
        case 30..<50:  return "D"
        default:       return "F"
        }
    }

    /// Color matching the quality (from the theme palette).
    var color: Color { Theme.quality(score) }

    static let empty = TargetStatistics()
}

// MARK: - Computing statistics from samples

enum StatisticsCalculator {

    /// Numbers/score are computed only over this recent window ("current state").
    static let statsWindowSeconds: Double = 120   // 2 minutes

    /// Computes statistics from the samples of the last two minutes
    /// (charts/logs keep the full history).
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

    /// Percentile p (0 to 1) of the values.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let idx = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(max(idx, 0), sorted.count - 1)]
    }

    /// Jitter = mean absolute difference of consecutive successful pings.
    static func jitter(of samples: [PingSample]) -> Double? {
        let rtts = samples.compactMap { $0.rttMs }
        guard rtts.count >= 2 else { return nil }
        var diffs: [Double] = []
        for i in 1..<rtts.count {
            diffs.append(abs(rtts[i] - rtts[i - 1]))
        }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    /// Combines the three factors into a single 0–100 score.
    static func qualityScore(latency: Double?, jitter: Double?, lossPercent: Double, hasData: Bool) -> Int {
        guard hasData, let latency = latency else { return 0 }

        // Ping thresholds come from user settings (calibrated for the local network).
        let latencyScore = scoreRamp(value: latency, best: Calibration.latencyBest, worst: Calibration.latencyWorst)
        let jitterScore  = scoreRamp(value: jitter ?? 0, best: 2, worst: 50)
        let lossScore    = scoreRamp(value: lossPercent, best: 0, worst: Calibration.lossWorst)

        // Weights come from settings and are normalized (the score formula is adjustable).
        let wl = Calibration.weightLatency
        let wj = Calibration.weightJitter
        let wo = Calibration.weightLoss
        let sum = max(1, wl + wj + wo)
        let combined = (wl * latencyScore + wj * jitterScore + wo * lossScore) / sum
        return Int(combined.rounded())
    }

    /// Latency sub-score (0–100) using the calibrated thresholds — for independent coloring.
    static func latencySubScore(_ v: Double) -> Int {
        Int(scoreRamp(value: v, best: Calibration.latencyBest, worst: Calibration.latencyWorst).rounded())
    }
    /// Packet-loss sub-score (0–100).
    static func lossSubScore(_ v: Double) -> Int {
        Int(scoreRamp(value: v, best: 0, worst: Calibration.lossWorst).rounded())
    }

    /// Linear mapping: value ≤ best → 100, value ≥ worst → 0.
    static func scoreRamp(value: Double, best: Double, worst: Double) -> Double {
        if value <= best { return 100 }
        if value >= worst { return 0 }
        return (worst - value) / (worst - best) * 100
    }
}

// MARK: - Threshold calibration (user-adjustable)

/// Scoring thresholds the user can tune to their local network
/// (e.g. networks where baseline ping is naturally higher). Stored in UserDefaults.
enum Calibration {
    // Defaults calibrated for high-latency networks (higher typical ping and loss).
    static let defaultLatBest: Double = 60     // excellent ping up to 60 ms
    static let defaultLatWorst: Double = 700   // bad ping from 700 ms
    static let defaultLossWorst: Double = 15   // bad loss from 15%

    static var latencyBest: Double {
        let v = UserDefaults.standard.double(forKey: DefaultsKey.latencyBest)
        return v > 0 ? v : defaultLatBest
    }
    static var latencyWorst: Double {
        let v = UserDefaults.standard.double(forKey: DefaultsKey.latencyWorst)
        let best = latencyBest
        return v > best ? v : max(defaultLatWorst, best + 50)
    }
    static var lossWorst: Double {
        let v = UserDefaults.standard.double(forKey: DefaultsKey.lossWorst)
        return v > 0 ? v : defaultLossWorst
    }

    // Score-formula weights (adjustable)
    static let defaultWLat: Double = 50
    static let defaultWJit: Double = 25
    static let defaultWLoss: Double = 25

    private static func weight(_ key: String, _ def: Double) -> Double {
        let v = UserDefaults.standard.object(forKey: key) as? Double
        return v ?? def
    }
    static var weightLatency: Double { weight(DefaultsKey.weightLatency, defaultWLat) }
    static var weightJitter: Double { weight(DefaultsKey.weightJitter, defaultWJit) }
    static var weightLoss: Double { weight(DefaultsKey.weightLoss, defaultWLoss) }
}

// MARK: - Timing breakdown of a request (DNS / TCP / TLS / TTFB)

/// Breaks connection-setup and response time into its parts, in milliseconds.
/// (DNS/TCP/TLS parts only have values when a new connection is established; TTFB almost always.)
struct PingBreakdown: Sendable {
    var dnsMs: Double? = nil    // name-resolution time
    var tcpMs: Double? = nil    // TCP handshake
    var tlsMs: Double? = nil    // TLS handshake
    var ttfbMs: Double? = nil   // time to the server's first response byte
    var date: Date = Date()

    var hasAny: Bool { dnsMs != nil || tcpMs != nil || tlsMs != nil || ttfbMs != nil }

    /// Merges fresh values over the previous ones (each component updates if a new value exists).
    func merged(with new: PingBreakdown) -> PingBreakdown {
        PingBreakdown(
            dnsMs:  new.dnsMs  ?? dnsMs,
            tcpMs:  new.tcpMs  ?? tcpMs,
            tlsMs:  new.tlsMs  ?? tlsMs,
            ttfbMs: new.ttfbMs ?? ttfbMs,
            date:   new.date
        )
    }

    /// Rough bottleneck diagnosis: is the problem the server, the network, or DNS?
    enum Bottleneck { case server, network, dns, none }

    var bottleneck: Bottleneck {
        guard let ttfb = ttfbMs else { return .none }
        if let dns = dnsMs, dns > 120, dns >= ttfb { return .dns }
        if let tcp = tcpMs {
            // TCP ≈ one network round trip; the excess of TTFB is server processing time.
            let serverThink = ttfb - tcp
            if ttfb > tcp * 1.5 && serverThink > 80 { return .server }
            return .network
        }
        return .none   // without TCP (reused connection) we don't make a confident call
    }
}
