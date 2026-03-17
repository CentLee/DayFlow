import Foundation

protocol APIClientProtocol {
    func fetchCurrentUser() async throws -> SessionUser
    func fetchCalendars() async throws -> [CalendarSummary]
    func fetchBudget(monthKey: String) async throws -> BudgetBoardResponse
}

struct MockAPIClient: APIClientProtocol {
    func fetchCurrentUser() async throws -> SessionUser {
        SessionUser(id: "usr_001", email: "owner@dayflow.local", displayName: "DayFlow Owner")
    }

    func fetchCalendars() async throws -> [CalendarSummary] {
        [
            CalendarSummary(id: "cal_001", name: "Personal", color: "#1F6B5C", updatedAt: ISO8601DateFormatter().string(from: .now)),
            CalendarSummary(id: "cal_002", name: "Shared Home", color: "#D8A21D", updatedAt: ISO8601DateFormatter().string(from: .now))
        ]
    }

    func fetchBudget(monthKey: String) async throws -> BudgetBoardResponse {
        BudgetBoardResponse(
            month: BudgetMonth(
                id: "bmon_001",
                monthKey: monthKey,
                baseBudgetAmount: 510,
                currentCashAmount: 118,
                savingAmount: 200,
                carryOverAmount: 0,
                remainingBudgetAmount: 145,
                updatedAt: ISO8601DateFormatter().string(from: .now)
            ),
            summary: BudgetSummary(fixedCostTotal: 153, variableBucketTotal: 12, freeCashAmount: 118),
            fixedItems: [
                BudgetItem(id: "itm_001", name: "월세 및 관리비", kind: "fixed", amount: 21, enabled: true, note: nil, billingDayLabel: "20일", updatedAt: ISO8601DateFormatter().string(from: .now)),
                BudgetItem(id: "itm_002", name: "대출이자", kind: "fixed", amount: 36, enabled: true, note: nil, billingDayLabel: "5일", updatedAt: ISO8601DateFormatter().string(from: .now)),
                BudgetItem(id: "itm_003", name: "신용카드", kind: "fixed", amount: 88, enabled: true, note: nil, billingDayLabel: "26일", updatedAt: ISO8601DateFormatter().string(from: .now))
            ],
            variableBuckets: [
                BudgetBucket(id: "bkt_001", name: "점심 및 주말 식대", plannedAmount: 12, actualAmount: 0, formulaHint: "평일 1 + 주말 3", updatedAt: ISO8601DateFormatter().string(from: .now)),
                BudgetBucket(id: "bkt_002", name: "유동 금액", plannedAmount: 0, actualAmount: 0, formulaHint: nil, updatedAt: ISO8601DateFormatter().string(from: .now))
            ],
            billingReminders: [
                BudgetItem(id: "rem_001", name: "보험비 정산", kind: "reminder", amount: 0, enabled: true, note: nil, billingDayLabel: "25일", updatedAt: ISO8601DateFormatter().string(from: .now))
            ]
        )
    }
}

