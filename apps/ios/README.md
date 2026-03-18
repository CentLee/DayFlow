# DayFlow iOS

SwiftUI app scaffold for DayFlow.

## Current Scope

- source layout for auth, calendar, budget, and settings
- observable stores
- API client protocol
- budget board screen skeleton based on the Excel monthly board

## API Setup

- default API base URL: `http://127.0.0.1:8080/v1`
- override with `DAYFLOW_API_BASE_URL`
- login and register persist a bearer session token locally for bootstrap

## Next Step

Create an Xcode iOS app target and add the files under `DayFlow/`.
