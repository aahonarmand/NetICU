import Foundation
import SwiftUI
import Combine
import UserNotifications

/// Display order of monitors.
enum SortOrder: String, CaseIterable {
    case manual, name, ping, quality
}

/// Manages the whole app's state: targets, sample history, the monitoring loop and persistence.
@MainActor
final class MonitorViewModel: ObservableObject {

    @Published var targets: [PingTarget] = []
    /// Sample history per target id.
    @Published private(set) var histories: [UUID: [PingSample]] = [:]
    @Published private(set) var stats: [UUID: TargetStatistics] = [:]
    /// Latest timing breakdown per target (DNS/TCP/TLS/TTFB).
    @Published private(set) var breakdowns: [UUID: PingBreakdown] = [:]
    @Published var isMonitoring: Bool = false

    /// Interval between measurement rounds (seconds). Persisted on change.
    @Published var intervalSeconds: Double {
        didSet { UserDefaults.standard.set(intervalSeconds, forKey: DefaultsKey.intervalSeconds) }
    }
    /// Display sort order. Persisted on change.
    @Published var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder) }
    }

    /// Maximum number of samples kept per target.
    /// Always covers at least the statistics window (2 minutes), even at short intervals (e.g. 0.5 s).
    private var maxSamples: Int {
        max(120, Int(StatisticsCalculator.statsWindowSeconds / max(0.5, intervalSeconds)) + 10)
    }

    private let engine = PingEngine()
    private var monitorTask: Task<Void, Never>?

    // MARK: User IP

    @Published private(set) var publicIP: String? = nil
    @Published private(set) var localIP: String? = nil
    private var ipTask: Task<Void, Never>?

    /// Cadence of the (opt-in) automatic public-IP refresh.
    static let ipAutoRefreshSeconds: UInt64 = 300   // 5 minutes

    /// PRIVACY: the public IP is looked up via third-party services (see `publicIPEndpoints`).
    /// Automatic polling is OFF by default — when disabled, those services are contacted
    /// only when the user presses the refresh button. Persisted on change.
    @Published var autoRefreshIP: Bool {
        didSet {
            UserDefaults.standard.set(autoRefreshIP, forKey: DefaultsKey.autoRefreshIP)
            if autoRefreshIP, isMonitoring { startIPAutoRefresh() } else { stopIPAutoRefresh() }
        }
    }

    // MARK: Alert state

    // Per-target alert state (prevents duplicate notifications).
    private struct AlertState { var breachStart: Date? = nil; var notified: Bool = false }
    private var alertStates: [UUID: AlertState] = [:]

    init() {
        let saved = UserDefaults.standard.double(forKey: DefaultsKey.intervalSeconds)
        intervalSeconds = saved > 0 ? saved : 2.0
        sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.sortOrder) ?? "") ?? .manual
        autoRefreshIP = UserDefaults.standard.bool(forKey: DefaultsKey.autoRefreshIP)
        loadTargets()
        if targets.isEmpty {
            targets = MonitorViewModel.defaultTargets
            saveTargets()
        }
    }

    // MARK: - Monitoring lifecycle

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitorTask = Task { [weak self] in
            await self?.runLoop()
        }
        // Local IP costs nothing and contacts no one; public IP only if the user opted in.
        localIP = MonitorViewModel.currentLocalIP()
        if autoRefreshIP { startIPAutoRefresh() }
        requestNotificationPermissionIfNeeded()
    }

    func stop() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
        stopIPAutoRefresh()
    }

    // MARK: - Notifications

    private var didRequestNotifPermission = false
    func requestNotificationPermissionIfNeeded() {
        guard !didRequestNotifPermission else { return }
        didRequestNotifPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Evaluates the alert rules against each target's latest sample.
    private func evaluateAlerts(latest: [UUID: PingSample]) {
        let now = Date()
        for target in targets where target.isEnabled {
            guard let rule = target.alert else { alertStates[target.id] = nil; continue }
            guard let sample = latest[target.id] else { continue }
            // breach: ping above the threshold, or no reply at all (timeout)
            let breach = (sample.rttMs == nil) || (sample.rttMs! > rule.pingThresholdMs)
            var state = alertStates[target.id] ?? AlertState()
            if breach {
                if state.breachStart == nil { state.breachStart = now }
                if let begun = state.breachStart,
                   now.timeIntervalSince(begun) >= rule.durationSeconds,
                   !state.notified {
                    let cur = sample.rttMs.map { "\(Int($0)) ms" } ?? "no response"
                    sendNotification(
                        title: "NetICU — \(target.name)",
                        body: "Ping above \(Int(rule.pingThresholdMs)) ms for \(Int(rule.durationSeconds))s (now: \(cur))"
                    )
                    state.notified = true
                }
            } else {
                state.breachStart = nil
                state.notified = false
            }
            alertStates[target.id] = state
        }
    }

    // MARK: - User IP

    private func startIPAutoRefresh() {
        guard ipTask == nil else { return }
        ipTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIP()
                try? await Task.sleep(nanoseconds: MonitorViewModel.ipAutoRefreshSeconds * 1_000_000_000)
            }
        }
    }

    private func stopIPAutoRefresh() {
        ipTask?.cancel()
        ipTask = nil
    }

    /// Manual refresh (the dashboard button) — always available regardless of the auto setting.
    func refreshIP() async {
        localIP = MonitorViewModel.currentLocalIP()
        publicIP = await MonitorViewModel.fetchPublicIP()
    }

    /// Shared session for fetching the public IP (built once instead of per request).
    private static let ipSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Third-party services used to discover the public IP (documented in the README).
    static let publicIPEndpoints = ["https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"]

    /// Tries the public-IP services in order.
    private static func fetchPublicIP() async -> String? {
        let session = ipSession
        for ep in publicIPEndpoints {
            guard let url = URL(string: ep) else { continue }
            do {
                let (data, _) = try await session.data(from: url)
                let ip = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let ip, !ip.isEmpty, ip.count <= 45 { return ip }
            } catch { continue }
        }
        return nil
    }

    /// Local (IPv4) address of the active network interface.
    private static func currentLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(bitPattern: cur.pointee.ifa_flags)
            let addr = cur.pointee.ifa_addr
            if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
               (flags & IFF_LOOPBACK) == 0,
               let addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: cur.pointee.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("utun") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                   &host, socklen_t(host.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: host)
                        if name.hasPrefix("en") { break } // prefer the primary interface (en0/en1)
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return address
    }

    // MARK: - Measurement loop

    private func runLoop() async {
        while !Task.isCancelled && isMonitoring {
            await runOneCycle()
            let nanos = UInt64(max(0.5, intervalSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    /// One round: pings all enabled targets concurrently.
    private func runOneCycle() async {
        let active = targets.filter { $0.isEnabled }
        guard !active.isEmpty else { return }

        var results: [(UUID, PingSample, PingBreakdown?)] = []
        await withTaskGroup(of: (UUID, PingSample, PingBreakdown?).self) { group in
            for target in active {
                group.addTask { [engine] in
                    let r = await engine.ping(host: target.host,
                                              port: target.port,
                                              proxy: target.proxy)
                    return (target.id, r.sample, r.breakdown)
                }
            }
            for await item in group { results.append(item) }
        }

        // Apply all changes at once so each cycle publishes only once
        // (frequent publishing during layout can cause crashes).
        var newHistories = histories
        var newStats = stats
        var newBreakdowns = breakdowns
        for (id, sample, bd) in results {
            var list = newHistories[id] ?? []
            list.append(sample)
            if list.count > maxSamples {
                list.removeFirst(list.count - maxSamples)
            }
            newHistories[id] = list
            newStats[id] = StatisticsCalculator.compute(from: list)
            if let bd {
                newBreakdowns[id] = (newBreakdowns[id] ?? PingBreakdown()).merged(with: bd)
            }
        }
        histories = newHistories
        stats = newStats
        breakdowns = newBreakdowns

        // Evaluate alerts against each target's latest sample.
        var latest: [UUID: PingSample] = [:]
        for (id, sample, _) in results { latest[id] = sample }
        evaluateAlerts(latest: latest)
    }

    // MARK: - Data access

    func history(for target: PingTarget) -> [PingSample] {
        histories[target.id] ?? []
    }

    func statistics(for target: PingTarget) -> TargetStatistics {
        stats[target.id] ?? .empty
    }

    func breakdown(for target: PingTarget) -> PingBreakdown? {
        breakdowns[target.id]
    }

    /// Monitors in the selected display order.
    var sortedTargets: [PingTarget] {
        switch sortOrder {
        case .manual:
            return targets
        case .name:
            return targets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .ping:
            return targets.sorted { a, b in
                let pa = stats[a.id]?.current ?? .greatestFiniteMagnitude
                let pb = stats[b.id]?.current ?? .greatestFiniteMagnitude
                return pa < pb   // lowest ping first
            }
        case .quality:
            return targets.sorted { a, b in
                let sa = (stats[a.id]?.sampleCount ?? 0) > 0 ? (stats[a.id]?.score ?? -1) : -1
                let sb = (stats[b.id]?.sampleCount ?? 0) > 0 ? (stats[b.id]?.score ?? -1) : -1
                return sa > sb   // best quality first
            }
        }
    }

    /// Manual reordering (drag). Takes the current display order as the base,
    /// applies the move, and saves it as the new manual order.
    func moveTargets(from source: IndexSet, to destination: Int) {
        var display = sortedTargets
        display.move(fromOffsets: source, toOffset: destination)
        targets = display
        sortOrder = .manual
        saveTargets()
    }

    /// Worst state among all enabled targets (for the menu-bar icon).
    var overallStatistics: TargetStatistics? {
        let active = targets.filter { $0.isEnabled }
        let values = active.compactMap { stats[$0.id] }.filter { $0.sampleCount > 0 }
        return values.min(by: { $0.score < $1.score })
    }

    /// Statistics of the monitor selected for the menu bar ("auto" = worst monitor).
    func menuBarStats(for sel: String) -> TargetStatistics? {
        if sel != "auto", let id = UUID(uuidString: sel),
           targets.contains(where: { $0.id == id }), let s = stats[id] {
            return s
        }
        return overallStatistics
    }

    // MARK: - Target management

    func addTarget(_ target: PingTarget) {
        targets.append(target)
        saveTargets()
    }

    func updateTarget(_ target: PingTarget) {
        guard let idx = targets.firstIndex(where: { $0.id == target.id }) else { return }
        targets[idx] = target
        alertStates[target.id] = nil   // reset alert state after an edit
        saveTargets()
        requestNotificationPermissionIfNeeded()
    }

    func removeTarget(_ target: PingTarget) {
        targets.removeAll { $0.id == target.id }
        histories[target.id] = nil
        stats[target.id] = nil
        breakdowns[target.id] = nil
        alertStates[target.id] = nil
        saveTargets()
    }

    /// Clears a monitor's history and statistics (without removing the monitor itself).
    func clearHistory(for target: PingTarget) {
        histories[target.id] = []
        stats[target.id] = .empty
        breakdowns[target.id] = nil
        alertStates[target.id] = nil
    }

    // MARK: - Local persistence

    private func saveTargets() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.savedTargets)
        }
    }

    private func loadTargets() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.savedTargets),
              let decoded = try? JSONDecoder().decode([PingTarget].self, from: data) else { return }
        targets = decoded
    }

    static let defaultTargets: [PingTarget] = [
        PingTarget(name: "Google DNS", host: "8.8.8.8", port: 443),
        PingTarget(name: "Cloudflare", host: "1.1.1.1", port: 443),
        PingTarget(name: "Google", host: "google.com", port: 443)
    ]
}
