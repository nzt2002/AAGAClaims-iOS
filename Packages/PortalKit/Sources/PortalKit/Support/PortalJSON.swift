import Foundation

/// A date with no time or time zone, as Apex serialises `Date` fields ("2026-08-14").
/// Kept separate from `Date` so a loss date never shifts a day when shown in another time zone.
public struct CalendarDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Today, in the device's calendar.
    public static var today: CalendarDate {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return CalendarDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(string: String) {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = CalendarDate(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected yyyy-MM-dd, got \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight on this day in the given calendar's time zone, for display with `Date.FormatStyle`.
    public func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public enum PortalJSON {
    /// Decoder for every portal response. Apex serialises `Datetime` as
    /// "2026-10-01T14:22:00.000Z"; the spec's fixtures omit the milliseconds. Both are accepted.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseDateTime(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date-time \(raw)")
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func parseDateTime(_ raw: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let withoutFraction = Date.ISO8601FormatStyle()

        if let date = try? withFraction.parse(raw) { return date }
        if let date = try? withoutFraction.parse(raw) { return date }

        // Apex can also emit "+0000" offsets.
        let normalised = raw.replacingOccurrences(of: "+0000", with: "Z")
        if let date = try? withFraction.parse(normalised) { return date }
        return try? withoutFraction.parse(normalised)
    }
}
