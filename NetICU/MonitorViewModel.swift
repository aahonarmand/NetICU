import Foundation
import SwiftUI
import Combine
import UserNotifications

/// ترتیب نمایش مانیتورها.
enum SortOrder: String, CaseIterable {
    case manual, name, ping, quality
}

/// مدیریت حالت کل اپ: اهداف، تاریخچه‌ی نمونه‌ها، حلقه‌ی پایش و ذخیره‌سازی.
@MainActor
final class MonitorViewModel: ObservableObject {

    @Published var targets: [PingTarget] = []
    /// تاریخچه‌ی نمونه‌ها به ازای id هر هدف.
    @Published private(set) var histories: [UUID: [PingSample]] = [:]
    @Published private(set) var stats: [UUID: TargetStatistics] = [:]
    /// آخرین تجزیه‌ی زمانِ هر هدف (DNS/TCP/TLS/TTFB).
    @Published private(set) var breakdowns: [UUID: PingBreakdown] = [:]
    @Published var isMonitoring: Bool = false

    /// بازه‌ی بین هر دور اندازه‌گیری (ثانیه). با تغییر، در UserDefaults ذخیره می‌شود.
    @Published var intervalSeconds: Double {
        didSet { UserDefaults.standard.set(intervalSeconds, forKey: "intervalSeconds") }
    }
    /// ترتیب مرتب‌سازی نمایش. با تغییر، ذخیره می‌شود.
    @Published var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") }
    }

    /// بیشینه‌ی تعداد نمونه‌ی نگه‌داری‌شده برای هر هدف.
    private let maxSamples = 120

    private let engine = PingEngine()
    private var monitorTask: Task<Void, Never>?

    // آی‌پی کاربر
    @Published private(set) var publicIP: String? = nil
    @Published private(set) var localIP: String? = nil
    private var ipTask: Task<Void, Never>?

    private let storageKey = "savedTargets"

    // وضعیت هشدار به‌ازای هر هدف (برای جلوگیری از نوتیفِ تکراری)
    private struct AlertState { var breachStart: Date? = nil; var notified: Bool = false }
    private var alertStates: [UUID: AlertState] = [:]

    init() {
        let saved = UserDefaults.standard.double(forKey: "intervalSeconds")
        intervalSeconds = saved > 0 ? saved : 2.0
        sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ?? .manual
        loadTargets()
        if targets.isEmpty {
            targets = MonitorViewModel.defaultTargets
            saveTargets()
        }
    }

    // MARK: - چرخه‌ی پایش

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitorTask = Task { [weak self] in
            await self?.runLoop()
        }
        startIPRefresh()
        requestNotificationPermissionIfNeeded()
    }

    // MARK: - نوتیفیکیشن

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

    /// ارزیابی قوانین هشدار بر اساس آخرین نمونه‌ی هر هدف.
    private func evaluateAlerts(latest: [UUID: PingSample]) {
        let now = Date()
        for target in targets where target.isEnabled {
            guard let rule = target.alert else { alertStates[target.id] = nil; continue }
            guard let sample = latest[target.id] else { continue }
            // breach: پینگ بالاتر از آستانه، یا اصلاً پاسخی نیامده (تایم‌اوت)
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

    func stop() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - آی‌پی کاربر

    func startIPRefresh() {
        guard ipTask == nil else { return }
        ipTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIP()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // هر ۶۰ ثانیه
            }
        }
    }

    func refreshIP() async {
        localIP = MonitorViewModel.currentLocalIP()
        publicIP = await MonitorViewModel.fetchPublicIP()
    }

    /// آی‌پی عمومی را از چند سرویس به‌ترتیب امتحان می‌کند.
    private static func fetchPublicIP() async -> String? {
        let endpoints = ["https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"]
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg)
        for ep in endpoints {
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

    /// آی‌پی محلی (IPv4) رابط فعال شبکه.
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
                        if name.hasPrefix("en") { break } // اولویت با رابط اصلی en0/en1
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return address
    }

    private func runLoop() async {
        while !Task.isCancelled && isMonitoring {
            await runOneCycle()
            let nanos = UInt64(max(0.5, intervalSeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    /// یک دور: همه‌ی اهداف فعال را هم‌زمان پینگ می‌کند.
    private func runOneCycle() async {
        let active = targets.filter { $0.isEnabled }
        guard !active.isEmpty else { return }

        var results: [(UUID, PingSample, PingBreakdown?)] = []
        await withTaskGroup(of: (UUID, PingSample, PingBreakdown?).self) { group in
            for target in active {
                group.addTask { [engine] in
                    let r = await engine.ping(host: target.host,
                                              port: target.port,
                                              proxy: target.proxy,
                                              timeoutMs: 5000)
                    return (target.id, r.sample, r.breakdown)
                }
            }
            for await item in group { results.append(item) }
        }

        // همه‌ی تغییرات را یک‌جا اعمال می‌کنیم تا در هر چرخه فقط یک‌بار منتشر شود
        // (انتشارِ پرتکرار هم‌زمان با چیدمان می‌تواند باعث کرش شود).
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

        // ارزیابی هشدارها بر اساس آخرین نمونه‌ی هر هدف
        var latest: [UUID: PingSample] = [:]
        for (id, sample, _) in results { latest[id] = sample }
        evaluateAlerts(latest: latest)
    }

    // MARK: - دسترسی به داده

    func history(for target: PingTarget) -> [PingSample] {
        histories[target.id] ?? []
    }

    func statistics(for target: PingTarget) -> TargetStatistics {
        stats[target.id] ?? .empty
    }

    func breakdown(for target: PingTarget) -> PingBreakdown? {
        breakdowns[target.id]
    }

    /// فهرست مانیتورها بر اساس ترتیب انتخاب‌شده.
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
                return pa < pb   // کم‌ترین پینگ اول
            }
        case .quality:
            return targets.sorted { a, b in
                let sa = (stats[a.id]?.sampleCount ?? 0) > 0 ? (stats[a.id]?.score ?? -1) : -1
                let sb = (stats[b.id]?.sampleCount ?? 0) > 0 ? (stats[b.id]?.score ?? -1) : -1
                return sa > sb   // بهترین کیفیت اول
            }
        }
    }

    /// جابجایی دستیِ مانیتورها (کشیدن). ترتیبِ نمایشیِ فعلی را مبنا می‌گیرد،
    /// جابجایی را اعمال می‌کند و آن را به‌عنوان ترتیب دستیِ جدید ذخیره می‌کند.
    func moveTargets(from source: IndexSet, to destination: Int) {
        var display = sortedTargets
        display.move(fromOffsets: source, toOffset: destination)
        targets = display
        sortOrder = .manual
        saveTargets()
    }

    /// بدترین وضعیت در میان همه‌ی اهداف فعال (برای آیکون نوار منو).
    var overallStatistics: TargetStatistics? {
        let active = targets.filter { $0.isEnabled }
        let values = active.compactMap { stats[$0.id] }.filter { $0.sampleCount > 0 }
        return values.min(by: { $0.score < $1.score })
    }

    /// آمارِ مانیتورِ انتخاب‌شده برای نوار منو ("auto" = بدترین مانیتور).
    func menuBarStats(for sel: String) -> TargetStatistics? {
        if sel != "auto", let id = UUID(uuidString: sel),
           targets.contains(where: { $0.id == id }), let s = stats[id] {
            return s
        }
        return overallStatistics
    }

    // MARK: - مدیریت اهداف

    func addTarget(_ target: PingTarget) {
        targets.append(target)
        saveTargets()
    }

    func updateTarget(_ target: PingTarget) {
        guard let idx = targets.firstIndex(where: { $0.id == target.id }) else { return }
        targets[idx] = target
        alertStates[target.id] = nil   // ریست وضعیت هشدار پس از ویرایش
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

    /// پاک‌کردن تاریخچه و آمارِ یک مانیتور (بدون حذف خودِ مانیتور).
    func clearHistory(for target: PingTarget) {
        histories[target.id] = []
        stats[target.id] = .empty
        breakdowns[target.id] = nil
        alertStates[target.id] = nil
    }

    // MARK: - ذخیره‌سازی محلی

    private func saveTargets() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadTargets() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PingTarget].self, from: data) else { return }
        targets = decoded
    }

    static let defaultTargets: [PingTarget] = [
        PingTarget(name: "Google DNS", host: "8.8.8.8", port: 443),
        PingTarget(name: "Cloudflare", host: "1.1.1.1", port: 443),
        PingTarget(name: "Google", host: "google.com", port: 443)
    ]
}
