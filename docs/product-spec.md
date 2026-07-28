# DayFlow Product Spec

## Product Baseline

DayFlow is a private, self-hosted productivity app for exactly two people: the
owner and the owner's partner. It runs on two iPhones, while the owner's iMac
hosts the API and PostgreSQL.

The MVP is not a public service:

- iOS is the only client platform.
- Exactly two Google identities are allowlisted.
- Google Sign-In proves identity only. DayFlow does not request Google Calendar
  scopes, read or write Google Calendar data, or retain Google access tokens.
- Tailscale is the only remote transport between either iPhone and the iMac;
  clients use the iMac's MagicDNS name.
- There is no purchased domain, public ingress, password registration,
  email/SMS invitation, or arbitrary onboarding.
- The household calendar is provisioned by the system rather than created or
  joined by users.

## People and Data Boundaries

### Owner

- has one private personal calendar
- is a member of the household shared calendar
- is the only person with an expense book and monthly budget board
- can import the Excel-derived budget model

### Partner

- has one private personal calendar
- is a member of the household shared calendar
- has no budget tab, budget bootstrap metadata, budget API access, or local
  budget cache

The two roles are deployment configuration, not user-manageable permissions.
There is no third identity, guest, invitation, role-management, or team flow.

## Core Flows

1. The person connects the iPhone to the private tailnet and opens DayFlow.
2. The app uses Google Sign-In and sends the Google ID token to the iMac API.
3. The API validates the token and its stable Google subject against the
   two-entry allowlist, then provisions or resumes the matching DayFlow session.
4. The app loads the person's private calendar and the one household calendar.
5. The person creates private events in their personal calendar.
6. A private event becomes visible to the other person only after an explicit
   copy or move to the household calendar.
7. The owner edits the monthly budget board; the partner never receives that
   data.
8. When the iMac is unavailable, the app uses its identity-partitioned local
   cache, records supported edits, and synchronizes after private connectivity
   returns.

## Calendar Scope

- exactly one private personal calendar per allowlisted person
- exactly one pre-provisioned household shared calendar
- month and week views
- event create, read, update, and delete
- both people may edit household events
- no user-created calendars, membership management, invite links, or sharing
  outside the household
- personal calendars never accept members and never change kind
- copy keeps the personal source and creates a household event
- move creates the household event and removes the personal source only after
  the server accepts the target write
- event visibility follows its current calendar

Google Calendar synchronization is outside MVP. "Calendar" in this document
always means a DayFlow calendar unless explicitly stated otherwise.

## Owner-Only Monthly Budget Board

The Excel workbook remains the source of truth for the budget interaction
model:

- the monthly summary is the primary dashboard
- fixed recurring costs are first-class objects
- variable spending stays grouped into buckets
- billing days are lightweight planning reminders
- editing the board is faster and more important than transaction history

Only the owner has one expense book. Calendar membership never grants budget
access, and the partner does not receive empty or redacted budget objects.

### Board Editing

- one `YYYY-MM` snapshot is edited at a time
- KPI cards update immediately but remain derived, display-only values
- fixed items support current-month `enabled`, `amount`, and note edits
- variable buckets support current-month planned and actual amount edits
- reminder label, due-day label, and note are informational metadata
- names, defaults, kinds, and ordering remain template-managed
- month edits do not rewrite templates, prior months, or future months
- reminders do not create calendar events or notifications

### KPI Truth

- `current money` maps to manual `current_cash_amount`
- `monthly budget` maps to manual `base_budget_amount`
- `carry over` maps to manual `carry_over_amount`
- `fixed costs` is the sum of enabled fixed-item amounts
- `savings` maps to `saving_amount`
- `variable bucket total` is the sum of planned bucket amounts
- `remaining budget` is `base_budget_amount - fixed_cost_total -
  saving_amount - variable_bucket_total + carry_over_amount`
- `free cash` is `current_cash_amount - fixed_cost_total - variable bucket
  actual amounts`
- actual bucket amounts affect `free cash`, not `remaining budget`
- reminders and formula hints do not affect KPI calculations

## Connectivity and Availability

- The API and PostgreSQL run on the owner's iMac.
- The API is reachable only at the iMac's Tailscale MagicDNS name; LAN or
  loopback access used for owner-operated diagnostics does not create another
  remote transport.
- No public DNS, reverse proxy, tunnel, or internet-facing port is required.
- The iMac is the synchronization authority and may be asleep, offline, or
  otherwise unreachable.
- Each iPhone retains the last confirmed data for its signed-in identity.
- Supported offline event and owner-budget edits remain visibly pending until
  acknowledged by the server.
- Signing out or changing identities removes that identity's decrypted local
  cache and pending writes from the device.
- Offline operation never broadens authorization: the partner device cannot
  cache or enqueue budget data.

## Target Authentication and Provisioning

- Deployment configuration contains exactly two entries: household role,
  stable Google `sub`, and expected normalized email.
- The stable subject is the authorization key. Email is verified and checked as
  a deployment guard, but email alone never grants access.
- The server validates Google issuer, audience, signature, expiry, and
  `email_verified` before checking the allowlist.
- An accepted exchange creates or reuses the DayFlow user, personal calendar,
  household membership, and opaque revocable session.
- The household calendar is created once by deployment migration and both
  allowlisted users are attached automatically.
- Only the owner receives an expense book and budget routing metadata.
- A non-allowlisted or mismatched identity is denied without provisioning data.

## Legacy-to-Target Migration

Password login, registration, invites, arbitrary shared-calendar creation, and
public/custom-domain ingress describe legacy implementation only. They are not
fallback MVP flows.

The removal must be staged safely:

1. Back up PostgreSQL and validate the two configured Google subjects before
   changing authentication.
2. Map the existing owner and partner rows to those subjects without changing
   their user IDs or personal-calendar ownership.
3. Select or create the single household calendar, attach both users, and
   explicitly archive any extra shared calendars after their events are
   accounted for.
4. Preserve the owner's expense book. Any legacy partner budget is exported or
   quarantined for operator review and is never reassigned or exposed.
5. Ship Google exchange and the new iOS client, then disable registration,
   password login, invite, membership-management, and shared-calendar-creation
   routes.
6. Remove password hashes, invite secrets, obsolete delivery fields, and public
   ingress configuration only after the cutover is verified and rollback data
   is retained for the operator-defined window.

## Out of Scope

- Google Calendar synchronization
- Android, web, macOS, or public SaaS clients
- purchased domains or public ingress
- password recovery or password registration
- email/SMS delivery and invite acceptance
- arbitrary users, teams, roles, calendars, or household administration
- bank sync, transaction ledger, or shared budgeting
- push notifications, event comments, and real-time co-editing
- hosted-only infrastructure or Kubernetes

## Success Criteria

- only the two configured Google subjects can establish sessions
- each person can see only their own personal calendar plus the household
  calendar
- a personal event is shared only by explicit copy or move
- the partner cannot obtain owner budget data online, offline, or through
  calendar membership
- the owner can use the Excel-derived monthly board with correct KPIs
- both iPhones remain useful during iMac downtime and converge after reconnection
- the deployed service has no public onboarding or public network path
