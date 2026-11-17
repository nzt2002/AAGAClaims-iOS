import Foundation
import Testing
@testable import PortalKit

@Suite("Payments summary")
struct PaymentsSummaryTests {
    private func payment(_ id: String, _ date: CalendarDate?, received: Decimal, deductible: Decimal = 0, fee: Decimal, insured: Decimal) -> Payment {
        Payment(paymentsId: id, paymentsName: nil, dateOfNotice: date, netDeposit: received, insuredPayment: insured, totalRcv: nil,
                checkNumber: "100\(id)", deductible: deductible, aaFee: fee)
    }

    private let jan = CalendarDate(year: 2026, month: 1, day: 5), feb = CalendarDate(year: 2026, month: 2, day: 9)

    @Test func addsUpOldestFirstWithARunningTotal() {
        // Newest first, as the server sends them.
        let s = PaymentsSummary(payments: [
            payment("2", feb, received: 5000, fee: 500, insured: 4500),
            payment("1", jan, received: 9000, deductible: 1000, fee: 1000, insured: 8000),
        ], totalRcv: 20000, collected: 15000)
        #expect(s.rows.map(\.id) == ["1", "2"])
        #expect(s.rows.map(\.cumulative) == [10000, 15000])
        #expect(s.feeTotal == 1500)
        #expect(s.insuredTotal == 12500)
        #expect(s.deductibleTotal == 1000)
        #expect(s.receivedTotal == 14000)
    }

    @Test func sharesAndProgress() {
        let s = PaymentsSummary(payments: [payment("1", jan, received: 9000, deductible: 1000, fee: 1000, insured: 8000)], totalRcv: 20000, collected: 10000)
        #expect(s.fraction == 0.5)
        #expect(s.outstanding == 10000)
        #expect(s.share(of: s.feeTotal) == 10)
        #expect(s.share(of: s.insuredTotal) == 80)
    }

    @Test func noRcvOrPaymentsIsZeroNotACrash() {
        let s = PaymentsSummary(payments: [], totalRcv: nil, collected: nil)
        #expect(s.fraction == 0)
        #expect(s.outstanding == 0)
        #expect(s.share(of: 5) == 0)
    }

    @Test func overCollectedStopsAtFull() {
        let s = PaymentsSummary(payments: [], totalRcv: 100, collected: 150)
        #expect(s.fraction == 1)
        #expect(s.outstanding == 0)
    }
}
