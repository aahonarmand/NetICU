import SwiftUI

extension Color {
    /// ساخت رنگ از کد هگز عددی، مثل Color(hex: 0xF26A1E)
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue:  Double(hex & 0xFF) / 255.0,
                  opacity: alpha)
    }
}

/// پالت رنگی اپ — برگرفته از آیکون NetICU (ذغالی تیره + نارنجی).
enum Theme {
    // لهجه‌ی نارنجی آیکون
    static let accent        = Color(hex: 0xF26A1E)
    static let accentBright  = Color(hex: 0xFF8A3D)
    static let accentGlow    = Color(hex: 0xFF7A28)

    // پس‌زمینه‌ها و سطوح ذغالی
    static let bg            = Color(hex: 0x161617)
    static let bgElevated    = Color(hex: 0x1D1D20)
    static let card          = Color(hex: 0x242428)
    static let cardAlt       = Color(hex: 0x2D2D33)
    static let stroke        = Color(hex: 0x3A3A41)

    // متن
    static let textPrimary   = Color(hex: 0xF3F3F5)
    static let textSecondary = Color(hex: 0x9C9CA4)

    // رنگ‌های وضعیت کیفیت
    static let qGreen  = Color(hex: 0x35C759)
    static let qLime   = Color(hex: 0x9ED13A)
    static let qYellow = Color(hex: 0xF2C53D)
    static let qOrange = Color(hex: 0xF2851E)
    static let qRed    = Color(hex: 0xF24A3D)
    static let qGray   = Color(hex: 0x6E6E76)

    /// رنگ وضعیت بر اساس امتیاز ۰ تا ۱۰۰
    static func quality(_ score: Int) -> Color {
        switch score {
        case 85...100: return qGreen
        case 70..<85:  return qLime
        case 50..<70:  return qYellow
        case 30..<50:  return qOrange
        default:       return qRed
        }
    }

    /// گرادیان لهجه برای عناصر شاخص
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentBright, accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
