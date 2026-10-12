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
11. **Update bodies** are rendered without WebKit by an allow-list (`HTMLText`): paragraphs, breaks, lists, headings, bold, italic, and links with http(s), mailto or tel URLs. Scripts, styles, iframes and other embedded content are dropped with their contents; `javascript:` and `data:` links are dropped. Web links open in `SFSafariViewController`.
12. **Claim files** are listed, but opening them in Quick Look and uploading wait for the [new] file endpoints and milestone 6 (spec §6.10).
13. **"View case"** after Request Assistance opens the Support tab straight into the new case.
14. **Status filter** on the claims list offers the 7 lifecycle stages. Claims with any other status appear only when the filter is "All statuses".
15. **Loss reason** (`lossReason`) only comes from `GET /claims`, so claim detail shows it from the list row it was opened from. Opened any other way (deep link, milestone 6), it's hidden.
16. **Claim detail** leaves the navigation bar title empty because the header already shows the claim name.

17. **Lead agreement filter:** "Sent" means sent and not yet signed; "Signed" means completed; "Not sent" means neither date is set.
18. **Lead Status filter** offers New, Working, Qualified, Converted and Unqualified.
19. **Submit a Lead validation** beyond the spec: email must look like an email, ZIP must be exactly 5 digits, and the photos link must be a full http(s) address. Peril, address and insurance fields are optional, as on the portal. "Has a claim been filed?" can be left unanswered ("Not sure").
20. **Insurance typeahead** matches anywhere in the name (like the server's `LIKE '%term%'`), so "st" finds both Allstate and State Farm. Editing the text after picking a company clears the selection.
21. **Supporting-files step** after Submit a Lead shows the confirmation and a Done button. Uploading from it arrives with milestone 6 (spec §6.10); until then it explains that and points to Add Comment for sharing a photo link.
22. **Lead detail** also shows the referral (associated party) details in a "Referred by" card, so every `LeadDetail` field appears somewhere.
23. **Submit a Lead** is the + button in the Leads toolbar, next to the notifications bell.
24. **Keyboard Done button** on the Submit a Lead form, because number and phone pads have no return key.

25. **Support list** follows the portal: it opens on the Open filter, treats "Closed" and "Resolved" as closed, shows a count on each filter, and search also covers the case number and account manager.
26. **Replies on closed cases** are allowed, as on the portal.
27. **Request Assistance (Support tab)** lists claims first, then leads, each sorted by name, in a pop-up menu. Both fields are required. After submitting, the app opens the new case.
28. **Case thread** is oldest first; staff messages are left-aligned with the author's name and yours are right-aligned as "You".

29. **Home tiles:** Open Claims shows claims that aren't Closed; Open Leads shows leads that aren't Converted or Unqualified; Completed shows Closed claims (the spec counts Converted leads too, but one list can't show both; they're under Lead Status on the Leads tab); Unread Updates opens the Notifications sheet.
30. **Status overview** appears only when the user has claims, and lists all 7 stages including those with no claims.
31. **Quick actions** sit above the status overview so they're visible without scrolling.
32. **Opening an update** (from Home or Notifications) marks it read straight away, and "Open Claim / Open Lead" closes the sheets and opens the record in its tab.
33. **App icon badge** is set to the unread count whenever it changes, but iOS only shows it after the user allows notifications, which is asked for with push in milestone 6.

## Open questions

1. **API access for Customer Community Login users** (spec §3 blocking prerequisite). The portal profile currently has API Enabled = false. Until this is resolved, live mode can't work.
2. **Privacy policy and terms URLs** for the Account screen (spec §6.11).
3. **App icon and vector logo** from the designer.
4. **Consumer key** from the "AAGA Claims iOS" External Client App, once it's deployed.
