# DayFlow iOS Architecture

## Target and Legacy Boundary

DayFlow is an iOS-only app for exactly two preconfigured Google identities. It
connects only to the owner's iMac API through its Tailscale MagicDNS name.
Google Sign-In establishes identity only: the app never requests Google
Calendar permission or synchronizes Google Calendar data.

The legacy `LoginView`, `RegisterView`, password session flow, invite-link
screens, calendar-sharing management, and public-base-URL configuration are
migration targets. They are not target UI, compatibility flows, or fallback
behavior.

## App Structure

The root chooses one of three states:

- signed out: Google Sign-In and private-connectivity guidance;
- signed in as owner: Calendar, Budget, and Settings tabs;
- signed in as partner: Calendar and Settings tabs only.

The app is SwiftUI-only, uses Observation for UI state, `async`/`await` for
networking, Keychain for the opaque DayFlow session, and a protected local
store for identity-partitioned cache and outbox data.

## State Model

- `AppStore`: Google exchange/session lifecycle, signed-in identity, route,
  connectivity, bootstrap, sign-out cleanup, and Tailscale MagicDNS endpoint.
- `CalendarStore`: exactly the user's personal calendar plus the household
  calendar, visible range, cached events, pending overlays, and event outbox.
- `BudgetStore`: owner-only current month board, templates, derived KPI preview,
  last confirmed board, pending overlay, and budget outbox.
- `SyncStore`: per-identity cursor, reconciliation state, retry scheduling, and
  conflict records. It has no budget scope for the partner.

State is scoped by immutable DayFlow user identity. A role change, sign-out, or
Google account change clears the prior identity's cache, cursors, and queued
mutations before another identity is rendered.

## Screen Structure

### Authentication and Connectivity

- `GoogleSignInView` starts Google Sign-In and exchanges the ID token with
  `POST /v1/auth/google/exchange`.
- `PrivateConnectionView` explains unavailable iMac/Tailscale connectivity and
  offers retry using the configured MagicDNS endpoint.
- `UnauthorizedIdentityView` explains that the Google identity is not one of
  the two allowlisted people, without exposing allowlist details.

There is no registration, password, invite, email/SMS, Google Calendar, or
public web onboarding screen.

### Calendar

- `CalendarHomeView` shows the caller's personal and household calendars in
  month and week views.
- `EventEditorView` creates, edits, or deletes events with visible pending and
  conflict states.
- `ShareEventSheet` makes an explicit choice to copy or move only a personal
  event to the household calendar. It never converts a calendar or exposes the
  other person's personal calendar.

Both people can edit household events. Calendar creation, member management,
and invite flows do not exist in the target app.

### Budget (owner only)

- `BudgetBoardView` is one scrollable `YYYY-MM` board with the KPI summary at
  the top.
- `BudgetTemplateEditorView` owns fixed-item names, defaults, and ordering.
- `BillingReminderEditor` edits informational reminder label, due-day label,
  and note fields.

The owner can edit fixed-item enabled state, amounts, and notes plus bucket
planned and actual amounts. KPI cards are derived and not directly editable.
The partner receives no Budget tab, routes, DTOs, cache, or pending-write UI.

### Settings

- `SettingsView` shows the signed-in Google account, private endpoint health,
  cache/sync status, and sign out.
- It does not manage allowlisted identities, household roles, calendars,
  membership, passwords, public URL, or Google Calendar connection.

## Networking and Sync

- `APIClient` uses the configured HTTPS Tailscale MagicDNS base URL and the
  opaque DayFlow bearer session. It has no public URL fallback.
- Bootstrap exchanges Google identity, fetches `/me`, fetches `/calendars` and
  visible events, and fetches the budget month only for `budget_access: owner`.
- DTOs decode snake_case into Swift names using explicit `CodingKeys` or a
  single configured decoder.
- While offline, views render last-confirmed cache with pending local overlays;
  supported mutations are put in the identity-scoped outbox.
- Reconnection pulls changes, replays mutations in order with stable
  `client_mutation_id` values, handles conflicts explicitly, and pulls changes
  again. The server's response replaces confirmed state.
- Event and budget `409 conflict` responses preserve the user's pending edit
  and present re-edit, retry-after-rebase, or discard choices. The client never
  silently overwrites a newer server version.
- Pull-to-refresh runs the same authorized reconciliation; it never broadens
  cached scope.

## UX Rules From Excel

- the budget screen is a single scrollable board;
- KPI summary stays at the top;
- fixed items favor toggles and inline numeric editing;
- variable items favor compact bucket cards rather than transactions;
- billing reminders appear as planning context near the bottom; and
- templates own recurring structure such as defaults and ordering.

Reminder edits do not schedule notifications or create DayFlow/Google Calendar
events. Bank sync, transaction ledger, Android, web, macOS, push notifications,
real-time collaboration, and any public or hosted client are out of scope.
