# DayFlow iOS

`project.yml` is the XcodeGen source of truth. The tracked `DayFlow.xcodeproj` is directly openable; do not commit `xcuserdata`, DerivedData, or other machine state.

## Regenerate the project

Install XcodeGen `2.45.3`. The system-test lane rejects any other version so the tracked project is generated deterministically.

```bash
xcodegen generate --spec apps/ios/project.yml --project apps/ios
```

Open `apps/ios/DayFlow.xcodeproj` and select the shared **DayFlow** scheme. The scheme includes the app, unit-test, and UI-test targets.

## Simulator E2E

Run the complete local lane from the repository root:

```bash
scripts/run_ios_system_tests.sh
```

It regenerates and validates project drift, takes a global iOS E2E lock, and starts an isolated Docker PostgreSQL/API stack on random host ports. The lane logs in through the real API, reads `/v1/me`, writes a deterministic `Housing` budget item for the returned current month, and verifies the persisted item through GET before testing. It then selects or boots an iOS 17.5+ simulator, clears the app before and after the run, and runs unit tests plus the seeded-owner UI bootstrap test against the discovered API port. The lock prevents concurrent worktrees from uninstalling each other's simulator app; stale lock owners are recovered automatically.

The lane requires GNU `timeout` for TERM-then-KILL process watchdogs. Set `DOCKER_BIN`, `XCODEGEN_BIN`, `XCODEBUILD_BIN`, `XCRUN_BIN`, or `TIMEOUT_BIN` when tools are not on `PATH`; common Homebrew, `/usr/local`, and Docker Desktop paths are detected automatically.

Docker volumes, containers, the locally built per-project API image, DerivedData, result bundles, and logs are removed after a run by default. Failures print only bounded tails from Docker build/runtime, simulator, and xcodebuild logs. Set `KEEP_IOS_SYSTEM_TEST_ARTIFACTS=1` to retain that run's temporary diagnostics. Process watchdog defaults can be adjusted with `IOS_SYSTEM_TEST_DOCKER_TIMEOUT_SECONDS`, `IOS_SYSTEM_TEST_SIMULATOR_BOOT_TIMEOUT_SECONDS`, `IOS_SYSTEM_TEST_UNIT_TIMEOUT_SECONDS`, and `IOS_SYSTEM_TEST_UI_TIMEOUT_SECONDS`.

To retain the Docker stack and its locally built image for a real iPhone smoke test, run:

```bash
KEEP_IOS_SYSTEM_TEST_STACK=1 scripts/run_ios_system_tests.sh
```

After a successful lane, the script prints the discovered host port, Compose project name, a LAN API URL, and the exact cleanup command. If neither `en0` nor `en1` has a detectable IPv4 address, replace the printed `<mac-lan-ip>` placeholder with the Mac's LAN address. In Xcode, edit the app scheme's **Run > Debug > Environment Variables** and set `DAYFLOW_API_BASE_URL` to the printed value, for example `http://192.168.1.20:<printed-port>/v1`.

Run the exact printed command when finished. It has this shape and removes containers, volumes, orphans, and the local API image:

```bash
docker compose -p "<printed-compose-project>" -f "<printed-absolute-compose-file>" down -v --remove-orphans --rmi local
```

This flow prepares the server only and does not imply that an actual device test has run.

The shared system compose file retains `15432` and `18080` defaults for `scripts/run_api_system_tests.sh`. The iOS lane overrides both host ports with Docker-assigned random ports to avoid parallel-run collisions.

The app reads `DAYFLOW_API_BASE_URL`; the Debug configuration permits local HTTP for this lane. Release does not include that transport exception.

## Manual iPhone smoke test

1. In Xcode, select a personal team and a unique bundle identifier under Signing & Capabilities, then choose your connected iPhone.
2. For a retained iOS system-test stack, use the exact `DAYFLOW_API_BASE_URL` printed by the successful `KEEP_IOS_SYSTEM_TEST_STACK=1` run. If you instead start the shared Compose stack manually with its default ports, use `http://<your-mac-LAN-hostname-or-IP>:18080/v1`.
3. Keep the Mac and phone on the same LAN, ensure the API/Docker port is reachable, and accept any local-network prompt if iOS displays one.

Local HTTP is intentionally Debug-only. Use HTTPS before any Release configuration is pointed at a remote API.
