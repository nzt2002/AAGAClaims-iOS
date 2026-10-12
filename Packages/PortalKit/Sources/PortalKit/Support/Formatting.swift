import Foundation

public enum PortalFormat {
    /// "$12,500.00". Always USD, regardless of the device region (spec §3).
    public static func currency(_ value: Decimal?, locale: Locale = .current) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "USD").locale(locale))
    }

    /// Adjuster fees are stored as a whole-number percentage (10 means 10%).
    public static func percent(_ value: Decimal?, locale: Locale = .current) -> String {
        guard let value else { return "—" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0...2)).locale(locale))
    }

    public static func date(_ value: CalendarDate?, locale: Locale = .current) -> String {
        guard let date = value?.date() else { return "—" }
        return date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }

    public static func date(_ value: Date?, locale: Locale = .current) -> String {
        guard let value else { return "—" }
        return value.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }

    public static func fileSize(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        return Int64(bytes).formatted(.byteCount(style: .file))
    }

    /// Blank strings become nil so the UI can show "—" or hide the row.
    public static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
