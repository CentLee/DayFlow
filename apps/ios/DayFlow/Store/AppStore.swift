import Foundation
import Observation

@Observable
final class AppStore {
    var sessionUser: SessionUser?
    var isLoading = false
    var apiClient: APIClientProtocol
    var calendarStore: CalendarStore
    var budgetStore: BudgetStore

    init(apiClient: APIClientProtocol = MockAPIClient()) {
        self.apiClient = apiClient
        self.calendarStore = CalendarStore(apiClient: apiClient)
        self.budgetStore = BudgetStore(apiClient: apiClient)
    }

    @MainActor
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessionUser = try await apiClient.fetchCurrentUser()
            await calendarStore.load()
            await budgetStore.loadCurrentMonth()
        } catch {
            print("Bootstrap failed: \(error)")
        }
    }
}

@Observable
final class CalendarStore {
    var calendars: [CalendarSummary] = []
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    @MainActor
    func load() async {
        do {
            calendars = try await apiClient.fetchCalendars()
        } catch {
            print("Calendar load failed: \(error)")
        }
    }
}

@Observable
final class BudgetStore {
    var board: BudgetBoardResponse?
    var lastSavedAt: Date?
    var saveState: String = "idle"
    private let apiClient: APIClientProtocol

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    @MainActor
    func loadCurrentMonth() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        do {
            board = try await apiClient.fetchBudget(monthKey: formatter.string(from: .now))
        } catch {
            print("Budget load failed: \(error)")
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
}
