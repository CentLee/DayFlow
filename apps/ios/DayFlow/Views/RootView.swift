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
                    if let board = appStore.budgetStore.board {
                        if let errorMessage = appStore.budgetStore.errorMessage {
                            ErrorBanner(message: errorMessage)
                        }
                        if appStore.budgetStore.isLoading {
                            ProgressView("예산 보드를 새로 불러오는 중입니다")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        BudgetStatusBar(
                            monthKey: board.month.monthKey,
                            saveState: appStore.budgetStore.saveState,
                            lastSavedAt: appStore.budgetStore.lastSavedAt,
                            isSaving: appStore.budgetStore.isSaving,
                            canSave: appStore.budgetStore.canPersistChanges,
                            actionTitle: appStore.budgetStore.persistActionTitle
                        ) {
                            Task {
                                await appStore.budgetStore.save()
                            }
                        }
                        KPICards(board: board)
                        FixedItemsSection(items: board.fixedItems)
                        VariableBucketsSection(buckets: board.variableBuckets)
                        BillingRemindersSection(reminders: board.billingReminders)
                    } else if appStore.budgetStore.isLoading {
                        ProgressView("예산 보드를 불러오는 중입니다")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let errorMessage = appStore.budgetStore.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            ErrorBanner(message: errorMessage)
                            retryButton
                        }
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
                    .disabled(appStore.budgetStore.isLoading || appStore.budgetStore.isSaving || appStore.budgetStore.monthKey == nil)
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
    let isSaving: Bool
    let canSave: Bool
    let actionTitle: String
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("\(monthKey) 월간 보드")
                        .font(.headline)
                } icon: {
                    Image(systemName: statusIconName)
                        .foregroundStyle(statusColor)
                }
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            Button(actionTitle) {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave || isSaving)
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
        case "saving":
            return "변경 사항을 저장하는 중입니다."
        case "error":
            return "저장에 실패해 마지막 저장본으로 복원했습니다. 다시 시도할 수 있습니다."
        default:
            return "실시간 예산 데이터를 준비 중입니다."
        }
    }

    private var statusIconName: String {
        switch saveState {
        case "synced":
            return "checkmark.circle.fill"
        case "dirty":
            return "pencil.circle.fill"
        case "saving":
            return "arrow.triangle.2.circlepath.circle.fill"
        case "error":
            return "exclamationmark.triangle.fill"
        default:
            return "clock.fill"
        }
    }

    private var statusColor: Color {
        switch saveState {
        case "synced":
            return .secondary
        case "dirty":
            return .orange
        case "saving":
            return .blue
        case "error":
            return .red
        default:
            return .secondary
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
                FixedItemRow(item: item)
            }
        }
    }
}

private struct FixedItemRow: View {
    @Environment(AppStore.self) private var appStore
    @FocusState private var isAmountFieldFocused: Bool

    let item: BudgetItem
    @State private var amountText: String

    init(item: BudgetItem) {
        self.item = item
        _amountText = State(initialValue: "\(item.amount)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: enabledBinding)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                if let billing = item.billingDayLabel {
                    Text(billing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            TextField("금액", text: $amountText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 88)
                .textFieldStyle(.roundedBorder)
                .focused($isAmountFieldFocused)
                .onChange(of: amountText) { _, newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits != newValue {
                        amountText = digits
                        return
                    }

                    let amount = Int(digits) ?? 0
                    appStore.budgetStore.updateFixedItemAmount(item.id, amount: amount)
                }
                .onChange(of: item.amount) { _, newValue in
                    let nextValue = "\(newValue)"
                    if !isAmountFieldFocused {
                        amountText = nextValue
                    } else if !amountText.isEmpty, amountText != nextValue {
                        amountText = nextValue
                    }
                }
                .onChange(of: isAmountFieldFocused) { _, isFocused in
                    if !isFocused {
                        amountText = "\(item.amount)"
                    }
                }
        }
        .padding(.vertical, 4)
        .opacity(item.enabled ? 1 : 0.7)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { item.enabled },
            set: { isEnabled in
                appStore.budgetStore.setFixedItemEnabled(item.id, isEnabled: isEnabled)
            }
        )
    }
}

private struct VariableBucketsSection: View {
    let buckets: [BudgetBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("변동 버킷")
                .font(.headline)
            ForEach(buckets) { bucket in
                VariableBucketRow(bucket: bucket)
            }
        }
    }
}

private struct VariableBucketRow: View {
    @Environment(AppStore.self) private var appStore
    @State private var plannedAmountText = ""
    @State private var actualAmountText = ""
    @FocusState private var focusedField: Field?

    let bucket: BudgetBucket

    private enum Field {
        case planned
        case actual
    }

    init(bucket: BudgetBucket) {
        self.bucket = bucket
        _plannedAmountText = State(initialValue: "\(bucket.plannedAmount)")
        _actualAmountText = State(initialValue: "\(bucket.actualAmount)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(bucket.name)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                amountField(title: "예산", text: $plannedAmountText, field: .planned)
                amountField(title: "사용", text: $actualAmountText, field: .actual)
            }

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
        .onChange(of: bucket.plannedAmount) { _, newValue in
            let nextValue = "\(newValue)"
            if focusedField != .planned {
                plannedAmountText = nextValue
            } else if !plannedAmountText.isEmpty, plannedAmountText != nextValue {
                plannedAmountText = nextValue
            }
        }
        .onChange(of: bucket.actualAmount) { _, newValue in
            let nextValue = "\(newValue)"
            if focusedField != .actual {
                actualAmountText = nextValue
            } else if !actualAmountText.isEmpty, actualAmountText != nextValue {
                actualAmountText = nextValue
            }
        }
        .onChange(of: focusedField) { _, newValue in
            guard newValue == nil else { return }
            plannedAmountText = "\(bucket.plannedAmount)"
            actualAmountText = "\(bucket.actualAmount)"
        }
    }

    private func amountField(title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(title, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: field)
                .onChange(of: text.wrappedValue) { _, newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits != newValue {
                        text.wrappedValue = digits
                        return
                    }

                    let amount = Int(digits) ?? 0
                    switch field {
                    case .planned:
                        appStore.budgetStore.updateVariableBucketPlannedAmount(bucket.id, amount: amount)
                    case .actual:
                        appStore.budgetStore.updateVariableBucketActualAmount(bucket.id, amount: amount)
                    }
                }
        }
        .frame(maxWidth: .infinity)
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
