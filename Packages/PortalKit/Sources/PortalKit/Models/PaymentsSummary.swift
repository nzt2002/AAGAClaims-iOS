import Foundation

/// The Payments tab "at a glance", worked out the way the website does it: how much of the Total RCV has been collected,
/// where the money goes (AA fee, insured payment, deductible) and how it arrived check by check.
public struct PaymentsSummary: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let date: CalendarDate?
        public let check: String?
        /// What the check paid, without the deductible.
        public let received: Decimal
        /// Received plus the deductible: what this check added to the money collected.
        public let total: Decimal
        public let fee: Decimal
        public let insured: Decimal
        public let deductible: Decimal
        /// Collected so far, up to and including this check.
        public let cumulative: Decimal
    }

    /// Oldest first.
    public let rows: [Row]
    public let totalRcv: Decimal
    public let collected: Decimal
    public let feeTotal: Decimal
    public let insuredTotal: Decimal
    public let deductibleTotal: Decimal

    public init(payments: [Payment], totalRcv: Decimal?, collected: Decimal?) {
        let sorted = payments.sorted { ($0.dateOfNotice ?? CalendarDate(year: 0, month: 0, day: 0)) < ($1.dateOfNotice ?? CalendarDate(year: 0, month: 0, day: 0)) }
        var running: Decimal = 0
        rows = sorted.map { p in
            let received = p.netDeposit ?? 0, deductible = p.deductible ?? 0
            running += received + deductible
            return Row(id: p.paymentsId, date: p.dateOfNotice, check: p.checkNumber.flatMap { $0.isEmpty ? nil : $0 },
                       received: received, total: received + deductible, fee: p.aaFee ?? 0, insured: p.insuredPayment ?? 0,
                       deductible: deductible, cumulative: running)
        }
        self.totalRcv = totalRcv ?? 0
        self.collected = collected ?? running
        feeTotal = rows.reduce(0) { $0 + $1.fee }
        insuredTotal = rows.reduce(0) { $0 + $1.insured }
        deductibleTotal = rows.reduce(0) { $0 + $1.deductible }
    }

    public var receivedTotal: Decimal { rows.reduce(0) { $0 + $1.received } }

    /// 0...1 of the Total RCV collected.
    public var fraction: Double {
        guard totalRcv > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: collected / totalRcv).doubleValue, 0), 1)
    }

    public var outstanding: Decimal { max(totalRcv - collected, 0) }

    /// Everything collected, so each share is a part of it.
    public var split: Decimal { feeTotal + insuredTotal + deductibleTotal }

    public func share(of amount: Decimal) -> Int {
        guard split > 0 else { return 0 }
        return Int((NSDecimalNumber(decimal: amount / split).doubleValue * 100).rounded())
    }
}
