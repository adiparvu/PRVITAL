import Foundation

/// Turns two periods of statistics into the two-or-three plain sentences a
/// person would actually tell themselves — "time in range rose", "fewer lows",
/// "Tuesday was the tough day" — instead of leaving them to diff the numbers.
/// Pure and deterministic; every threshold is a named constant.
enum PeriodNarrative {

    /// A TIR / variability move smaller than this (percentage points) is noise,
    /// not news.
    static let meaningfulPoints = 3.0

    /// Up to three sentences, most important first. Empty when there is no
    /// previous period to compare against or too little data to say anything.
    static func sentences(
        current: PeriodStatistics,
        previous: PeriodStatistics?,
        dailyDays: [DayTIR],
        calendar: Calendar = .current
    ) -> [String] {
        guard current.readingCount > 0 else { return [] }
        var out: [String] = []

        if let previous, previous.readingCount > 0 {
            out.append(tirSentence(current: current, previous: previous))
            if let lows = lowsSentence(current: current, previous: previous) {
                out.append(lows)
            }
            if let variability = variabilitySentence(current: current, previous: previous) {
                out.append(variability)
            }
        }
        if let toughest = toughestDaySentence(dailyDays: dailyDays, calendar: calendar) {
            out.append(toughest)
        }
        return Array(out.prefix(3))
    }

    private static func tirSentence(current: PeriodStatistics, previous: PeriodStatistics) -> String {
        let nowPct = Int((current.timeInRange * 100).rounded())
        let delta = (current.timeInRange - previous.timeInRange) * 100
        if delta >= meaningfulPoints {
            return String(localized: "Time in range rose \(Int(delta.rounded())) points to \(nowPct)%.")
        }
        if delta <= -meaningfulPoints {
            return String(localized: "Time in range fell \(Int((-delta).rounded())) points to \(nowPct)%.")
        }
        return String(localized: "Time in range held steady at \(nowPct)%.")
    }

    private static func lowsSentence(current: PeriodStatistics, previous: PeriodStatistics) -> String? {
        let now = current.hypoEvents
        let before = previous.hypoEvents
        if now == 0 && before == 0 { return nil }
        if now == 0 {
            return String(localized: "No lows this period — last period had \(before).")
        }
        if now < before {
            return String(localized: "\(now) lows, down from \(before).")
        }
        if now > before {
            return String(localized: "\(now) lows, up from \(before).")
        }
        return nil
    }

    private static func variabilitySentence(current: PeriodStatistics, previous: PeriodStatistics) -> String? {
        let delta = (current.coefficientOfVariation - previous.coefficientOfVariation) * 100
        if delta <= -meaningfulPoints {
            return String(localized: "Glucose is steadier — variability down \(Int((-delta).rounded())) points.")
        }
        if delta >= meaningfulPoints {
            return String(localized: "Glucose swung more — variability up \(Int(delta.rounded())) points.")
        }
        return nil
    }

    /// The weekday that repeatedly underperforms — only named when it has at
    /// least two full days of data and sits clearly below the rest.
    private static func toughestDaySentence(dailyDays: [DayTIR], calendar: Calendar) -> String? {
        let meaningful = dailyDays.filter { $0.readingCount >= 24 }
        guard meaningful.count >= 7 else { return nil }

        var byWeekday: [Int: [Double]] = [:]
        for day in meaningful {
            byWeekday[calendar.component(.weekday, from: day.day), default: []].append(day.timeInRange)
        }
        let averages = byWeekday.compactMapValues { tirs -> Double? in
            tirs.count >= 2 ? tirs.reduce(0, +) / Double(tirs.count) : nil
        }
        guard averages.count >= 2,
              let worst = averages.min(by: { $0.value < $1.value }) else { return nil }
        let rest = averages.filter { $0.key != worst.key }.values
        let restAverage = rest.reduce(0, +) / Double(rest.count)
        guard restAverage - worst.value >= meaningfulPoints / 100 else { return nil }

        let name = calendar.standaloneWeekdaySymbols[worst.key - 1]
        let pct = Int((worst.value * 100).rounded())
        return String(localized: "\(name) is the toughest day (\(pct)% in range).")
    }
}
