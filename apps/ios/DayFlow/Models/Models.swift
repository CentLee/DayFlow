import Foundation

enum SessionPhase: Equatable {
    case launching
    case signedOut
    case signedIn
}

enum AuthScreen: String, CaseIterable, Identifiable {
    case login
    case register

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login:
            return "로그인"
        case .register:
            return "회원가입"
        }
    }
}

struct SessionUser: Identifiable, Codable {
    let id: String
    let email: String
    let displayName: String
}

struct AuthResponse: Codable {
    let user: SessionUser
    let token: String
}

struct MeResponse: Codable {
    let user: SessionUser
    let ownedCalendars: [CalendarSummary]
    let sharedCalendars: [CalendarSummary]
    let currentBudgetMonthKey: String
}

struct APIErrorResponse: Codable {
    struct Payload: Codable {
        let code: String
        let message: String
    }

    let error: Payload
}

struct CalendarSummary: Identifiable, Codable {
    let id: String
    let name: String
    let color: String
    let updatedAt: String
}

struct BudgetMonth: Codable {
    let id: String
    let monthKey: String
    let baseBudgetAmount: Int
    let currentCashAmount: Int
    let savingAmount: Int
    let carryOverAmount: Int
    let remainingBudgetAmount: Int
    let updatedAt: String
}

struct BudgetSummary: Codable {
    let fixedCostTotal: Int
    let variableBucketTotal: Int
    let freeCashAmount: Int
}

struct BudgetItem: Identifiable, Codable {
    let id: String
    var name: String
    var kind: String
    var amount: Int
    var enabled: Bool
    var note: String?
    var billingDayLabel: String?
    let updatedAt: String
}

struct BudgetBucket: Identifiable, Codable {
    let id: String
    var name: String
    var plannedAmount: Int
    var actualAmount: Int
    var formulaHint: String?
    let updatedAt: String
}

struct BudgetBoardResponse: Codable {
    let month: BudgetMonth
    let summary: BudgetSummary
    var fixedItems: [BudgetItem]
    var variableBuckets: [BudgetBucket]
    var billingReminders: [BudgetItem]
}
