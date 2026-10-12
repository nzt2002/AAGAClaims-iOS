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
12. **Files** open in Quick Look from a temporary copy that's deleted when Quick Look closes; nothing is cached (spec §8).
13. **"View case"** after Request Assistance opens the Support tab straight into the new case.
14. **Status filter** on the claims list offers the 7 lifecycle stages. Claims with any other status appear only when the filter is "All statuses".
15. **Loss reason** (`lossReason`) only comes from `GET /claims`, so claim detail shows it from the list row it was opened from. Opened any other way (deep link, milestone 6), it's hidden.
16. **Claim detail** leaves the navigation bar title empty because the header already shows the claim name.

17. **Lead agreement filter:** "Sent" means sent and not yet signed; "Signed" means completed; "Not sent" means neither date is set.
18. **Lead Status filter** offers New, Working, Qualified, Converted and Unqualified.
19. **Submit a Lead validation** beyond the spec: email must look like an email, ZIP must be exactly 5 digits, and the photos link must be a full http(s) address. Peril, address and insurance fields are optional, as on the portal. "Has a claim been filed?" can be left unanswered ("Not sure").
20. **Insurance typeahead** matches anywhere in the name (like the server's `LIKE '%term%'`), so "st" finds both Allstate and State Farm. Editing the text after picking a company clears the selection.
21. **Supporting-files step** after Submit a Lead has the same Upload menu as a lead's Files section.
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

34. **Record types from ids:** portal universal links (`/s/detail/{id}`) and update pushes only carry an id, so the app tells claims from leads by key prefix: Claims2__c `a23`, Prospects__c `a0r` (from the org). Fixtures use the same prefixes.
35. **Deep links are strict:** only `aagaclaims://claim|lead|case/{id}` with a 15- or 18-character id, and portal links on `https://portal.accurateadjustmentsga.com`. Anything else is ignored. Links that arrive before sign-in open after it.
36. **Update pushes** open the claim or lead and mark the update read, rather than opening the Update sheet on top.
37. **Notifications toggle** asks for permission the first time; after that iOS only allows changes in Settings, so the toggle opens Settings.
38. **App lock** uses `.deviceOwnerAuthentication`, so it falls back to the device passcode. It's turned on only after a successful check, is offered once after the first sign-in, is cleared on sign-out, and turns itself off if the device passcode is removed (otherwise the user would be locked out).
39. **Offline cache** is response JSON in files under Caches with complete file protection, not SmartStore or SwiftData: it's read-only and keyed by endpoint, so a database adds nothing. It's cleared on sign-out. 404s and server errors are never replaced by cached data. The banner shows the age of the oldest cached data on screen.
40. **Offline writes:** Add Comment, Request Assistance, replies, Submit a Lead, Mark all read, uploads and opening files are disabled or refused with "Available when you're back online."
41. **Upload progress** shows each file's state (Waiting, Uploading, Uploaded, or Failed with Retry) rather than a percentage: the Mobile SDK's REST client doesn't report upload progress.
42. **Upload size:** files over 25 MB are refused on the device. See open question 5.
43. **Photo library picks** have no file name without full photo-library access, so they're titled like camera photos ("Photo {yyyy-MM-dd HH:mm}", numbered when several are picked).
44. **Camera photos** are saved as HEIC where the device supports it, otherwise JPEG, and downscaled like library photos.
45. **Photo metadata** (including location) is kept on photos that don't need downscaling, and dropped from downscaled ones.

46. **Colour refinements for contrast:** brand blue `#1A73E8` is `#1967D2` for text, links and filled buttons (it was 4.4:1 on the tinted backgrounds; now 5.4:1 or better), and warning `#B06000` is `#9A5300` in light mode (was 4.1:1 on tinted backgrounds; now 4.9:1 or better). Every text colour passes 4.5:1 on every background it's used on, in light and dark mode. The spec says the designer may refine the palette; these are the minimum changes for WCAG AA.
47. **Large text:** two-column rows (card headers and footers, the team card, the action bar) stack vertically from the xxLarge text size up; Home shows one tile per row and stacked quick actions at accessibility sizes; titles wrap rather than truncate. The demo and offline banners are capped at xxxLarge so they never crowd out the screen.
48. **Accessibility audit:** `AccessibilityAuditUITests` runs Xcode's audit on every main screen and fails on any new issue. Its allowlist covers only reviewed false positives: iOS's own search field placeholder, contrast reports with no element attached, the capped banners, iOS's grouped-form header and footer grey, and five labels checked in screenshots at accessibility sizes.
49. **Foreground refresh:** returning to the app reloads any list, dashboard or open detail whose data is more than 5 minutes old, or whose last load failed (spec §7).
50. **Expired session (401):** any 401 signs the user out through the Mobile SDK, which shows the login screen again (spec §5). In demo mode there's no session to expire.
51. **Privacy manifest** (`PrivacyInfo.xcprivacy`) declares the spec §10 data (name, email, phone, photos, other user content, user ID; app functionality only, no tracking) and the required-reason APIs the app uses (UserDefaults CA92.1, file timestamps C617.1).

## Open questions

1. **API access for Customer Community Login users** (spec §3 blocking prerequisite). The portal profile currently has API Enabled = false. Until this is resolved, live mode can't work.
2. **Privacy policy and terms URLs** for the Account screen (spec §6.11).
3. **App icon and vector logo** from the designer.
4. **Consumer key** from the "AAGA Claims iOS" External Client App, once it's deployed.
5. **Upload size limit.** Apex REST request bodies are limited by heap size (about 6 MB synchronous), which a 4,000 px photo can exceed. The Salesforce team should confirm the limit for `POST /claims|leads/{id}/files`, or have it accept larger files another way. The app currently refuses files over 25 MB.
6. **Push setup:** an Apple Developer team, an APNs key added to the External Client App's push settings, and the server-side trigger (spec §8).
7. **Universal links:** the portal must serve `/.well-known/apple-app-site-association` for the app's team and bundle id, and the app needs the Associated Domains entitlement (`applinks:portal.accurateadjustmentsga.com`). Both need the Apple team id.
8. **Should location metadata be stripped from all photos before upload?** It's currently only dropped when a photo is downscaled.
9. **Brand colours:** the designer should confirm the contrast-driven refinements in assumption 46, and supply dark-mode values (ours are placeholders).
