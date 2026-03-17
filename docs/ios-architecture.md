# DayFlow iOS Architecture

## App Structure

Tabs:

- Calendar
- Budget
- Settings

## State Model

- `AppStore`: session, preload state, top-level routing
- `CalendarStore`: calendars, selected range, events
- `BudgetStore`: current month board, optimistic saves, templates

Use SwiftUI Observation for state updates and async/await for network calls.

## Screen Structure

### Auth

- `LoginView`
- `RegisterView`

### Calendar

- `CalendarListView`
- `CalendarMonthView`
- `EventEditorView`
- `ShareCalendarView`

### Budget

- `BudgetBoardView`
- `BudgetTemplateEditorView`
- `BillingReminderView`

### Settings

- `SettingsView`

## UX Rules From Excel

- budget screen is a single scrollable board
- KPI summary stays at the top
- fixed items favor toggles and inline numeric editing
- variable items favor small bucket cards
- billing reminders appear near the bottom as planning context

## Networking

- auth requests use `POST /auth/login` and `POST /auth/register`, both returning `{ user, token }`
- preload `GET /me`, then `GET /calendars` and `GET /budget/months/{current_budget_month_key}`
- treat `GET /me` as the bootstrap payload for session user, grouped calendars, and current month routing
- treat `GET /calendars` as the canonical flat calendar list used by `CalendarStore`
- decode snake_case API payloads into Swift camelCase models with DTOs or explicit `CodingKeys`
- optimistic budget save with rollback on failure
- simple pull-to-refresh for calendar and budget
