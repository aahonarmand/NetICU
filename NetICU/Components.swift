import SwiftUI
import Charts

// MARK: - نقطه‌ی رنگیِ وضعیت

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 10
    var glow: Bool = true
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: glow ? color.opacity(0.7) : .clear, radius: glow ? 4 : 0)
    }
}

// MARK: - کارت آماری

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    var color: Color = Theme.textPrimary
    var help: String? = nil
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if let help {
                    Button { showHelp.toggle() } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showHelp) {
                        Text(help)
                            .font(.callout)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(width: 260)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardAlt, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - نشانِ امتیاز و درجه

struct ScoreBadge: View {
    @EnvironmentObject var loc: Localizer
    let stats: TargetStatistics
    var size: CGFloat = 70

    var body: some View {
        VStack(spacing: 2) {
            Text(stats.grade)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(stats.color)
            Text("\(loc.int(stats.score)) · \(loc.quality(stats.score))")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: max(size + 20, 90), height: size)
        .background(stats.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stats.color.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - داده‌ی نمودار روند

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double?
}

extension Array where Element == PingSample {
    var pingPoints: [TrendPoint] { map { TrendPoint(date: $0.date, value: $0.rttMs) } }
    var jitterPoints: [TrendPoint] {
        var prev: Double? = nil
        return map { s in
            guard let rtt = s.rttMs else { return TrendPoint(date: s.date, value: nil) }
            let v = prev == nil ? nil : abs(rtt - prev!)
            prev = rtt
            return TrendPoint(date: s.date, value: v)
        }
    }
}

// MARK: - نمودار روند (پینگ یا جیتر)

struct TrendChart: View {
    @EnvironmentObject var loc: Localizer
    let points: [TrendPoint]
    var color: Color
    var markLoss: Bool = false
    var height: CGFloat = 150
    var compact: Bool = false   // برای نمودارهای کوچکِ داشبورد، محور زمان پنهان می‌شود

    private var valued: [TrendPoint] { points.filter { $0.value != nil } }

    var body: some View {
        // برای نمودار پینگ، نقاطِ قطعی هم به‌حساب می‌آیند تا هنگام قطعی، نمودار
        // (خطِ صفر + نقاط قرمز) نمایش داده شود نه پیام «در حال جمع‌آوری».
        let enough = (markLoss ? points.count : valued.count) >= 2
        return Group {
            if enough {
                chart
            } else {
                placeholder
            }
        }
        .frame(height: height)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 26))
                .foregroundStyle(color.opacity(0.6))
            Text(loc.t("collecting"))
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardAlt.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                // در نمودار پینگ، نقاطِ قطعی (nil) را با مقدار صفر رسم می‌کنیم تا خط
                // هنگام قطعی واقعاً به پایین بیفتد (به‌جای پریدن از روی قطعی).
                let lineY: Double? = p.value ?? (markLoss ? 0 : nil)
                if let lineY {
                    LineMark(x: .value("t", p.date), y: .value("v", lineY))
                        .interpolationMethod(markLoss ? .linear : .monotone)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(x: .value("t", p.date), y: .value("v", lineY))
                        .interpolationMethod(markLoss ? .linear : .monotone)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                }
                if markLoss, p.value == nil {
                    PointMark(x: .value("t", p.date), y: .value("v", 0))
                        .foregroundStyle(Theme.qRed)
                        .symbolSize(26)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 2 : 3)) { value in
                AxisGridLine().foregroundStyle(Theme.stroke.opacity(0.5))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(loc.n0(d))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            if !compact {
                // فقط ساعت و دقیقه (بدون ثانیه) و تعداد کم برچسب تا روی هم نیفتند
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke.opacity(0.35))
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}
