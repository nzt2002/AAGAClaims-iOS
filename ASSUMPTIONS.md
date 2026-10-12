# Assumptions and open questions

Decisions made where the spec ([SPEC.md](SPEC.md)) is silent or conflicts with reality.

## Assumptions

1. **iOS 18 minimum, not iOS 17.** Salesforce Mobile SDK 14.0.0 (the latest) requires iOS 18. The spec asks for both "latest SDK" and "iOS 17+"; we chose the current SDK.
2. **UIKit scene delegate hosting SwiftUI.** The Mobile SDK's login flow presents over a UIKit scene, so the app follows Salesforce's native Swift template (`AppDelegate` + `SceneDelegate` + `UIHostingController`). All screens are SwiftUI.
3. **Demo mode.** While `bootconfig.plist` has the placeholder consumer key, the app skips login and signs in a fixed demo user ("Alex Smith"). A banner says so on every tab. UI tests force demo mode with `-UITestDemo YES`.
4. **Mock data by default.** `PortalDataSource` in `Config/Info.plist` is `mock` (spec §3: build against the mock until the REST prerequisite is confirmed). Set it to `live`, or launch with `-PortalDataSource live`, to call `/services/apexrest/portal/v1`.
5. **OAuth callback** is `aagaclaims-auth://oauth/done`, a separate scheme from the `aagaclaims://` deep links, so the login redirect never reaches the deep-link handler. It matches the External Client App metadata in the Salesforce repo.
6. **Login host** is set with `SFDCOAuthLoginHost = portal.accurateadjustmentsga.com` in Info.plist.
7. **Logo** on the splash screen is an SF Symbol placeholder until the designer supplies the vector logo (spec §9). The SDK's own login page shows the portal's branded login.
8. **"Open Leads"** on Home counts leads that are not `Converted` or `Unqualified`.
9. **Dates without a time** (`lossDate`, `dateOfNotice` etc.) are decoded as `CalendarDate`, not `Date`, so they never shift a day across time zones.
10. **Dark-mode colours** are our own equivalents of the portal palette (Assets.xcassets); the designer may refine them.
11. **Update bodies** show as plain-text previews for now (tags and scripts stripped). Full rich rendering comes with the Update sheet in milestone 5.

## Open questions

1. **API access for Customer Community Login users** (spec §3 blocking prerequisite). The portal profile currently has API Enabled = false. Until this is resolved, live mode can't work.
2. **Privacy policy and terms URLs** for the Account screen (spec §6.11).
3. **App icon and vector logo** from the designer.
4. **Consumer key** from the "AAGA Claims iOS" External Client App, once it's deployed.
