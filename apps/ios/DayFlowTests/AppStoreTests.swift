import Testing
@testable import DayFlow

@Suite
@MainActor
struct AppStoreTests {
    @Test
    func bootstrapWithoutStoredSessionShowsSignedOut() async {
        let apiClient = StubAPIClient()
        let appStore = AppStore(apiClient: apiClient)

        await appStore.bootstrap()

        #expect(appStore.sessionPhase == .signedOut)
        #expect(appStore.sessionUser == nil)
        #expect(appStore.isLoading == false)
    }

    @Test
    func loginSuccessBootstrapsSessionAndData() async {
        let apiClient = StubAPIClient()
        apiClient.loginHandler = { _, _ in
            apiClient.hasActiveSession = true
        }
        apiClient.currentSession = .sample()
        apiClient.budgetBoard = .sample(monthKey: "2026-03")

        let appStore = AppStore(apiClient: apiClient)
        appStore.loginEmail = "owner@dayflow.local"
        appStore.loginPassword = "secret1234"

        await appStore.login()

        #expect(appStore.sessionPhase == .signedIn)
        #expect(appStore.sessionUser?.email == "owner@dayflow.local")
        #expect(appStore.calendarStore.calendars.count == 2)
        #expect(appStore.budgetStore.board?.month.monthKey == "2026-03")
        #expect(appStore.authErrorMessage == nil)
    }

    @Test
    func registerFailureSurfacesAuthError() async {
        let apiClient = StubAPIClient()
        apiClient.registerHandler = { _, _, _, _ in
            throw APIClientError.server("초대 코드를 확인해 주세요.")
        }

        let appStore = AppStore(apiClient: apiClient)
        appStore.authScreen = .register
        appStore.registerEmail = "user@example.com"
        appStore.registerDisplayName = "Kakao"
        appStore.registerPassword = "secret1234"
        appStore.registerInviteCode = "wrong"

        await appStore.register()

        #expect(appStore.sessionPhase == .signedOut)
        #expect(appStore.authErrorMessage == "초대 코드를 확인해 주세요.")
        #expect(appStore.sessionUser == nil)
    }

    @Test
    func bootstrapUnauthorizedClearsSessionAndShowsMessage() async {
        let apiClient = StubAPIClient()
        apiClient.hasActiveSession = true
        apiClient.fetchCurrentSessionHandler = {
            throw APIClientError.unauthorized("invalid session")
        }

        let appStore = AppStore(apiClient: apiClient)

        await appStore.bootstrap()

        #expect(appStore.sessionPhase == .signedOut)
        #expect(appStore.bootstrapErrorMessage == "invalid session")
        #expect(apiClient.clearSessionCalled)
    }
}

private final class StubAPIClient: APIClientProtocol, @unchecked Sendable {
    var hasActiveSession = false
    var clearSessionCalled = false
    var currentSession: MeResponse?
    var budgetBoard: BudgetBoardResponse?
    var loginHandler: (@Sendable (String, String) async throws -> Void)?
    var registerHandler: (@Sendable (String, String, String, String) async throws -> Void)?
    var fetchCurrentSessionHandler: (@Sendable () async throws -> MeResponse)?

    func login(email: String, password: String) async throws {
        if let loginHandler {
            try await loginHandler(email, password)
        }
    }

    func register(email: String, displayName: String, password: String, inviteCode: String) async throws {
        if let registerHandler {
            try await registerHandler(email, displayName, password, inviteCode)
            return
        }
        hasActiveSession = true
    }

    func fetchCurrentSession() async throws -> MeResponse {
        if let fetchCurrentSessionHandler {
            return try await fetchCurrentSessionHandler()
        }
        return currentSession ?? .sample()
    }

    func fetchBudget(monthKey: String) async throws -> BudgetBoardResponse {
        budgetBoard ?? .sample(monthKey: monthKey)
    }

    func clearSession() {
        clearSessionCalled = true
        hasActiveSession = false
    }
}

private extension MeResponse {
    static func sample() -> MeResponse {
        MeResponse(
            user: SessionUser(id: "usr_001", email: "owner@dayflow.local", displayName: "DayFlow Owner"),
            ownedCalendars: [
                CalendarSummary(id: "cal_001", name: "Personal", color: "#1F6B5C", updatedAt: "2026-03-17T00:00:00Z")
            ],
            sharedCalendars: [
                CalendarSummary(id: "cal_002", name: "Shared Home", color: "#D8A21D", updatedAt: "2026-03-17T00:00:00Z")
            ],
            currentBudgetMonthKey: "2026-03"
        )
    }
}

private extension BudgetBoardResponse {
    static func sample(monthKey: String) -> BudgetBoardResponse {
        BudgetBoardResponse(
            month: BudgetMonth(
                id: "bmon_001",
                monthKey: monthKey,
                baseBudgetAmount: 510,
                currentCashAmount: 118,
                savingAmount: 200,
                carryOverAmount: 0,
                remainingBudgetAmount: 145,
                updatedAt: "2026-03-17T00:00:00Z"
            ),
            summary: BudgetSummary(fixedCostTotal: 153, variableBucketTotal: 12, freeCashAmount: 118),
            fixedItems: [
                BudgetItem(id: "itm_001", name: "월세 및 관리비", kind: "fixed", amount: 21, enabled: true, note: nil, billingDayLabel: "20일", updatedAt: "2026-03-17T00:00:00Z")
            ],
            variableBuckets: [
                BudgetBucket(id: "bkt_001", name: "점심 및 주말 식대", plannedAmount: 12, actualAmount: 0, formulaHint: "평일 1 + 주말 3", updatedAt: "2026-03-17T00:00:00Z")
            ],
            billingReminders: [
                BudgetItem(id: "rem_001", name: "보험비 정산", kind: "reminder", amount: 0, enabled: true, note: nil, billingDayLabel: "25일", updatedAt: "2026-03-17T00:00:00Z")
            ]
        )
    }
}
