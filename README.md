# AAGA Claims (iOS)

Native iOS app for Accurate Adjustments GA portal customers and referral partners. Spec: [SPEC.md](SPEC.md). Decisions and open questions: [ASSUMPTIONS.md](ASSUMPTIONS.md).

## Layout

| Path | What |
|---|---|
| `Packages/PortalKit` | Models, `PortalAPI` (HTTP + mock), JSON fixtures, view models, formatting. No SDK dependency; tests run with `swift test`. |
| `AAGAClaims/` | The app: SwiftUI screens, Mobile SDK login (`App/SceneDelegate.swift`), SDK-backed transport (`Salesforce/SalesforceTransport.swift`), design tokens (`Resources/Assets.xcassets`). |
| `AAGAClaimsUITests/` | UI tests. |
| `Config/Info.plist` | Login host, URL schemes, data source. |
| `AAGAClaims/Resources/bootconfig.plist` | Mobile SDK OAuth config (consumer key goes here). |

## Build and test

Requires Xcode 26+ with an iOS 18+ simulator.

```sh
# PortalKit unit tests (fast, macOS)
cd Packages/PortalKit && swift test

# App build and UI tests
xcodebuild test -project AAGAClaims.xcodeproj -scheme AAGAClaims \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

If package resolution fails with `cannot use bare repository`, your git config has `safe.bareRepository=explicit`. Prefix the command with
`GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all`.

## Signing in for real

1. Deploy the "AAGA Claims iOS" External Client App (metadata is in the Salesforce repo).
2. Copy its consumer key into `bootconfig.plist`.
3. Run the app: the Mobile SDK shows the portal's login page.

## Milestones (spec §12)

- [x] 1. Foundation: project, SDK login, mock `PortalAPI` with fixtures, tab shell, design tokens
- [x] 2. Claims
- [x] 3. Leads and Submit a Lead
- [x] 4. Support
- [ ] 5. Home and notifications
- [ ] 6. Native features
- [ ] 7. Hardening
