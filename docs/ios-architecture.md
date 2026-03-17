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

- preload `GET /me`, `GET /calendars`, `GET /budget/months/{current}`
- optimistic budget save with rollback on failure
- simple pull-to-refresh for calendar and budget

