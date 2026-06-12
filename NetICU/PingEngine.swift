import Foundation
import Network

/// Single source of truth for probe timeouts.
enum ProbeTimeout {
    static let seconds: Double = 5
    static var milliseconds: Int { Int(seconds * 1000) }
}

/// Connection-quality measurement engine.
///
/// Instead of timing a raw TCP handshake, it sends a real HTTP(S) request to the target
/// and measures the response time. The reason: on some networks (e.g. behind transparent
/// proxies/middleboxes) the TCP handshake is answered locally and instantly, so its time
/// is nearly zero. An HTTP request must travel to the actual server and back, producing
/// a real, meaningful number.
actor PingEngine {

    private let defaultSession: URLSession
    /// Sessions cached per proxy (so we don't build a new session for every measurement).
    private var proxySessions: [String: URLSession] = [:]

    init() {
        defaultSession = PingEngine.makeSession(proxy: nil)
    }

    /// One measurement (through the given proxy, if any).
    func ping(host: String, port: UInt16, proxy: ProxyConfig? = nil,
              timeoutMs: Int = ProbeTimeout.milliseconds) async -> (sample: PingSample, breakdown: PingBreakdown?) {
        guard let url = makeURL(host: host, port: port) else {
            return (PingSample(date: Date(), rttMs: nil), nil)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = Double(timeoutMs) / 1000.0
        req.setValue("NetICU/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

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

    /// Picks/builds the right session for the given proxy.
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
        cfg.timeoutIntervalForRequest = ProbeTimeout.seconds
        cfg.timeoutIntervalForResource = ProbeTimeout.seconds
        cfg.waitsForConnectivity = false
        if let proxy, proxy.isValid {
            // On macOS 14+ we use the modern Network API, which properly supports
            // SOCKS5 and HTTP; on older versions we fall back to the legacy dictionary.
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
        return URLSession(configuration: cfg, delegate: ProbeTrustDelegate(), delegateQueue: nil)
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

    /// Builds a URL from user input (domain, IP or full URL) + a cache-busting parameter.
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

/// Host-string classification helpers.
enum HostClassifier {
    /// True if the string parses as a literal IPv4 or IPv6 address.
    static func isRawIPAddress(_ host: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return host.withCString { cs in
            inet_pton(AF_INET, cs, &v4) == 1 || inet_pton(AF_INET6, cs, &v6) == 1
        }
    }
}

/// TLS trust policy for probe requests.
///
/// THREAT MODEL: probes are HEAD requests that carry no user data and whose responses
/// are discarded — only timing is measured. Certificate validation is bypassed ONLY
/// when the probed host is a raw IP address (e.g. "1.1.1.1"), because public CAs
/// rarely issue certificates for bare IPs and such targets would otherwise be
/// unmeasurable over HTTPS. For named hosts (and anything going through a proxy to a
/// named host) the system's default certificate validation applies unchanged.
/// See SECURITY.md for the full rationale.
private final class ProbeTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              HostClassifier.isRawIPAddress(challenge.protectionSpace.host) else {
            // Named host (or non-server-trust challenge): default system validation.
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Raw-IP target: accept the certificate; we only measure timing.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

/// Per-request delegate that collects timing metrics and converts them to a PingBreakdown.
/// (Writes happen on the delegate queue and reads after the request finishes; the lock
/// makes the access safe.)
private final class MetricsCollector: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var collected: URLSessionTaskMetrics?

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        collected = metrics
        lock.unlock()
    }

    func breakdown() -> PingBreakdown? {
        lock.lock()
        let metrics = collected
        lock.unlock()
        guard let t = metrics?.transactionMetrics.last else { return nil }
        func ms(_ a: Date?, _ b: Date?) -> Double? {
            guard let a, let b else { return nil }
            let v = b.timeIntervalSince(a) * 1000.0
            return v >= 0 ? v : nil
        }
        let dns  = ms(t.domainLookupStartDate, t.domainLookupEndDate)
        // The pure TCP part, up to the start of TLS (when present).
        let tcp  = ms(t.connectStartDate, t.secureConnectionStartDate ?? t.connectEndDate)
        let tls  = ms(t.secureConnectionStartDate, t.secureConnectionEndDate)
        let ttfb = ms(t.requestStartDate, t.responseStartDate)
        let b = PingBreakdown(dnsMs: dns, tcpMs: tcp, tlsMs: tls, ttfbMs: ttfb, date: Date())
        return b.hasAny ? b : nil
    }
}
