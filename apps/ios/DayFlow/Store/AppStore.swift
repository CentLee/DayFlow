import Foundation
import Observation

@Observable
final class AppStore {
    var sessionPhase: SessionPhase = .launching
    var sessionUser: SessionUser?
    var authScreen: AuthScreen = .login
    var isLoading = false
    var isAuthenticating = false
    var authErrorMessage: String?
    var bootstrapErrorMessage: String?
    var loginEmail = ""
    var loginPassword = ""
    var registerEmail = ""
    var registerDisplayName = ""
    var registerPassword = ""
    var registerInviteCode = ""
    var apiClient: APIClientProtocol
    var calendarStore: CalendarStore
    var budgetStore: BudgetStore

    init(apiClient: APIClientProtocol = APIClient.live()) {
        self.apiClient = apiClient
        self.calendarStore = CalendarStore()
        self.budgetStore = BudgetStore(apiClient: apiClient)
    }

    @MainActor
    func bootstrap() async {
        guard sessionPhase == .launching else { return }
        guard apiClient.hasActiveSession else {
            sessionPhase = .signedOut
            return
        }

        isLoading = true
        bootstrapErrorMessage = nil
        defer { isLoading = false }

        do {
            try await hydrateSession()
            sessionPhase = .signedIn
        } catch {
            handleSessionFailure(error, fallbackMessage: "세션을 복원하지 못했습니다. 다시 로그인해 주세요.")
        }
    }

    @MainActor
    func login() async {
        bootstrapErrorMessage = nil
        authErrorMessage = validateLogin()
        guard authErrorMessage == nil else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await apiClient.login(email: loginEmail.trimmingCharacters(in: .whitespacesAndNewlines), password: loginPassword)
            try await hydrateSession()
            authErrorMessage = nil
            bootstrapErrorMessage = nil
            sessionPhase = .signedIn
        } catch {
            apiClient.clearSession()
            sessionUser = nil
            calendarStore.reset()
            budgetStore.reset()
            authErrorMessage = message(for: error)
            sessionPhase = .signedOut
        }
    }

    @MainActor
    func register() async {
        bootstrapErrorMessage = nil
        authErrorMessage = validateRegister()
        guard authErrorMessage == nil else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await apiClient.register(
                email: registerEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: registerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                password: registerPassword,
                inviteCode: registerInviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await hydrateSession()
            authErrorMessage = nil
            bootstrapErrorMessage = nil
            sessionPhase = .signedIn
        } catch {
            apiClient.clearSession()
            sessionUser = nil
            calendarStore.reset()
            budgetStore.reset()
            authErrorMessage = message(for: error)
            sessionPhase = .signedOut
        }
    }

    @MainActor
    func logout() {
        apiClient.clearSession()
        sessionUser = nil
        sessionPhase = .signedOut
        authScreen = .login
        loginPassword = ""
        authErrorMessage = nil
        bootstrapErrorMessage = nil
        calendarStore.reset()
        budgetStore.reset()
    }

    @MainActor
    func showLogin() {
        setAuthScreen(.login)
    }

    @MainActor
    func showRegister() {
        setAuthScreen(.register)
    }

    @MainActor
    func setAuthScreen(_ screen: AuthScreen) {
        authScreen = screen
        authErrorMessage = nil
        bootstrapErrorMessage = nil
    }

    @MainActor
    private func hydrateSession() async throws {
        let me = try await apiClient.fetchCurrentSession()
        sessionUser = me.user
        calendarStore.setCalendars(me.ownedCalendars + me.sharedCalendars)
        clearAuthForms()
        do {
            try await budgetStore.load(monthKey: me.currentBudgetMonthKey)
        } catch {
            budgetStore.errorMessage = message(for: error)
        }
    }

    @MainActor
    private func handleSessionFailure(_ error: Error, fallbackMessage: String) {
        apiClient.clearSession()
        sessionUser = nil
        sessionPhase = .signedOut
        calendarStore.reset()
        budgetStore.reset()
        bootstrapErrorMessage = message(for: error, fallback: fallbackMessage)
    }

    private func validateLogin() -> String? {
        if loginEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loginPassword.isEmpty {
            return "이메일과 비밀번호를 입력해 주세요."
        }
        return nil
    }

    private func validateRegister() -> String? {
        if registerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            registerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            registerPassword.isEmpty ||
            registerInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "이메일, 이름, 비밀번호, 초대 코드를 모두 입력해 주세요."
        }
        return nil
    }

    private func clearAuthForms() {
        loginPassword = ""
        registerPassword = ""
        registerInviteCode = ""
    }

    private func message(for error: Error, fallback: String = "요청을 완료하지 못했습니다.") -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription.isEmpty ? fallback : error.localizedDescription
    }
}

@Observable
final class CalendarStore {
    var calendars: [CalendarSummary] = []
    var errorMessage: String?

    func setCalendars(_ calendars: [CalendarSummary]) {
        self.calendars = calendars.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        errorMessage = nil
    }

    func reset() {
        calendars = []
        errorMessage = nil
    }
}

@Observable
final class BudgetStore {
    var board: BudgetBoardResponse?
    var isLoading = false
    var errorMessage: String?
    var lastSavedAt: Date?
    var saveState: String = "idle"
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    @MainActor
    func load(monthKey: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            board = try await apiClient.fetchBudget(monthKey: monthKey)
        } catch {
            board = nil
            throw error
        }
    }

    @MainActor
    func toggleFixedItem(_ itemID: String) {
        guard var board else { return }
        guard let index = board.fixedItems.firstIndex(where: { $0.id == itemID }) else { return }
        board.fixedItems[index].enabled.toggle()
        self.board = board
        saveState = "dirty"
    }

    func reset() {
        board = nil
        isLoading = false
        errorMessage = nil
        lastSavedAt = nil
        saveState = "idle"
    }
}
