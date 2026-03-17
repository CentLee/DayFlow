# DayFlow Product Spec

## Summary

DayFlow combines a shared calendar with a personal-first monthly budget board.

The budget experience is modeled directly after the provided Excel workbook:

- top-level monthly KPIs are always visible
- fixed costs are edited in place
- variable spending is handled as buckets rather than mandatory transaction rows
- billing reminders are attached to budget items for quick planning

## Mandatory Input Insights

### Harness Patterns Used

The provided harness references influenced the repo and agent structure:

- pipeline for requirement to implementation flow
- fan-out/fan-in for backend, iOS, and integration work
- producer-reviewer for final validation by the review agent

### Excel Insights

Observed structure from the workbook:

- monthly summary: current money, monthly budget, fixed costs, savings, remaining budget
- fixed items: named recurring costs with on/off state and base value
- variable buckets: lunch/weekend meals, flexible money
- calendar-like reminders: settlement days attached to items

These insights shape the MVP:

- budget board is the main expense UI
- single-month editing is optimized for speed
- category and bucket editing matters more than detailed transaction history

## Users

- primary: you and a small number of invited collaborators
- environment: local or self-hosted on a personal iMac server

## Core Flows

1. User signs in.
2. App loads the user profile, calendars, and current month budget.
3. User creates or edits personal events.
4. User shares a calendar with another invited account.
5. User edits monthly budget values in one screen and sees summary changes immediately.

## MVP Features

### Calendar

- personal calendar creation
- calendar list
- month and week views
- event CRUD
- invite user to a specific calendar
- member role: owner, editor, viewer

### Budget

- one personal expense book per user
- month board with KPI summary
- fixed item template editing
- variable buckets
- savings target
- billing reminder metadata
- notes per item

### Authentication

- invited account registration
- password hash authentication
- session token auth for iOS client

## Out of Scope

- bank sync
- full accounting ledger
- event comments
- push notifications
- web frontend
- real-time collaborative editing

## Success Criteria

- a user can manage a monthly budget without leaving the month board
- fixed-cost toggles and amount edits update KPI totals correctly
- invited users can access only shared calendars
- budget data remains private per user

