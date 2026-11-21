import Charts
import PortalKit
import SwiftUI

/// The Payments tab, as on the mobile website: how much of the Total RCV has been collected, where the money goes
/// (AA fee, insured payment, deductible), how it arrived over time, or the same as a table. Staff also get Record payment.
struct PaymentsAtAGlance: View {
    let summary: PaymentsSummary
    /// Staff: opens the payment calculator (Apply Payments).
    var onRecord: (() -> Void)? = nil

    private enum Mode: String, CaseIterable { case chart = "Chart", table = "Table" }
    @State private var mode: Mode = .chart

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                header
                if summary.totalRcv > 0 { progress }
                if !summary.rows.isEmpty {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("paymentsMode")
                    if mode == .table { table } else { charts }
                }
            }
            .cardStyle()

            HStack {
                Text(summary.rows.count == 1 ? "1 payment" : "\(summary.rows.count) payments")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if let onRecord {
                    Button(action: onRecord) { Label("Record payment", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("recordPayment")
                }
            }
            if summary.rows.isEmpty {
                Text("No payments recorded yet. Record each check from the insurer.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Collected toward Total RCV")
                        RCVHelpButton()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    (Text(PortalFormat.currency(summary.collected)).font(.title2.weight(.bold))
                     + Text(" of \(summary.totalRcv > 0 ? PortalFormat.currency(summary.totalRcv) : "no RCV set")").font(.subheadline).foregroundColor(Color.textSecondary))
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: summary.fraction).tint(PaymentColors.insured)
            Text("\(Int((summary.fraction * 100).rounded()))% collected · \(PortalFormat.currency(summary.outstanding)) outstanding")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PortalFormat.currency(summary.collected)) collected of \(PortalFormat.currency(summary.totalRcv)), \(Int((summary.fraction * 100).rounded())) percent, \(PortalFormat.currency(summary.outstanding)) outstanding")
        .accessibilityIdentifier("paymentProgress")
    }

    // MARK: Chart

    private var charts: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Where the Money Goes").font(.subheadline.weight(.semibold))
                moneyBar
                legend
            }
            if summary.rows.count >= 2 { overTime }
        }
    }

    private var slices: [(name: String, amount: Decimal, color: Color)] {
        [("AA fee", summary.feeTotal, PaymentColors.fee),
         ("Insured payment", summary.insuredTotal, PaymentColors.insured),
         ("Deductible", summary.deductibleTotal, PaymentColors.neutral)].filter { $0.1 > 0 }
    }

    private var moneyBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(slices, id: \.name) { slice in
                    let share = summary.split > 0 ? NSDecimalNumber(decimal: slice.amount / summary.split).doubleValue : 0
                    RoundedRectangle(cornerRadius: 4).fill(slice.color)
                        .frame(width: max(4, (geo.size.width - 2 * CGFloat(max(slices.count - 1, 0))) * share))
                }
            }
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AA fee \(PortalFormat.currency(summary.feeTotal)), insured payment \(PortalFormat.currency(summary.insuredTotal)), deductible \(PortalFormat.currency(summary.deductibleTotal))")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(slices, id: \.name) { slice in
                HStack(spacing: Theme.Spacing.s) {
                    RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 10, height: 10)
                    Text(slice.name).foregroundStyle(Color.textSecondary)
                    Text(PortalFormat.currency(slice.amount)).fontWeight(.semibold).monospacedDigit()
                    Text("\(summary.share(of: slice.amount))%").font(.caption).foregroundStyle(Color.textSecondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var overTime: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Collected Over Time").font(.subheadline.weight(.semibold))
            Chart {
                ForEach(Array(summary.rows.enumerated()), id: \.offset) { index, row in
                    LineMark(x: .value("Check", index), y: .value("Collected", NSDecimalNumber(decimal: row.cumulative).doubleValue))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(PaymentColors.insured)
                    PointMark(x: .value("Check", index), y: .value("Collected", NSDecimalNumber(decimal: row.cumulative).doubleValue))
                        .foregroundStyle(PaymentColors.insured)
                }
                if summary.totalRcv > 0 {
                    RuleMark(y: .value("Total RCV", NSDecimalNumber(decimal: summary.totalRcv).doubleValue))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.textSecondary)
                        .annotation(position: .top, alignment: .trailing) { Text("Total RCV").font(.caption2).foregroundStyle(Color.textSecondary) }
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, summary.rows.count - 1]) { value in
                    AxisValueLabel {
                        if let i = value.as(Int.self), summary.rows.indices.contains(i) { Text(Self.shortDay(summary.rows[i].date)).font(.caption2) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let v = value.as(Double.self) { Text(Self.compact(v)).font(.caption2) } }
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Collected so far: " + summary.rows.map { "\(Self.shortDay($0.date)) \(PortalFormat.currency($0.cumulative))" }.joined(separator: ", "))
        }
    }

    // MARK: Table

    private var table: some View {
        VStack(spacing: 0) {
            ForEach(summary.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(PortalFormat.date(row.date)).font(.subheadline.weight(.semibold))
                        if let check = row.check { Text("Check \(check)").font(.caption).foregroundStyle(Color.textSecondary) }
                        Spacer()
                        Text(PortalFormat.currency(row.total)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    HStack {
                        cell("Received", row.received)
                        cell("AA fee", row.fee)
                        cell("Insured", row.insured)
                        cell("So far", row.cumulative)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)
                .accessibilityElement(children: .combine)
                Divider()
            }
            HStack {
                Text("Total").font(.subheadline.weight(.semibold))
                Spacer()
                cell("Received", summary.receivedTotal)
                cell("AA fee", summary.feeTotal)
                cell("Insured", summary.insuredTotal)
            }
            .padding(.top, Theme.Spacing.s)
            .accessibilityElement(children: .combine)
        }
    }

    private func cell(_ title: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(PortalFormat.currency(amount)).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func shortDay(_ date: CalendarDate?) -> String {
        guard let date, let d = date.date(in: .current) else { return "No date" }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func compact(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").notation(.compactName).precision(.fractionLength(0...1)))
    }
}

/// The two series colours the website uses (blue insured payment, orange AA fee), tuned for dark mode.
enum PaymentColors {
    static let insured = Color(uiColor: BrandPalette.pair(light: (0.165, 0.471, 0.839), dark: (0.224, 0.529, 0.898)))
    static let fee = Color(uiColor: BrandPalette.pair(light: (0.922, 0.408, 0.204), dark: (0.851, 0.349, 0.149)))
    static let neutral = Color(uiColor: BrandPalette.pair(light: (0.604, 0.639, 0.698), dark: (0.357, 0.396, 0.467)))
}
