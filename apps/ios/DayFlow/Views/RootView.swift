import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        content
            .task {
                await appStore.bootstrap()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch appStore.sessionPhase {
        case .launching:
            LaunchingView()
        case .signedOut:
            AuthView()
        case .signedIn:
            if appStore.sessionUser != nil {
                MainTabView()
            } else {
                LaunchingView()
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

private struct LaunchingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("세션을 불러오는 중입니다")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AuthView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DayFlow")
                            .font(.largeTitle.bold())
                        Text("공유 캘린더와 개인 월간 예산 보드를 함께 관리합니다.")
                            .foregroundStyle(.secondary)
                    }

                    if let message = appStore.bootstrapErrorMessage ?? appStore.authErrorMessage {
                        ErrorBanner(message: message)
                    }

                    Picker(
                        "인증 화면",
                        selection: Binding(
                            get: { appStore.authScreen },
                            set: { appStore.setAuthScreen($0) }
                        )
                    ) {
                        ForEach(AuthScreen.allCases) { screen in
                            Text(screen.title).tag(screen)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch appStore.authScreen {
                    case .login:
                        LoginFormView()
                    case .register:
                        RegisterFormView()
                    }
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LoginFormView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore

        VStack(alignment: .leading, spacing: 16) {
            Text("기존 계정으로 바로 시작")
                .font(.headline)

            TextField("이메일", text: $appStore.loginEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("비밀번호", text: $appStore.loginPassword)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await appStore.login()
                }
            } label: {
                HStack {
                    if appStore.isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("로그인")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appStore.isAuthenticating)

            Button("초대받은 계정이신가요? 가입으로 이동") {
                appStore.showRegister()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct RegisterFormView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        @Bindable var appStore = appStore

        VStack(alignment: .leading, spacing: 16) {
            Text("초대 코드로 계정을 만듭니다")
                .font(.headline)

            TextField("이메일", text: $appStore.registerEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("이름", text: $appStore.registerDisplayName)
                .textFieldStyle(.roundedBorder)

            SecureField("비밀번호", text: $appStore.registerPassword)
                .textFieldStyle(.roundedBorder)

            TextField("초대 코드", text: $appStore.registerInviteCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Text("공유 캘린더 초대와 연결된 이메일, 초대 코드가 필요합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await appStore.register()
                }
            } label: {
                HStack {
                    if appStore.isAuthenticating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("회원가입")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appStore.isAuthenticating)

            Button("이미 계정이 있나요? 로그인으로 이동") {
                appStore.showLogin()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CalendarListView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage = appStore.calendarStore.errorMessage {
                    ContentUnavailableView("캘린더를 불러오지 못했습니다", systemImage: "calendar.badge.exclamationmark", description: Text(errorMessage))
                } else if appStore.calendarStore.calendars.isEmpty {
                    ContentUnavailableView("표시할 캘린더가 없습니다", systemImage: "calendar")
                } else {
                    List(appStore.calendarStore.calendars) { calendar in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(calendar.name)
                            Text(calendar.updatedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    if appStore.budgetStore.isLoading {
                        ProgressView("예산 보드를 불러오는 중입니다")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let errorMessage = appStore.budgetStore.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            ErrorBanner(message: errorMessage)
                            retryButton
                        }
                    } else if let board = appStore.budgetStore.board {
                        BudgetStatusBar(
                            monthKey: board.month.monthKey,
                            saveState: appStore.budgetStore.saveState,
                            lastSavedAt: appStore.budgetStore.lastSavedAt
                        )
                        KPICards(board: board)
                        FixedItemsSection(items: board.fixedItems)
                        VariableBucketsSection(buckets: board.variableBuckets)
                        BillingRemindersSection(reminders: board.billingReminders)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ContentUnavailableView("예산 보드가 없습니다", systemImage: "chart.bar.doc.horizontal")
                            retryButton
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Budget")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await appStore.budgetStore.reload()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(appStore.budgetStore.isLoading || appStore.budgetStore.monthKey == nil)
                }
            }
        }
    }

    private var retryButton: some View {
        Button {
            Task {
                await appStore.budgetStore.reload()
            }
        } label: {
            Label("다시 불러오기", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(appStore.budgetStore.isLoading || appStore.budgetStore.monthKey == nil)
    }
}

private struct BudgetStatusBar: View {
    let monthKey: String
    let saveState: String
    let lastSavedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(monthKey) live board")
                .font(.headline)
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusMessage: String {
        switch saveState {
        case "synced":
            if let lastSavedAt {
                return "서버와 동기화됨 · \(lastSavedAt.formatted(date: .omitted, time: .shortened))"
            }
            return "서버와 동기화됨"
        case "dirty":
            return "변경 사항이 아직 저장되지 않았습니다."
        case "error":
            return "API 오류로 최신 상태를 불러오지 못했습니다."
        default:
            return "실시간 예산 데이터를 준비 중입니다."
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

                Section {
                    Button("로그아웃", role: .destructive) {
                        appStore.logout()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
