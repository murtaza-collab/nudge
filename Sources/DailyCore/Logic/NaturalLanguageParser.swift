import Foundation

/// The result of parsing quick-add text.
public struct ParsedInput: Equatable, Sendable {
    public var title: String
    public var dueDay: DayKey?
    public var dueMinutes: Int?
    public var recurrence: Recurrence?
    /// "#work" → "work". Matched to (or creates) a category when the task is added.
    public var categoryTag: String?

    public init(title: String, dueDay: DayKey? = nil, dueMinutes: Int? = nil, recurrence: Recurrence? = nil, categoryTag: String? = nil) {
        self.title = title
        self.dueDay = dueDay
        self.dueMinutes = dueMinutes
        self.recurrence = recurrence
        self.categoryTag = categoryTag
    }

    public var hasSchedule: Bool { dueDay != nil || dueMinutes != nil || recurrence != nil }
    /// Anything beyond the title was recognized.
    public var hasDetails: Bool { hasSchedule || categoryTag != nil }
}

/// Practical natural-language parsing for quick add: "Call Alex tomorrow 11am",
/// "Review metrics every Monday 10am".
///
/// Deliberately conservative:
/// - Only phrases at the **start or end** of the text are read, so "Prepare Monday report"
///   stays a title while "Prepare report Monday" gets a due date.
/// - Ambiguous input is left in the title rather than guessed: "at 5:30" (am or pm?) is not
///   parsed, "5:30pm" and "17:30" are.
/// - If nothing would be left for the title, the text is kept as-is.
public struct NaturalLanguageParser: Sendable {
    public var calendar: Calendar
    /// Decides day/month order for numeric dates like 5/10.
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    public func parse(_ text: String, now: Date = Date()) -> ParsedInput {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let literal = ParsedInput(title: original)
        let context = Context(today: DayKey(now, calendar: calendar), now: now, calendar: calendar, dayFirst: dayFirst)

        // "#work" may appear anywhere: the # makes it explicit. The first one is used.
        let (withoutTag, tag) = Self.extractTag(original)
        var remaining = withoutTag
        var found = Found()
        // Peel phrases off the end, then off the start, until nothing more matches.
        for side in [Side.end, .start] {
            var progress = true
            while progress {
                progress = false
                for rule in Self.rules where found.canAccept(rule.kind) {
                    guard let (range, match) = rule.match(in: remaining, side: side),
                          let effect = rule.handler(Captures(match: match, text: remaining), context)
                    else { continue }
                    found.apply(effect, kind: rule.kind)
                    remaining = side == .end
                        ? String(remaining[..<range.lowerBound])
                        : String(remaining[range.upperBound...])
                    remaining = Self.cleanTitle(remaining)
                    progress = true
                    break
                }
            }
        }

        guard found.any || tag != nil, !remaining.isEmpty else { return literal }
        var result = resolve(found, title: remaining, context: context)
        result.categoryTag = tag
        return result
    }

    /// The day named by `text` when it is only a date phrase ("tomorrow", "oct 1"), for search.
    public func day(inQuery text: String, now: Date = Date()) -> DayKey? {
        // Parsing needs a title to keep; use a placeholder and require that nothing else remains.
        let parsed = parse("_ " + text, now: now)
        return parsed.title == "_" && parsed.dueMinutes == nil && parsed.recurrence == nil ? parsed.dueDay : nil
    }

    private static let tagRegex = try! NSRegularExpression(pattern: "(?:^|\\s)#([\\p{L}\\p{N}_-]+)(?=\\s|$)")

    /// Removes the first "#tag" that contains a letter ("#123" is an issue number, not a category).
    public static func extractTag(_ text: String) -> (String, String?) {
        let range = NSRange(text.startIndex..., in: text)
        for match in tagRegex.matches(in: text, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text) else { continue }
            let tag = String(text[tagRange])
            guard tag.contains(where: \.isLetter) else { continue }
            let without = (text[..<whole.lowerBound] + " " + text[whole.upperBound...])
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return (cleanTitle(without), tag)
        }
        return (text, nil)
    }

    /// The partial tag being typed at the end of `text` ("Logo #ac" → "ac"), for completion.
    public static func trailingTagPrefix(_ text: String) -> String? {
        guard let hash = text.lastIndex(of: "#") else { return nil }
        let before = text[..<hash]
        guard before.isEmpty || before.last?.isWhitespace == true else { return nil }
        let prefix = text[text.index(after: hash)...]
        guard !prefix.contains(where: \.isWhitespace) else { return nil }
        return String(prefix)
    }

    /// Turns the collected pieces into a due day/time.
    private func resolve(_ found: Found, title: String, context: Context) -> ParsedInput {
        var day = found.day
        let minutes = found.minutes
        var recurrence = found.recurrence

        if let rule = recurrence {
            if let day {
                recurrence = rule.anchored(to: day, calendar: calendar)
            } else {
                // First occurrence from today, or tomorrow if today's time has already passed.
                var start = context.today
                if let minutes, minutes <= context.minutesNow { start = start.adding(days: 1, calendar: calendar) }
                let first = rule.firstOccurrence(onOrAfter: start, calendar: calendar)
                // Implicit details ("every week") come from the first day it applies.
                let anchored = rule.anchored(to: first, calendar: calendar)
                day = anchored.firstOccurrence(onOrAfter: start, calendar: calendar)
                recurrence = anchored
            }
        } else if day == nil, let minutes {
            // Time only: today, or tomorrow if that time has passed.
            day = minutes > context.minutesNow ? context.today : context.today.adding(days: 1, calendar: calendar)
        }
        return ParsedInput(title: title, dueDay: day, dueMinutes: minutes, recurrence: recurrence)
    }

    private var dayFirst: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let d = format.firstIndex(of: "d"), let m = format.firstIndex(of: "M") else { return false }
        return d < m
    }

    static func cleanTitle(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = result.last, ",;:-–—".contains(last) {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}

// MARK: - Rules

private enum Side { case start, end }

private enum Kind { case time, date, dateTime, recurrence }

private enum Effect {
    case time(Int)
    case day(DayKey)
    case dayTime(DayKey, Int)
    case recurrence(Recurrence)
}

private struct Found {
    var day: DayKey?
    var minutes: Int?
    var recurrence: Recurrence?

    var any: Bool { day != nil || minutes != nil || recurrence != nil }

    func canAccept(_ kind: Kind) -> Bool {
        switch kind {
        case .time: minutes == nil
        case .date: day == nil
        case .dateTime: day == nil && minutes == nil
        case .recurrence: recurrence == nil
        }
    }

    mutating func apply(_ effect: Effect, kind: Kind) {
        switch effect {
        case .time(let m): minutes = m
        case .day(let d): day = d
        case .dayTime(let d, let m): day = d; minutes = m
        case .recurrence(let r): recurrence = r
        }
    }
}

private struct Context {
    let today: DayKey
    let now: Date
    let calendar: Calendar
    let dayFirst: Bool

    var minutesNow: Int {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

private struct Captures {
    let match: NSTextCheckingResult
    let text: String

    subscript(name: String) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange]).lowercased()
    }
}

/// Immutable once built; NSRegularExpression is safe to use from multiple threads.
private struct Rule: @unchecked Sendable {
    let kind: Kind
    let endRegex: NSRegularExpression
    let startRegex: NSRegularExpression
    let handler: @Sendable (Captures, Context) -> Effect?

    init(_ kind: Kind, _ pattern: String, handler: @escaping @Sendable (Captures, Context) -> Effect?) {
        self.kind = kind
        self.endRegex = try! NSRegularExpression(pattern: "(?:^|\\s)(?:\(pattern))[\\s,.!?]*$", options: [.caseInsensitive])
        self.startRegex = try! NSRegularExpression(pattern: "^\\s*(?:\(pattern))(?=[\\s,]|$)", options: [.caseInsensitive])
        self.handler = handler
    }

    func match(in text: String, side: Side) -> (Range<String.Index>, NSTextCheckingResult)? {
        let regex = side == .end ? endRegex : startRegex
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange), let range = Range(match.range, in: text) else { return nil }
        return (range, match)
    }
}

private let weekdayPattern = "sun(?:day)?|mon(?:day)?|tue(?:s|sday)?|wed(?:s|nesday)?|thu(?:r|rs|rsday)?|fri(?:day)?|sat(?:urday)?"
private let monthPattern = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
private let numberWordPattern = "\\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten"
private let dayPrefix = "(?:(?:on|by|due(?:\\s+on)?)\\s+)?"
private let ordinalSuffix = "(?:st|nd|rd|th)?"

private func weekdayNumber(_ name: String) -> Int? {
    let prefixes = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
    return prefixes[String(name.lowercased().prefix(3))]
}

private func monthNumber(_ name: String) -> Int? {
    let prefixes = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    return prefixes.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
}

private func number(_ word: String?) -> Int? {
    guard let word else { return nil }
    let words = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
    return words[word] ?? Int(word)
}

private func ordinalNumber(_ word: String) -> Int? {
    switch word {
    case "first", "1st": 1
    case "second", "2nd": 2
    case "third", "3rd": 3
    case "fourth", "4th": 4
    case "last": -1
    default: nil
    }
}

/// A valid calendar date, or nil (e.g. Feb 30). Without a year, a date already past rolls to next year.
private func validDay(year: Int?, month: Int, day: Int, context: Context) -> DayKey? {
    let resolvedYear = year.map { $0 < 100 ? 2000 + $0 : $0 } ?? context.today.year
    let key = DayKey(year: resolvedYear, month: month, day: day)
    guard (1...12).contains(month), (1...31).contains(day),
          DayKey(key.startDate(calendar: context.calendar), calendar: context.calendar) == key else { return nil }
    if year == nil && key < context.today {
        return validDay(year: resolvedYear + 1, month: month, day: day, context: context)
    }
    return key
}

/// Days from today to the next `weekday`; 0 only when `allowToday`.
private func daysUntil(_ weekday: Int, from today: DayKey, allowToday: Bool, calendar: Calendar) -> Int {
    let days = (weekday - today.weekday(calendar: calendar) + 7) % 7
    return days == 0 && !allowToday ? 7 : days
}

private func weekdayList(_ text: String) -> [Int] {
    let regex = try! NSRegularExpression(pattern: weekdayPattern, options: [.caseInsensitive])
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range, in: text).flatMap { weekdayNumber(String(text[$0])) }
    }
}

extension NaturalLanguageParser {
    fileprivate static let rules: [Rule] = recurrenceRules + dateTimeRules + dateRules + timeRules

    // Recurrence is tried first so "every Monday" isn't read as the date "Monday".
    private static let recurrenceRules: [Rule] = [
        Rule(.recurrence, "every\\s*day|daily|everyday") { _, _ in .recurrence(.daily) },
        Rule(.recurrence, "every\\s+other\\s+day") { _, _ in .recurrence(Recurrence(frequency: .daily, interval: 2)) },
        Rule(.recurrence, "every\\s+(?<n>\\d+)\\s+days") { c, _ in
            number(c["n"]).map { .recurrence(Recurrence(frequency: .daily, interval: $0)) }
        },
        Rule(.recurrence, "every\\s+(?:week|work)\\s*day|weekdays") { _, _ in .recurrence(.weekdaysOnly) },
        Rule(.recurrence, "every\\s+(?<ord>first|1st|second|2nd|third|3rd|fourth|4th|last)\\s+(?<wd>\(weekdayPattern))(?:\\s+of\\s+(?:the|every|each)\\s+month)?") { c, _ in
            guard let ordinal = c["ord"].flatMap(ordinalNumber), let weekday = c["wd"].flatMap(weekdayNumber) else { return nil }
            return .recurrence(Recurrence(frequency: .monthly, ordinal: ordinal, ordinalWeekday: weekday))
        },
        Rule(.recurrence, "every\\s+(?<other>other\\s+)?(?<days>(?:\(weekdayPattern))(?:\\s*(?:,|and|&)\\s*(?:\(weekdayPattern)))*)") { c, _ in
            let days = weekdayList(c["days"] ?? "")
            guard !days.isEmpty else { return nil }
            return .recurrence(Recurrence(frequency: .weekly, interval: c["other"] == nil ? 1 : 2, weekdays: days))
        },
        Rule(.recurrence, "every\\s+(?:(?<n>\\d+)\\s+weeks|(?<other>other\\s+)?week)(?:\\s+on\\s+(?<days>(?:\(weekdayPattern))(?:\\s*(?:,|and|&)\\s*(?:\(weekdayPattern)))*))?|weekly") { c, _ in
            let interval = number(c["n"]) ?? (c["other"] == nil ? 1 : 2)
            return .recurrence(Recurrence(frequency: .weekly, interval: interval, weekdays: weekdayList(c["days"] ?? "")))
        },
        Rule(.recurrence, "(?:every\\s+(?:(?<n>\\d+)\\s+months|(?<other>other\\s+)?month)|monthly)(?:\\s+on\\s+the\\s+(?<dom>\\d{1,2})\(ordinalSuffix))?") { c, _ in
            let interval = number(c["n"]) ?? (c["other"] == nil ? 1 : 2)
            let day = c["dom"].flatMap { Int($0) }
            if let day, !(1...31).contains(day) { return nil }
            return .recurrence(Recurrence(frequency: .monthly, interval: interval, monthDay: day))
        },
        Rule(.recurrence, "every\\s+(?<dom>\\d{1,2})(?:st|nd|rd|th)(?:\\s+of\\s+(?:the|every|each)\\s+month)?") { c, _ in
            guard let day = c["dom"].flatMap({ Int($0) }), (1...31).contains(day) else { return nil }
            return .recurrence(Recurrence(frequency: .monthly, monthDay: day))
        },
    ]

    private static let dateTimeRules: [Rule] = [
        Rule(.dateTime, "in\\s+(?<n>\(numberWordPattern))\\s+(?<unit>min(?:ute)?s?|h(?:ou)?rs?|hours?)") { c, ctx in
            guard let n = number(c["n"]), n > 0, let unit = c["unit"] else { return nil }
            let seconds = Double(n) * (unit.hasPrefix("h") ? 3600 : 60)
            // Round up to the next whole minute.
            let raw = ctx.now.addingTimeInterval(seconds)
            let date = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
            let parts = ctx.calendar.dateComponents([.hour, .minute], from: date)
            return .dayTime(DayKey(date, calendar: ctx.calendar), (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        },
    ]

    private static let dateRules: [Rule] = [
        Rule(.date, "\(dayPrefix)(?:today|tonight)") { _, ctx in .day(ctx.today) },
        Rule(.date, "\(dayPrefix)(?:the\\s+)?day\\s+after\\s+tomorrow") { _, ctx in .day(ctx.today.adding(days: 2, calendar: ctx.calendar)) },
        // Includes common misspellings: tommorow, tomorow, tommorrow.
        Rule(.date, "\(dayPrefix)(?:tom+or+ow|tmrw|tmr)") { _, ctx in .day(ctx.today.adding(days: 1, calendar: ctx.calendar)) },
        Rule(.date, "\(dayPrefix)next\\s+week") { _, ctx in
            .day(ctx.today.adding(days: daysUntil(2, from: ctx.today, allowToday: false, calendar: ctx.calendar), calendar: ctx.calendar))
        },
        Rule(.date, "in\\s+(?<n>\(numberWordPattern))\\s+(?<unit>days?|weeks?|months?)") { c, ctx in
            guard let n = number(c["n"]), n > 0, let unit = c["unit"] else { return nil }
            if unit.hasPrefix("month") {
                guard let date = ctx.calendar.date(byAdding: .month, value: n, to: ctx.today.startDate(calendar: ctx.calendar)) else { return nil }
                return .day(DayKey(date, calendar: ctx.calendar))
            }
            return .day(ctx.today.adding(days: n * (unit.hasPrefix("week") ? 7 : 1), calendar: ctx.calendar))
        },
        Rule(.date, "(?:(?<pre>on|by|due(?:\\s+on)?)\\s+)?(?:(?<mod>this|next)\\s+)?(?<wd>\(weekdayPattern))") { c, ctx in
            guard let name = c["wd"], let weekday = weekdayNumber(name) else { return nil }
            // Short forms ("sun", "sat", "wed") are ordinary words too; only read them with a lead-in.
            if !name.hasSuffix("day") && c["pre"] == nil && c["mod"] == nil { return nil }
            let days = daysUntil(weekday, from: ctx.today, allowToday: c["mod"] == "this", calendar: ctx.calendar)
            return .day(ctx.today.adding(days: days, calendar: ctx.calendar))
        },
        Rule(.date, "\(dayPrefix)(?<month>\(monthPattern))\\.?\\s+(?<day>\\d{1,2})\(ordinalSuffix)(?:,?\\s+(?<year>\\d{4}))?") { c, ctx in
            guard let month = c["month"].flatMap(monthNumber), let day = c["day"].flatMap({ Int($0) }) else { return nil }
            return validDay(year: c["year"].flatMap { Int($0) }, month: month, day: day, context: ctx).map(Effect.day)
        },
        Rule(.date, "\(dayPrefix)(?:the\\s+)?(?<day>\\d{1,2})\(ordinalSuffix)\\s+(?:of\\s+)?(?<month>\(monthPattern))\\.?(?:,?\\s+(?<year>\\d{4}))?") { c, ctx in
            guard let month = c["month"].flatMap(monthNumber), let day = c["day"].flatMap({ Int($0) }) else { return nil }
            return validDay(year: c["year"].flatMap { Int($0) }, month: month, day: day, context: ctx).map(Effect.day)
        },
        Rule(.date, "\(dayPrefix)(?<y>\\d{4})-(?<m>\\d{1,2})-(?<d>\\d{1,2})") { c, ctx in
            guard let y = c["y"].flatMap({ Int($0) }), let m = c["m"].flatMap({ Int($0) }), let d = c["d"].flatMap({ Int($0) }) else { return nil }
            return validDay(year: y, month: m, day: d, context: ctx).map(Effect.day)
        },
        // Numeric dates need a lead-in or a year, so scores like "4/5" aren't read as dates.
        Rule(.date, "(?:(?<pre>on|by|due(?:\\s+on)?)\\s+)?(?<a>\\d{1,2})/(?<b>\\d{1,2})(?:/(?<y>\\d{2}|\\d{4}))?") { c, ctx in
            guard c["pre"] != nil || c["y"] != nil else { return nil }
            guard let a = c["a"].flatMap({ Int($0) }), let b = c["b"].flatMap({ Int($0) }) else { return nil }
            let (day, month) = ctx.dayFirst ? (a, b) : (b, a)
            return validDay(year: c["y"].flatMap { Int($0) }, month: month, day: day, context: ctx).map(Effect.day)
        },
    ]

    private static let timeRules: [Rule] = [
        // "3pm", "3:30 pm", "11 a.m.", and "3p" (single letter only when attached).
        Rule(.time, "(?:at\\s+|@\\s*)?(?<h>\\d{1,2})(?:[:.](?<m>[0-5]\\d))?(?:\\s*(?<mer>a\\.?m\\.?|p\\.?m\\.?)|(?<short>[ap]))") { c, _ in
            guard let h = c["h"].flatMap({ Int($0) }), (1...12).contains(h), let meridiem = c["mer"] ?? c["short"] else { return nil }
            let minute = c["m"].flatMap { Int($0) } ?? 0
            let hour = h % 12 + (meridiem.hasPrefix("p") ? 12 : 0)
            return .time(hour * 60 + minute)
        },
        // 24-hour times only when unambiguous: 13:00–23:59, 12:xx, or a leading zero ("09:30").
        // "at 5:30" could be morning or evening, so it's left in the title.
        Rule(.time, "(?:at\\s+|@\\s*)?(?<h>\\d{1,2})[:.](?<m>[0-5]\\d)") { c, _ in
            guard let hourText = c["h"], let h = Int(hourText), h <= 23, let m = c["m"].flatMap({ Int($0) }) else { return nil }
            guard h >= 12 || (hourText.count == 2 && hourText.hasPrefix("0")) else { return nil }
            return .time(h * 60 + m)
        },
        Rule(.time, "(?:at\\s+)?noon|midday") { _, _ in .time(12 * 60) },
    ]
}
