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
    func registerSuccessBootstrapsSessionAndData() async {
        let apiClient = StubAPIClient()
        apiClient.registerHandler = { _, _, _, _ in
            apiClient.hasActiveSession = true
        }
        apiClient.currentSession = .sample()
        apiClient.budgetBoard = .sample(monthKey: "2026-03")

        let appStore = AppStore(apiClient: apiClient)
        appStore.authScreen = .register
        appStore.registerEmail = "guest@dayflow.local"
        appStore.registerDisplayName = "Guest"
        appStore.registerPassword = "secret1234"
        appStore.registerInviteCode = "invite_abc"

        await appStore.register()

        #expect(appStore.sessionPhase == .signedIn)
        #expect(appStore.sessionUser?.email == "owner@dayflow.local")
        #expect(appStore.calendarStore.calendars.count == 2)
        #expect(appStore.budgetStore.board?.month.monthKey == "2026-03")
        #expect(appStore.authErrorMessage == nil)
        #expect(appStore.bootstrapErrorMessage == nil)
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

    @Test
    func loginValidationReplacesBootstrapErrorAndSkipsRequest() async {
        let apiClient = StubAPIClient()
        let appStore = AppStore(apiClient: apiClient)
        appStore.bootstrapErrorMessage = "세션을 복원하지 못했습니다."

        await appStore.login()

        #expect(appStore.authErrorMessage == "이메일과 비밀번호를 입력해 주세요.")
        #expect(appStore.bootstrapErrorMessage == nil)
        #expect(apiClient.loginCalls == 0)
        #expect(appStore.isAuthenticating == false)
    }

    @Test
    func bootstrapBudgetFailureKeepsSignedInSession() async {
        let apiClient = StubAPIClient()
        apiClient.hasActiveSession = true
        apiClient.currentSession = .sample()
        apiClient.fetchBudgetHandler = { _ in
            throw APIClientError.server("예산 보드를 불러오지 못했습니다.")
        }

        let appStore = AppStore(apiClient: apiClient)

        await appStore.bootstrap()

        #expect(appStore.sessionPhase == .signedIn)
        #expect(appStore.sessionUser?.email == "owner@dayflow.local")
        #expect(appStore.calendarStore.calendars.count == 2)
        #expect(appStore.budgetStore.board == nil)
        #expect(appStore.budgetStore.errorMessage == "예산 보드를 불러오지 못했습니다.")
        #expect(appStore.bootstrapErrorMessage == nil)
    }

    @Test
    func authScreenSwitchClearsVisibleErrors() async {
        let apiClient = StubAPIClient()
        let appStore = AppStore(apiClient: apiClient)
        appStore.authErrorMessage = "로그인에 실패했습니다."
        appStore.bootstrapErrorMessage = "세션을 복원하지 못했습니다."

        appStore.showRegister()
        #expect(appStore.authScreen == .register)
        #expect(appStore.authErrorMessage == nil)
        #expect(appStore.bootstrapErrorMessage == nil)

        appStore.authErrorMessage = "초대 코드를 확인해 주세요."
        appStore.showLogin()
        #expect(appStore.authScreen == .login)
        #expect(appStore.authErrorMessage == nil)
    }
}

private final class StubAPIClient: APIClientProtocol, @unchecked Sendable {
    var hasActiveSession = false
    var clearSessionCalled = false
    var loginCalls = 0
    var currentSession: MeResponse?
    var budgetBoard: BudgetBoardResponse?
    var loginHandler: (@Sendable (String, String) async throws -> Void)?
    var registerHandler: (@Sendable (String, String, String, String) async throws -> Void)?
    var fetchCurrentSessionHandler: (@Sendable () async throws -> MeResponse)?
    var fetchBudgetHandler: (@Sendable (String) async throws -> BudgetBoardResponse)?

    func login(email: String, password: String) async throws {
        loginCalls += 1
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
        if let fetchBudgetHandler {
            return try await fetchBudgetHandler(monthKey)
        }
        return budgetBoard ?? .sample(monthKey: monthKey)
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
            summary: BudgetSummary(fixedCostTotal: 153, variableBucketTotal: 12, freeCashAmount: -35),
            fixedItems: [
                BudgetItem(id: "bitm_001", name: "월세 및 관리비", kind: "fixed", amount: 21, enabled: true, note: nil, billingDayLabel: "20일", updatedAt: "2026-03-17T00:00:00Z"),
                BudgetItem(id: "bitm_002", name: "대출이자", kind: "fixed", amount: 36, enabled: true, note: nil, billingDayLabel: "5일", updatedAt: "2026-03-17T00:00:00Z"),
                BudgetItem(id: "bitm_003", name: "핸드폰요금", kind: "fixed", amount: 8, enabled: true, note: nil, billingDayLabel: "15일", updatedAt: "2026-03-17T00:00:00Z"),
                BudgetItem(id: "bitm_004", name: "신용카드", kind: "fixed", amount: 88, enabled: true, note: nil, billingDayLabel: "26일", updatedAt: "2026-03-17T00:00:00Z")
            ],
            variableBuckets: [
                BudgetBucket(id: "bkt_001", name: "점심 및 주말 식대", plannedAmount: 12, actualAmount: 0, formulaHint: "평일 1 + 주말 3", updatedAt: "2026-03-17T00:00:00Z"),
                BudgetBucket(id: "bkt_002", name: "유동 금액", plannedAmount: 0, actualAmount: 0, formulaHint: nil, updatedAt: "2026-03-17T00:00:00Z")
            ],
            billingReminders: [
                BudgetItem(id: "rem_001", name: "인터넷", kind: "reminder", amount: 0, enabled: false, note: nil, billingDayLabel: "25일", updatedAt: "2026-03-17T00:00:00Z"),
                BudgetItem(id: "rem_002", name: "전기 정산", kind: "reminder", amount: 0, enabled: false, note: nil, billingDayLabel: "월말일", updatedAt: "2026-03-17T00:00:00Z")
            ]
        )
    }
}
