import Foundation
import Network

/// موتور اندازه‌گیری کیفیت اتصال.
///
/// به‌جای زمانِ دست‌دادن خام TCP، یک درخواست HTTP(S) واقعی به هدف می‌فرستد و زمان
/// پاسخ را می‌سنجد. علتش این است که در برخی شبکه‌ها (مثل شبکه‌هایی با پروکسی/میدل‌باکس
/// شفاف) دست‌دادن TCP به‌صورت محلی و آنی پاسخ داده می‌شود و زمان آن تقریباً صفر می‌افتد.
/// یک درخواست HTTP باید تا خود سرور برود و برگردد، پس عددی واقعی و معنادار می‌دهد.
actor PingEngine {

    private let defaultSession: URLSession
    /// سشن‌های کش‌شده بر اساس پراکسی (تا برای هر بار اندازه‌گیری سشن جدید نسازیم).
    private var proxySessions: [String: URLSession] = [:]

    init() {
        defaultSession = PingEngine.makeSession(proxy: nil)
    }

    /// یک بار اندازه‌گیری (در صورت تعیین پراکسی، از طریق آن).
    func ping(host: String, port: UInt16, proxy: ProxyConfig? = nil,
              timeoutMs: Int = 6000) async -> (sample: PingSample, breakdown: PingBreakdown?) {
        guard let url = makeURL(host: host, port: port) else {
            return (PingSample(date: Date(), rttMs: nil), nil)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = Double(timeoutMs) / 1000.0
        req.setValue("NetICU/1.0", forHTTPHeaderField: "User-Agent")

        let session = session(for: proxy)
        let collector = MetricsCollector()
        let start = DispatchTime.now()
        do {
            _ = try await session.data(for: req, delegate: collector)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            return (PingSample(date: Date(), rttMs: ms), collector.breakdown())
        } catch {
            return (PingSample(date: Date(), rttMs: nil), nil)
        }
    }

    /// انتخاب/ساختِ سشن مناسب برای پراکسیِ داده‌شده.
    private func session(for proxy: ProxyConfig?) -> URLSession {
        guard let proxy, proxy.isValid else { return defaultSession }
        let key = "\(proxy.type.rawValue)://\(proxy.host):\(proxy.port)"
        if let cached = proxySessions[key] { return cached }
        let s = PingEngine.makeSession(proxy: proxy)
        proxySessions[key] = s
        return s
    }

    private static func makeSession(proxy: ProxyConfig?) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 6
        cfg.waitsForConnectivity = false
        if let proxy, proxy.isValid {
            // در macOS 14+ از API مدرنِ Network استفاده می‌کنیم که SOCKS5 و HTTP را
            // واقعاً پشتیبانی می‌کند؛ در نسخه‌های قدیمی‌تر fallback به روش قدیمی.
            if #available(macOS 14.0, *), let nwPort = NWEndpoint.Port(rawValue: proxy.port) {
                let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: nwPort)
                let pc: ProxyConfiguration
                switch proxy.type {
                case .socks5: pc = ProxyConfiguration(socksv5Proxy: endpoint)
                case .http:   pc = ProxyConfiguration(httpCONNECTProxy: endpoint)
                }
                cfg.proxyConfigurations = [pc]
            } else {
                cfg.connectionProxyDictionary = PingEngine.proxyDictionary(proxy)
            }
        }
        // اجازه‌ی استفاده از گواهی نامعتبر (مثلاً وقتی هدف یک IP خام است) فقط برای سنجش زمان.
        return URLSession(configuration: cfg, delegate: InsecureTrustDelegate(), delegateQueue: nil)
    }

    private static func proxyDictionary(_ p: ProxyConfig) -> [String: Any] {
        let port = Int(p.port)
        switch p.type {
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: p.host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: p.host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: p.host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        }
    }

    /// ساخت URL از ورودی کاربر (دامنه، IP یا آدرس کامل) + پارامتر ضدکش.
    private func makeURL(host raw: String, port: UInt16) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var base: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            base = trimmed
        } else {
            let scheme = (port == 80) ? "http" : "https"
            let portPart = (port == 443 || port == 80) ? "" : ":\(port)"
            base = "\(scheme)://\(trimmed)\(portPart)/"
        }
        let sep = base.contains("?") ? "&" : "?"
        return URL(string: base + sep + "_neticu=" + String(Int(Date().timeIntervalSince1970 * 1000)))
    }
}

/// اعتماد به هر گواهی TLS — فقط برای اندازه‌گیری زمان لازم است، داده‌ی حساسی رد و بدل نمی‌شود.
private final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// دلیگیتِ هر-درخواست که متریک‌های زمان‌بندی را جمع می‌کند و به PingBreakdown تبدیل می‌کند.
private final class MetricsCollector: NSObject, URLSessionTaskDelegate {
    private var collected: URLSessionTaskMetrics?

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        collected = metrics
    }

    func breakdown() -> PingBreakdown? {
        guard let t = collected?.transactionMetrics.last else { return nil }
        func ms(_ a: Date?, _ b: Date?) -> Double? {
            guard let a, let b else { return nil }
            let v = b.timeIntervalSince(a) * 1000.0
            return v >= 0 ? v : nil
        }
        let dns  = ms(t.domainLookupStartDate, t.domainLookupEndDate)
        // بخشِ خالصِ TCP تا قبل از شروع TLS (در صورت وجود)
        let tcp  = ms(t.connectStartDate, t.secureConnectionStartDate ?? t.connectEndDate)
        let tls  = ms(t.secureConnectionStartDate, t.secureConnectionEndDate)
        let ttfb = ms(t.requestStartDate, t.responseStartDate)
        let b = PingBreakdown(dnsMs: dns, tcpMs: tcp, tlsMs: tls, ttfbMs: ttfb, date: Date())
        return b.hasAny ? b : nil
    }
}
