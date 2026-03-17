import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        Group {
            if appStore.sessionUser == nil {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .task {
            if appStore.sessionUser == nil {
                await appStore.bootstrap()
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            CalendarListView()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            BudgetBoardView()
                .tabItem { Label("Budget", systemImage: "chart.bar.doc.horizontal") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct LoginView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("DayFlow")
                    .font(.largeTitle.bold())
                Text("공유 캘린더와 개인 월간 예산 보드를 함께 관리합니다.")
                    .foregroundStyle(.secondary)
                Button("데모 세션으로 시작") {}
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }
}

struct CalendarListView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        NavigationStack {
            List(appStore.calendarStore.calendars) { calendar in
                VStack(alignment: .leading, spacing: 4) {
                    Text(calendar.name)
                    Text(calendar.updatedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Calendars")
        }
    }
}

struct BudgetBoardView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let board = appStore.budgetStore.board {
                        KPICards(board: board)
                        FixedItemsSection(items: board.fixedItems)
                        VariableBucketsSection(buckets: board.variableBuckets)
                        BillingRemindersSection(reminders: board.billingReminders)
                    } else {
                        ProgressView()
                    }
                }
                .padding(20)
            }
            .navigationTitle("Budget")
        }
    }
}

private struct KPICards: View {
    let board: BudgetBoardResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(board.month.monthKey)
                .font(.title2.bold())
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                card("현재자금", value: board.month.currentCashAmount)
                card("월 예산", value: board.month.baseBudgetAmount)
                card("고정지출", value: board.summary.fixedCostTotal)
                card("저축", value: board.month.savingAmount)
                card("잔여예산", value: board.month.remainingBudgetAmount)
                card("여유자금", value: board.summary.freeCashAmount)
            }
        }
    }

    private func card(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct FixedItemsSection: View {
    let items: [BudgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("고정비")
                .font(.headline)
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                        if let billing = item.billingDayLabel {
                            Text(billing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: .constant(item.enabled))
                        .labelsHidden()
                    Text("\(item.amount)")
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct VariableBucketsSection: View {
    let buckets: [BudgetBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("변동 버킷")
                .font(.headline)
            ForEach(buckets) { bucket in
                VStack(alignment: .leading, spacing: 6) {
                    Text(bucket.name)
                    Text("예산 \(bucket.plannedAmount) / 사용 \(bucket.actualAmount)")
                        .font(.subheadline)
                    if let hint = bucket.formulaHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private struct BillingRemindersSection: View {
    let reminders: [BudgetItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("정산 일정")
                .font(.headline)
            ForEach(reminders) { reminder in
                HStack {
                    Text(reminder.name)
                    Spacer()
                    Text(reminder.billingDayLabel ?? "")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        NavigationStack {
            Form {
                if let user = appStore.sessionUser {
                    Section("Account") {
                        Text(user.displayName)
                        Text(user.email)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
