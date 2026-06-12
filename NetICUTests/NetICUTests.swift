import XCTest
@testable import NetICU

// MARK: - StatisticsCalculator

final class StatisticsCalculatorTests: XCTestCase {

    /// Calibration reads UserDefaults (shared with the host app), so the previous
    /// values are saved here and restored in tearDown.
    private var savedDefaults: [String: Any?] = [:]
    private let calibrationKeys = [
        DefaultsKey.latencyBest, DefaultsKey.latencyWorst, DefaultsKey.lossWorst,
        DefaultsKey.weightLatency, DefaultsKey.weightJitter, DefaultsKey.weightLoss
    ]

    override func setUp() {
        super.setUp()
        for key in calibrationKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)   // force default calibration
        }
    }

    override func tearDown() {
        for key in calibrationKeys {
            if let value = savedDefaults[key] ?? nil {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedDefaults = [:]
        super.tearDown()
    }

    /// Builds samples ending `secondsAgo` seconds in the past, 0.1 s apart.
    private func samples(_ rtts: [Double?], secondsAgo: Double = 10) -> [PingSample] {
        let start = Date().addingTimeInterval(-secondsAgo)
        return rtts.enumerated().map { i, rtt in
            PingSample(date: start.addingTimeInterval(Double(i) * 0.1), rttMs: rtt)
        }
    }

    // MARK: compute

    func testComputeEmptyInputReturnsEmpty() {
        let stats = StatisticsCalculator.compute(from: [])
        XCTAssertEqual(stats.sampleCount, 0)
        XCTAssertNil(stats.current)
        XCTAssertEqual(stats.score, 0)
    }

    func testComputeBasicStats() {
        let stats = StatisticsCalculator.compute(from: samples([100, 200, 300]))
        XCTAssertEqual(stats.sampleCount, 3)
        XCTAssertEqual(stats.average ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(stats.minimum, 100)
        XCTAssertEqual(stats.maximum, 300)
        XCTAssertEqual(stats.lossPercent, 0)
    }

    func testCurrentIsLastSuccessfulSample() {
        let stats = StatisticsCalculator.compute(from: samples([100, 250, nil]))
        XCTAssertEqual(stats.current, 250)
    }

    func testLossPercent() {
        let stats = StatisticsCalculator.compute(from: samples([100, nil, 100, nil]))
        XCTAssertEqual(stats.lossPercent, 50, accuracy: 0.001)
    }

    func testSamplesOutsideWindowAreExcluded() {
        let old = samples([50], secondsAgo: StatisticsCalculator.statsWindowSeconds + 60)
        let recent = samples([100, 110])
        let stats = StatisticsCalculator.compute(from: old + recent)
        XCTAssertEqual(stats.sampleCount, 2)
        XCTAssertEqual(stats.minimum, 100)   // the old 50 ms sample must not count
    }

    // MARK: jitter

    func testJitterIsMeanAbsoluteDifference() {
        // diffs: |110-100| = 10, |90-110| = 20 → mean 15
        let j = StatisticsCalculator.jitter(of: samples([100, 110, 90]))
        XCTAssertEqual(j ?? 0, 15, accuracy: 0.001)
    }

    func testJitterSkipsFailedSamples() {
        let j = StatisticsCalculator.jitter(of: samples([100, nil, 110]))
        XCTAssertEqual(j ?? 0, 10, accuracy: 0.001)
    }

    func testJitterNeedsAtLeastTwoSuccessfulSamples() {
        XCTAssertNil(StatisticsCalculator.jitter(of: samples([100, nil])))
    }

    // MARK: percentile

    func testPercentile() {
        let values = (1...100).map(Double.init).shuffled()
        // idx = round(99 * 0.95) = 94 → sorted[94] = 95
        XCTAssertEqual(StatisticsCalculator.percentile(values, 0.95), 95)
        XCTAssertEqual(StatisticsCalculator.percentile(values, 0), 1)
        XCTAssertEqual(StatisticsCalculator.percentile(values, 1), 100)
        XCTAssertNil(StatisticsCalculator.percentile([], 0.5))
    }

    // MARK: qualityScore / scoreRamp

    func testQualityScoreWithoutDataIsZero() {
        XCTAssertEqual(StatisticsCalculator.qualityScore(latency: nil, jitter: nil,
                                                         lossPercent: 0, hasData: false), 0)
    }

    func testQualityScorePerfectConditionsIs100() {
        let s = StatisticsCalculator.qualityScore(latency: 10, jitter: 1,
                                                  lossPercent: 0, hasData: true)
        XCTAssertEqual(s, 100)
    }

    func testQualityScoreWorstConditionsIsZero() {
        let s = StatisticsCalculator.qualityScore(latency: 2000, jitter: 100,
                                                  lossPercent: 100, hasData: true)
        XCTAssertEqual(s, 0)
    }

    func testScoreRampBoundsAndMidpoint() {
        XCTAssertEqual(StatisticsCalculator.scoreRamp(value: 60, best: 60, worst: 700), 100)
        XCTAssertEqual(StatisticsCalculator.scoreRamp(value: 700, best: 60, worst: 700), 0)
        XCTAssertEqual(StatisticsCalculator.scoreRamp(value: 380, best: 60, worst: 700),
                       50, accuracy: 0.001)   // exact midpoint
    }

    func testSubScoresUseDefaultCalibration() {
        XCTAssertEqual(StatisticsCalculator.latencySubScore(10), 100)
        XCTAssertEqual(StatisticsCalculator.latencySubScore(2000), 0)
        XCTAssertEqual(StatisticsCalculator.lossSubScore(0), 100)
        XCTAssertEqual(StatisticsCalculator.lossSubScore(100), 0)
    }

    // MARK: grade

    func testGradeMapping() {
        func grade(_ score: Int) -> String {
            var s = TargetStatistics(); s.score = score; return s.grade
        }
        XCTAssertEqual(grade(100), "A")
        XCTAssertEqual(grade(85), "A")
        XCTAssertEqual(grade(70), "B")
        XCTAssertEqual(grade(50), "C")
        XCTAssertEqual(grade(30), "D")
        XCTAssertEqual(grade(0), "F")
    }
}

// MARK: - PingBreakdown

final class PingBreakdownTests: XCTestCase {

    func testMergedTakesNewValuesAndKeepsOldOnes() {
        let old = PingBreakdown(dnsMs: 10, tcpMs: 20, tlsMs: nil, ttfbMs: 40)
        let new = PingBreakdown(dnsMs: nil, tcpMs: 25, tlsMs: 30, ttfbMs: nil)
        let merged = old.merged(with: new)
        XCTAssertEqual(merged.dnsMs, 10)    // kept (new was nil)
        XCTAssertEqual(merged.tcpMs, 25)    // replaced
        XCTAssertEqual(merged.tlsMs, 30)    // filled in
        XCTAssertEqual(merged.ttfbMs, 40)   // kept
        XCTAssertEqual(merged.date, new.date)
    }

    func testBottleneckDNS() {
        let bd = PingBreakdown(dnsMs: 200, tcpMs: 50, tlsMs: nil, ttfbMs: 150)
        XCTAssertEqual(bd.bottleneck, .dns)
    }

    func testBottleneckServer() {
        // ttfb (200) > tcp (50) * 1.5 and serverThink (150) > 80
        let bd = PingBreakdown(dnsMs: nil, tcpMs: 50, tlsMs: nil, ttfbMs: 200)
        XCTAssertEqual(bd.bottleneck, .server)
    }

    func testBottleneckNetwork() {
        // ttfb (120) is not > tcp (100) * 1.5 → network
        let bd = PingBreakdown(dnsMs: nil, tcpMs: 100, tlsMs: nil, ttfbMs: 120)
        XCTAssertEqual(bd.bottleneck, .network)
    }

    func testBottleneckNoneWithoutTTFB() {
        let bd = PingBreakdown(dnsMs: 10, tcpMs: 20, tlsMs: 5, ttfbMs: nil)
        XCTAssertEqual(bd.bottleneck, PingBreakdown.Bottleneck.none)
    }

    func testBottleneckNoneOnReusedConnection() {
        // No TCP (reused connection) and no slow DNS → no confident call.
        let bd = PingBreakdown(dnsMs: nil, tcpMs: nil, tlsMs: nil, ttfbMs: 90)
        XCTAssertEqual(bd.bottleneck, PingBreakdown.Bottleneck.none)
    }
}

// MARK: - HostClassifier (TLS-bypass gating)

final class HostClassifierTests: XCTestCase {

    func testIPv4IsRawIP() {
        XCTAssertTrue(HostClassifier.isRawIPAddress("1.1.1.1"))
        XCTAssertTrue(HostClassifier.isRawIPAddress("8.8.8.8"))
        XCTAssertTrue(HostClassifier.isRawIPAddress("192.168.0.1"))
    }

    func testIPv6IsRawIP() {
        XCTAssertTrue(HostClassifier.isRawIPAddress("2606:4700:4700::1111"))
        XCTAssertTrue(HostClassifier.isRawIPAddress("::1"))
    }

    func testHostnamesAreNotRawIPs() {
        XCTAssertFalse(HostClassifier.isRawIPAddress("google.com"))
        XCTAssertFalse(HostClassifier.isRawIPAddress("1.1.1.1.example.com"))
        XCTAssertFalse(HostClassifier.isRawIPAddress(""))
        XCTAssertFalse(HostClassifier.isRawIPAddress("256.1.1.1"))   // invalid octet
    }
}
