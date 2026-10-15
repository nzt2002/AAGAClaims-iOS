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

29. ~~**Home tiles**~~ Replaced on 2026-10-12 by Upcoming and Recent claims (see 56).
30. **Status overview** appears only when the user has claims, and lists all 7 stages including those with no claims.
31. **Quick actions** sit directly under the welcome message: Submit a Lead, Ask Question, My Claims, and New Task for staff and portal adjusters.
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
42. **Upload size:** files over 4 MB are refused on the device, matching the server (Apex REST bodies count against the 6 MB heap). Files over 4 MB can't be previewed in the app either.
43. **Photo library picks** have no file name without full photo-library access, so they're titled like camera photos ("Photo {yyyy-MM-dd HH:mm}", numbered when several are picked).
44. **Camera photos** are saved as HEIC where the device supports it, otherwise JPEG, and downscaled like library photos.
45. **Photo metadata** (including location) is kept on photos that don't need downscaling, and dropped from downscaled ones.

46. *(Superseded by 66.)* **Colour refinements for contrast:** brand blue `#1A73E8` is `#1967D2` for text, links and filled buttons (it was 4.4:1 on the tinted backgrounds; now 5.4:1 or better), and warning `#B06000` is `#9A5300` in light mode (was 4.1:1 on tinted backgrounds; now 4.9:1 or better). Every text colour passes 4.5:1 on every background it's used on, in light and dark mode. The spec says the designer may refine the palette; these are the minimum changes for WCAG AA.
47. **Large text:** two-column rows (card headers and footers, the team card, the action bar) stack vertically from the xxLarge text size up; Home shows one tile per row and stacked quick actions at accessibility sizes; titles wrap rather than truncate. The demo and offline banners are capped at xxxLarge so they never crowd out the screen.
48. **Accessibility audit:** `AccessibilityAuditUITests` runs Xcode's audit on every main screen and fails on any new issue. Its allowlist covers only reviewed false positives: iOS's own search field placeholder, contrast reports with no element attached, the capped banners, iOS's grouped-form header and footer grey, and five labels checked in screenshots at accessibility sizes.
49. **Foreground refresh:** returning to the app reloads any list, dashboard or open detail whose data is more than 5 minutes old, or whose last load failed (spec §7).
50. **Expired session (401):** any 401 signs the user out through the Mobile SDK, which shows the login screen again (spec §5). In demo mode there's no session to expire.
51. **Privacy manifest** (`PrivacyInfo.xcprivacy`) declares the spec §10 data (name, email, phone, photos, other user content, user ID; app functionality only, no tracking) and the required-reason APIs the app uses (UserDefaults CA92.1, file timestamps C617.1).

52. **Live data by default:** `PortalDataSource` is `live`. UI tests force demo mode and mock data with launch arguments.
53. **Keychain entitlement:** `Config/AAGAClaims.entitlements` declares the app's keychain access group. Without it the Mobile SDK can't store tokens (errSecMissingEntitlement, -34018) and sign-in fails with "required parameters for the identity service were missing: access token". This happens on the simulator too, so build signed ("Sign to Run Locally" is enough), not with `CODE_SIGNING_ALLOWED=NO`.
54. **Internal users** (staff) can use the app with the "Portal Mobile App (Staff)" permission set. They sign in through the portal login page. Their lists show the claims and leads they own or manage, and record access isn't restricted, the same as on internal record pages.
55. **"Failed: DPoP Validation Error"** appears in Login History next to every successful app sign-in. The Mobile SDK tries DPoP token binding first and falls back; sign-in succeeds.

56. **Home redesign (2026-10-12, at the business's request):** the KPI tiles are gone. *Upcoming* shows the next 5 items from `GET /agenda`: the user's own open tasks (overdue first, in amber) and upcoming events, plus upcoming events (not tasks) on their claims and leads. It's hidden when empty, unless the user can create tasks. *Recent claims* shows the 3 most recently updated claims. Status overview and Recent activity stay below.
57. **New Task** is for staff and portal adjusters only (`canCreateTasks` from the server, same rule as the portal). A task is on a claim, assigned to someone on the End User or Standard Platform User profiles, defaulting to the user when they're on that list.
58. **"Ask Question"** replaces "Request Assistance" everywhere in the app (Home, claim and lead detail, Support). The portal web pages still say Request Assistance; the case it creates is the same.
59. **All-day events** are shown on their UTC date, because Salesforce stores them at midnight UTC.
60. **Photos over 4 MB** after the 4,000 px downscale are re-encoded at smaller sizes (down to 1,600 px) until they fit. HEIC stays HEIC; JPEG and PNG become JPEG. Documents over 4 MB are still refused.

61. **Search** covers claims, leads and support cases for portal users (their own lists), and claims and leads for staff (Salesforce search with their sharing). Staff can't open cases in the app, so cases aren't searched for them. It's online only.
62. **Chatter for staff:** Recent activity mixes in the latest posts from the staff member's Chatter news feed (`internal` community, News feed). Posts on a claim or lead open that record; others (on users or groups) are shown but not tappable. A failed feed just leaves posts out.
63. **New Event** has the same permission and assignee rules as New Task. All-day events send a date; others send start and end times. The org's managed calendar package (okt_calendar) rewrites event subjects and locations on save, the same as for events created in Salesforce.
64. **Ask Question** isn't on Home (the top-bar icon was removed at the business's request). It's on claim and lead detail and the Support tab.
65. **Status overview** was removed from Home at the business's request.

66. **Salesforce blue and white theme (2026-10-12, at the business's request):** brand `#0B5CAB` for text and controls (Salesforce's `#0176D3` fails 4.5:1 on tinted backgrounds, so it's only used in gradients and large accents), navy `#014486`, cool off-white background `#F4F7FB`, white cards with soft shadows (on the card shape only; a shadow on the whole card also blurs the text and fails contrast), solid brand icon circles on the quick actions, a hero gradient from `#0A62C2` (white text 5.9:1), capsule buttons, a gradient hero on Home and a gradient splash. Contrast was measured for every text/background pair in both modes. "Engagement" features are data-driven, not decorative: global search front and centre, and friendly dates ("Today", "Tomorrow", weekday names).
67. **Emails aren't tasks:** Upcoming leaves out open tasks with Subtype Email or List Email, or a subject starting "Email:". In prod, all 654 of the admin's open "tasks" were synced emails.
68. **Global search lives in the Home hero** (2026-10-12, at the business's request), replacing Next up and the "new updates" chip; the top bar keeps only the bell (unread count stays on its badge). Recent searches (up to 6) are kept in UserDefaults on the device because they can contain customer names; they're cleared at sign-out and never sent anywhere. Scope chips filter the results already fetched, so switching scope is instant and costs no extra calls.
69. **TestFlight setup (2026-10-12):** team `62Z8PRAHTS`, automatic signing. `ITSAppUsesNonExemptEncryption` is `NO`: the app's only encryption is HTTPS and the encryption built into iOS (keychain, data protection) that the Mobile SDK uses for stored tokens and data, which Apple treats as exempt. The business should confirm this; if it's wrong, App Store Connect needs export compliance documents instead.
70. **Tasks and events on leads (2026-10-12):** New Task and New Event can go on a claim or a lead, with the same permission and assignee rules. The lead picker lists the user's leads (the same list as the Leads tab).
71. **Staff vs portal users in the app** comes from the SDK's identity data (user type `STANDARD` = staff). Recent activity: staff can filter Chatter / Portal updates / All and start on Chatter; portal users only ever see portal updates. Demo mode behaves as staff.
72. **New Claim (staff, 2026-10-12)** follows the Prospect Conversion Guided Process as retrieved from prod, minus the Prospect-only steps (files, Prospect status, referred-by fields). Guardrails kept exactly: a new account can't be created while a Residential account has the same email or the same first and last name (no override, as in the flow); a new company account can't be created while one has the same name; new contacts go through the duplicate rules. The server re-checks all of these on create and rolls back on any failure, so a stale app can't create a duplicate. Account duplicate rules are also consulted when active (the person-account rule is currently inactive in prod). Portal users keep My Claims (the business's choice).
73. The flow's account email match treats a blank email as "no email match" (the flow would compare blank to blank). Claim name is prefilled with the account name for the user to finish ("Smith - Roof").
74. **People search is staff only (2026-10-13):** portal users don't see employees in search, and the people and Chatter routes return 404 for them. "Edit Chatter replies inline" is read as both replying and editing your own replies in place; Chatter enforces who may edit (if comment editing is off in Chatter settings, the edit fails with a message). Profile photos aren't shown (they need an authenticated image request); initials are used.
75. **Claim/Lead lookups** filter the user's own claim and lead lists on the device (by name or address); no extra server call. The bell is 15% smaller (icon and button), scaling with Dynamic Type; the button is 38 pt, under the 44 pt guideline, but the bar's glass button keeps a larger hit area.
76. **Claim record page for staff (2026-10-13):** each quick action mirrors its Salesforce counterpart as retrieved from prod: Apply Payments saves through `PaymentCalculatorController2` (same rules as Apply_Payments_Mobile; payment files aren't uploaded from the app yet); Add Contact follows Add_Claim_Contact's matching (email, mobile, or name) and refuses a contact already on the claim; Proof of Loss edits the 13 fields of `proofOfLossDataEntry`, and document generation opens Salesforce's DocMerge page in the in-app browser (the user may need to sign in there; not in demo mode). Edit Claim covers the core fields (the business's choice). Send an Email goes through Salesforce (not the iPhone Mail app) and is logged as an EmailMessage on the claim; "From" offers the user and org-wide addresses open to all profiles. The collapsible progress card and "Contact Us" apply to everyone; actions, communication and the Claim Feed are staff only.
77. **Request of 2026-10-14:** "Home page" items 2–4 (Deductible, Peril, Log a Call) were read as the claim page, where those fields and actions are. Lists that show "3 at a time" scroll inside a box sized to the first three. Edit on the lead is a text "Edit" button (as asked); Edit on claims stays an icon.
78. **Convert to Account** is native (the business's choice) and builds the claim on the server from the lead exactly as the guided flow does. Where the lead's picklist values don't exist on claims (peril "Wind/Tree" vs the claim's "Windstorm /Tree", see the peril pipeline note), the claim's value is left blank instead of failing the conversion as the flow would. Add Comment is removed from leads, as on claims (the business's choice).
79. **Salesforce pages open signed in (2026-10-15):** E-Sign and Generate Proof of Loss Document open DocMerge through a single-use front-door link from `POST /services/oauth2/singleaccess` (verified in prod: returns `frontdoor_uri` with `otp` and `startURL`), so the in-app browser doesn't ask for a second login. The OAuth token never goes in a URL. If the call fails, the plain page opens (and may ask to sign in). Orgs that lock sessions to an IP address may still prompt.

## Open questions

1. ~~**API access for Customer Community Login users**~~ **Resolved 2026-10-12:** the "Portal Mobile App" permission set (Customer Community Login licence, API Enabled, PortalApiV1 access) works. A portal user signed in through the app and loaded live data. Assign it to every portal user who uses the app.
2. **Privacy policy and terms URLs** for the Account screen (spec §6.11).
3. **App icon and vector logo** from the designer. *Temporary icon added 2026-10-12* (white house with a checkmark on the hero gradient, plus dark and tinted variants; drawn by `Tools/make-app-icon.swift`) so TestFlight uploads pass. Replace the three PNGs in `AppIcon.appiconset` when the real icon arrives.
4. ~~**Consumer key**~~ **Resolved:** the External Client App is deployed and its key is in `bootconfig.plist`.
5. **Files over 4 MB.** The Apex REST layer caps uploads and downloads at 4 MB. Larger files (big PDFs) need another route, e.g. the standard ContentVersion REST API once portal users have API access.
6. **Push setup:** an Apple Developer team, an APNs key added to the External Client App's push settings, and the server-side trigger (spec §8).
7. **Universal links:** the portal must serve `/.well-known/apple-app-site-association` for the app's team and bundle id, and the app needs the Associated Domains entitlement (`applinks:portal.accurateadjustmentsga.com`). Both need the Apple team id.
8. **Should location metadata be stripped from all photos before upload?** It's currently only dropped when a photo is downscaled.
9. **Brand colours:** the designer should confirm the Salesforce-blue theme in assumption 66, including its dark-mode values.
10. ~~**Should the API refuse internal users?**~~ **Decided 2026-10-12:** no. Staff use the app too, with the "Portal Mobile App (Staff)" permission set.
