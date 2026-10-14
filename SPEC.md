# Accurate Adjustments GA — iOS App Build Spec

> **For the AI coding agent:** This is the product and technical specification for a native iOS app. Build what is described here. Where this spec is silent, follow Apple Human Interface Guidelines and Salesforce Mobile SDK conventions, and list your assumptions in `ASSUMPTIONS.md` in the app repo instead of asking. Do not invent features, fields or endpoints that are not listed here. If you need one, add it to "Open questions" in `ASSUMPTIONS.md`.

---

## 1. Product summary

Accurate Adjustments GA is a public adjusting firm. It represents property owners in insurance claims for storm, water, fire and similar damage. Today, customers and referral partners use a Salesforce Experience Cloud portal at `https://portal.accurateadjustmentsga.com/s/` to:

- track their property **claims** through a 7-stage lifecycle
- read **updates** published by their public adjuster team
- upload **photos and documents**
- see **payments** collected from the insurer
- submit and track **leads** (potential new claims)
- open **support cases** and message their account manager

The iOS app brings these same capabilities to iPhone as a fast, native experience. It adds features the website can't offer: push notifications, camera uploads, Face ID, and tap-to-call/email.

**Version 1 goal:** match the portal's customer and partner functionality exactly, plus the native enhancements in §8. Nothing more.

---

## 2. Users

All users sign in with their **existing portal credentials**. They are Salesforce Experience Cloud users with the *Customer Community Login* licence. One user can play both roles below, so the app must not force a choice. Show whichever sections have data.

| Role | Who | What they use |
|---|---|---|
| **Homeowner / insured** | A property owner with a claim in progress | Claims, claim updates, files, payments, support |
| **Referral partner** | A contractor, roofer or agent who sends leads to the firm | Submit a Lead, My Leads (matched by their email address), lead updates, support |

**Out of scope for v1:** portal adjusters, meaning users with the `Edit_Claim_Status` custom permission. They can change claim status and manage tasks and commissions in the portal. Don't build those screens. The backend rejects those actions for everyone else anyway.

---

## 3. Technical stack and constraints

| Area | Requirement |
|---|---|
| Language / UI | Swift 5.9+, **SwiftUI**, iOS **17.0+**, iPhone only (portrait first; support Dynamic Type and Dark Mode) |
| Salesforce | **Salesforce Mobile SDK for iOS** (latest; add via Swift Package Manager): `SalesforceSDKCore` for OAuth, token refresh and the REST client; `MobileSync`/`SmartStore` for the offline cache |
| Login | OAuth 2.0 through the **Experience Cloud login host** `portal.accurateadjustmentsga.com`, *not* `login.salesforce.com`. Use the SDK's standard login flow so forgot-password and the site's branded login page work. |
| Salesforce app config | An External Client App or Connected App (created by the Salesforce admin) with scopes `api`, `refresh_token`, `web`; callback URL provided by the admin; push notifications enabled (§8) |
| Data access | **Only** through the Apex REST endpoints in §5. Don't query objects directly with SOQL or the UI API. All business rules and access control are on the server. |
| Architecture | MVVM with `@Observable` view models; one `PortalAPI` service wrapping the SDK REST client; `async/await`; no third-party UI frameworks |
| Rich text | Update bodies (the `text` field of updates and activity items) are **HTML**. Render them safely as `AttributedString` and strip scripts. Links open in `SFSafariViewController`. Everything else, including `lossDescription`, case descriptions and case comment `body`, is **plain text**. Show its line breaks as they are and don't parse it as HTML. |
| Current user | The user's first name, full name and email (for the Home greeting, Account and Submit a Lead) come from the SDK's identity data for the signed-in account (`UserAccountManager.shared.currentUserAccount?.idData`). There is no `/me` endpoint. |
| Formatting | Currency USD (`$12,500.00`); dates in the user's locale; percentages for adjuster fees |
| Testing | Unit tests for view models and JSON decoding (fixtures in §5); SwiftUI previews with mock data for every screen; UI test for login → claim detail |

> **Prerequisite, resolved 2026-10-12:** Customer Community Login users can call the REST API through the External Client App when they have the **Portal Mobile App** permission set (API Enabled plus access to `PortalApiV1`). A portal user signed in through the app on the simulator and loaded live data. The mock `PortalAPI` with JSON fixtures remains for demo mode and tests.

---

## 4. Information architecture

**Tab bar (5 tabs):**

1. **Home**: dashboard, recent activity, quick actions
2. **Claims**: claim list → claim detail
3. **Leads**: lead list → lead detail; "Submit a Lead" button
4. **Support**: support cases → case thread; "Request Assistance" button
5. **Account**: profile, notification settings, Face ID toggle, sign out

**Global:** a bell icon in the navigation bar of Home, Claims and Leads opens **Notifications** and shows an unread badge count. Global **Search** opens from the search bar in the Home hero.

**Empty-state rule:** if a user has no claims, the Claims tab still appears with a friendly empty state ("No claims yet") and a link to Support. The same applies to Leads.

---

## 5. Backend API contract

The Salesforce team will expose these as Apex REST endpoints under `/services/apexrest/portal/v1/`. Most wrap an existing portal controller method, so their response shapes match what the portal already uses. Endpoints marked **[new]** have no existing controller and must be built: file download and upload, the peril picklist, and device registration. Every endpoint runs as the logged-in user and returns **only that user's records**. Record-level endpoints return `404` for records the user doesn't own. Treat `401` as "session expired → re-login" and anything else `>= 400` as a retryable error.

**Record types:** a lead is stored as a `Prospects__c` record. Wherever a response includes `relatedRecordType`, the value is `"Claim"` or `"Prospect"`; `"Prospect"` means a lead. Show it as "Lead" in the UI.

**Built:** `PortalApiV1` (`@RestResource(urlMapping='/portal/v1/*')`). Errors are `{"error": "<code>"}` with codes `not_found`, `invalid_request`, `invalid_json`, `invalid_peril`, `too_large`, `unsupported_type` or `server_error`; exception messages are never returned. Successful POSTs that return a body use `201`. Portal users need the **Portal Mobile App** permission set (API Enabled and access to `PortalApiV1`).

> **Notes for the Salesforce team building this layer:**
> - The existing controllers throw `AuraHandledException` when access is denied. Map that to `404` and validation errors to `400`. Don't let them surface as `500`.
> - Every method that takes a record ID must call `PortalRecordAccess.assertCanAccessClaim` or `assertCanAccessProspect`. The new file download endpoint must also check that the file is linked to a claim or lead the user can access.
> - Lead files must wrap `ProspectRecordBannerController.getProspectFiles`, not `ProspectCommunityFileController.getFiles`. The latter doesn't return `createdByName` and has no access check.
> - `GET /picklists/peril` must return the active values of `Prospects__c.Peril__c`. That field is restricted, so it's the one `POST /leads` validates against.

### 5.1 Claims

`GET /claims` → `[RelatedClaim]`
```json
{
  "recordId": "a0X...", "recordName": "Smith - Roof", "claimNumber": "CLM-1234",
  "policyNumber": "POL-5678", "claimStatus": "Inspection", "peril": "Wind",
  "lossAddress": "123 Main St, Atlanta, GA 30301", "lossDate": "2026-08-14",
  "lossReason": "Storm", "paymentCollected": 12500.00,
  "adjusterName": "Jane Doe", "accountManagerName": "Sam Lee",
  "lastModifiedDate": "2026-10-01T14:22:00Z"
}
```

`GET /claims/{id}` → `ClaimDetail`
```json
{
  "claimName": "...", "claimStatus": "Negotiations", "peril": "Water",
  "lossAddress": "...", "email": "...", "mainPhone": "...", "businessEmail": "...",
  "adjusterName": "...", "adjusterEmail": "...", "adjusterPhone": "...",
  "deskAdjusterName": "...", "deskAdjusterEmail": "...",
  "accountManagerName": "...", "accountManagerEmail": "...", "accountManagerPhone": "...",
  "insuranceCompanyName": "...", "insuranceMainPhone": "...",
  "claimNumber": "...", "policyNumber": "...",
  "dateClaimFiled": "2026-08-20", "dateOfClaim": "2026-08-15", "lossDate": "2026-08-14",
  "lossDescription": "Wind damage to roof.\nWater intrusion in the upstairs bedroom.", "photosUrl": "https://...",
  "adjusterFees": 10, "deductible": 1000.00, "paymentCollected": 12500.00, "totalRcv": 48000.00
}
```
`paymentCollected` is never null and always matches the value in `GET /claims` for the same claim. Any other numeric field may be null; show "—".

`GET /claims/{id}/updates` → `[Update]`: published updates from the adjuster team, newest first
```json
{ "commentId": "a1Y...", "relatedRecordId": "a0X...", "relatedRecordName": "...",
  "createdDate": "2026-10-02T15:00:00Z", "title": "Carrier review update", "text": "<p>...</p>" }
```

`GET /claims/{id}/payments` → `[Payment]` (up to 50)
```json
{ "paymentsId": "a2Z...", "paymentsName": "PMT-0001", "dateOfNotice": "2026-09-30",
  "netDeposit": 8000.00, "insuredPayment": 4500.00, "totalRcv": 48000.00 }
```
Display labels: **Date of Notice**, **Net Deposit**, **Insured Payment**, **Total RCV**. These are the labels the portal uses today. (`insuredPayment` comes from the `Contractor_Payment__c` field; the business is confirming that label is correct.)

`GET /claims/{id}/files` → `[File]` (up to 50)
```json
{ "contentDocumentId": "069...", "title": "Roof photo 1", "fileType": "JPG",
  "contentSize": 2048000, "createdDate": "...", "createdByName": "..." }
```

**[new]** `GET /files/{contentDocumentId}/content` → binary download (for preview). Only files linked to one of the user's claims or leads; otherwise `404`.
**[new]** `POST /claims/{id}/files?fileName={name}&title={title}` → upload → `201` with `File`. The request body is the file's bytes, and `Content-Type` is its MIME type. (Apex can't parse multipart bodies, so this isn't multipart.) Allowed extensions: pdf, png, jpg, jpeg, heic, doc, docx, xls, xlsx; anything else is `400 unsupported_type`.

**File size:** uploads and downloads are limited to **4 MB** (`400 too_large`), because Apex REST bodies count against the 6 MB heap. Photos downscaled to 4,000 px usually fit; large PDFs may not.

`POST /claims/{id}/comments` `{ "text": "..." }` → `204`. Sends a private comment to the account manager. On claims, it is **not** shown back in the updates feed. Max 5,000 characters.

### 5.2 Leads (prospects)

`GET /leads` → `[Lead]`
```json
{
  "recordId": "a0P...", "recordName": "...", "prospectStatus": "Working",
  "lossAddress": "...", "lossDate": "...", "peril": "...", "claimNumber": "...", "policyNumber": "...",
  "customerEmail": "...", "associatedPartyName": "...", "associatedPartyCompany": "...",
  "associatedPartyEmail": "...", "insuranceCompanyName": "...",
  "adjusterName": "...", "accountManagerName": "...", "lastModifiedDate": "...",
  "agreementSentDate": "2026-09-01T...", "agreementCompletedDate": null
}
```

`GET /leads/{id}` → `LeadDetail`: contact and loss fields (`prospectName`, `prospectStatus`, `peril`, `lossAddress`, `email`, `phone`, `mobile`, `associatedParty*`, adjuster/desk adjuster/account manager name, email and phone, `insuranceCompanyName`, `claimNumber`, `policyNumber`, `didFileClaim`, `adjusterFees`, `lossDate`, `lossDescription`, `documentsUrl`, `createdDate`, `lastModifiedDate`) plus:
```json
"agreement": { "hasAgreement": true, "agreementId": "a3S...", "agreementName": "Public Adjuster Agreement",
  "agreementStatus": "SENT", "sentDate": "...", "viewedDate": null, "completedDate": null }
```
`agreementStatus` is `"SENT"` or `"COMPLETE"`. `COMPLETE` means signed, and `completedDate` is only set then. `viewedDate` is always `null`, because the e-signature integration doesn't record when an agreement is viewed. Don't build a "Viewed" step. When `hasAgreement` is `false`, every other agreement field is `null`.

`lossAddress` on leads (both list and detail) can contain a line break between the street and the "city, state, ZIP" line. Claim addresses are a single line.

`GET /leads/{id}/updates`, `GET /leads/{id}/files`, `POST /leads/{id}/files`, `POST /leads/{id}/comments`: same shapes as for claims, with one difference in behaviour. **On leads, a comment the user sends is published to the lead's updates feed** with the title "Customer Comment", as the portal does today. After a successful lead comment, refresh the updates list. The activity feed and push notifications never include the user's own comments.

`POST /leads` → creates a lead. Returns `{ "recordId": "a0P..." }`. The server returns `400` if `leadName` is blank, or if `email` and `phone` are both blank. It always sets `associatedPartyEmail` to the signed-in user's email and ignores any value the app sends. The app can still send it.
```json
{
  "leadName": "Jane Smith", "email": "...", "phone": "...",
  "street": "...", "city": "...", "stateCode": "GA", "postalCode": "30301",
  "peril": "Wind", "lossDescription": "...", "fileLink": "https://...",
  "insuranceCompanyId": "a0I...", "policyNumber": "...",
  "didFileClaim": "Yes", "claimNumber": "...",
  "associatedPartyCompany": "...", "associatedPartyName": "...",
  "associatedPartyPhone": "...", "associatedPartyEmail": "<current user email>"
}
```

`GET /insurance-companies?q=sta` → `[{ "id": "...", "name": "State Farm" }]` (up to 10; typeahead)
**[new]** `GET /picklists/peril` → `["Wind", "Hail", "Water", ...]`. Don't hard-code peril values; they change.

### 5.3 Activity and notifications

`GET /activity` → `[ActivityItem]`: the latest published update for each of the user's claims and leads
```json
{ "commentId": "...", "relatedRecordId": "...", "relatedRecordName": "...",
  "relatedRecordType": "Claim" | "Prospect", "createdDate": "...",
  "title": "...", "text": "<p>...</p>", "isRead": false }
```
At most one item per record (that record's latest update), newest first. The user's own comments are excluded.
`POST /activity/read` `{ "commentIds": ["..."] }` → `204` (idempotent)

### 5.4 Support cases

`GET /cases` → `[Case]`
```json
{ "caseId": "500...", "caseNumber": "00012345", "subject": "...", "description": "...",
  "status": "New", "createdDate": "...", "relatedRecordId": "a0X...", "relatedRecordName": "...",
  "relatedRecordType": "Claim" | "Prospect", "relatedRecordStage": "...", "accountManager": "..." }
```
Returns the cases where the user is the case contact. This includes every case they opened with Request Assistance. All the `relatedRecord*` fields are `null` when a case isn't linked to a claim or lead. `relatedRecordStage` is only set for claims.

`GET /cases/{id}` → `Case` + `"comments": [{ "commentId", "body", "authorName", "createdDate", "isOwn" }]`. Comments are oldest first. `body` is plain text.
`POST /cases/{id}/replies` `{ "body": "..." }` → `204` (max 2,000 characters)
`POST /cases` `{ "recordId": "<claim or lead id>", "comments": "..." }` → `{ "caseId": "..." }` (Request Assistance; max 5,000 characters; also emails the account manager)

### 5.5 Agenda and tasks

`GET /agenda` → `{ "items": [AgendaItem], "canCreateTasks": true }`: the user's own open tasks (excluding logged or synced emails: Task Subtype Email or List Email, or a subject starting "Email:") and upcoming events, plus upcoming events (not tasks) on the claims and leads they can see, earliest first (undated tasks last; up to 20). Overdue open tasks are included.
```json
{ "id": "00T...", "kind": "task" | "event", "subject": "...",
  "dueDate": "2026-10-16", "startDateTime": "...", "endDateTime": "...", "isAllDay": false,
  "location": "...", "status": "Not Started", "isOverdue": false, "assignedToName": "...",
  "relatedRecordId": "a23...", "relatedRecordName": "...", "relatedRecordType": "Claim" | "Prospect" | null }
```
`canCreateTasks` is true for internal staff and portal adjusters (the `Edit_Claim_Status` custom permission), the same people who manage tasks in the portal.

`GET /task-assignees` → `[{ "userId", "name" }]`: active users on the End User and Standard Platform User profiles. `404` unless `canCreateTasks`.
`POST /claims/{id}/tasks` or `POST /leads/{id}/tasks` `{ "subject", "dueDate"?, "assignedToId", "description"? }` → `201` `{ "recordId" }`. Subject is required (max 255); the assignee must be on the list above (`400 invalid_assignee`). `404` unless `canCreateTasks`.

`POST /claims/{id}/events` or `POST /leads/{id}/events` `{ "subject", "isAllDay", "date"? (all-day), "startDateTime"?, "endDateTime"?, "location"?, "assignedToId", "description"? }` → `201` `{ "recordId" }`. The end must not be before the start. Same permission and assignee rules as tasks. (A managed calendar package in the org rewrites event subjects and locations on save, as it does for events created in Salesforce.)

### 5.6 Search and Chatter

`GET /search?q=` (2+ characters) → `[{ "type": "Claim" | "Prospect" | "Case", "id", "title", "subtitle" }]`. Portal users: matches in their own claims, leads and cases (up to 20 of each). Staff: a SOSL search over claims and leads that respects their sharing (cases aren't included, because staff can't open cases in the app).

`GET /feed` → `[{ "id", "authorName", "text", "createdDate", "parentId", "parentName", "parentType": "Claim" | "Prospect" | null }]`: the latest 20 posts in a staff member's Chatter news feed. Empty for portal users.

### 5.6a People and Chatter (staff)

All return `404` unless the user is internal (user type Standard), and only for active internal users.

- `GET /search?q=&includeUsers=true` also returns `{ "type": "User", "id", "title": name, "subtitle": "Title · Department" }` (SOSL on name fields, 20 at most). Without `includeUsers`, no people are returned, so older app builds never see the "User" type.
- `GET /people/{id}` → `{ id, name, title, department, email, phone, mobilePhone, aboutMe, city, state, managerName, isMe }`.
- `GET /people/{id}/feed` → their Chatter profile feed (ConnectApi, `UserProfile`, 20 newest): `[{ id, authorName, text, createdDate, parentName?, totalReplies, replies: [{ id, authorName, text, createdDate, isMine }] }]`. Posts without text are skipped. `parentName` is set when the post is on something other than their profile.
- `POST /chatter/posts/{postId}/replies` `{ text }` → `201` the reply.
- `POST /chatter/replies/{replyId}` `{ text }` → `201` the edited reply. Chatter decides who may edit (normally only the author, and only if comment editing is on); otherwise `400 edit_not_allowed`.
- Text is required and at most 10,000 characters. Everything runs through ConnectApi as the user, so Chatter's own visibility rules apply.

### 5.6b Claim actions (staff)

`PortalClaimActionsService`. All routes are under `/claims/{id}/…` after the usual claim access check, and return `404` unless the user is internal. Errors a user can fix come back as `400 {"error":"validation","message":"…"}` (including the org's validation rules, e.g. Required_for_Inspection), and the app shows the message.

- `GET staff` → the claim's editable values, Proof of Loss fields, and choices: stages, perils, states, occupancy and primary-home values, contact roles, internal users, email recipients (claim email, account email, claim contacts), "From" addresses (the user and org-wide addresses open to all profiles), and the claim's contacts.
- `POST edit` → Edit Claim: name, stage, peril, loss date and description, claim and policy numbers, insurance company, deductible, adjuster fees (≤ 100), account manager.
- `POST address` → Update Address (the Update_Address quick action's fields). `POST owner {ownerId}` → Change Owner (active internal users).
- `POST proof-of-loss` → the 13 fields of the proofOfLossDataEntry component. The expiration date must be after the effective date.
- `GET payment-setup` and `POST payments {dateCollected, notes, applyDeductible, rows:[{rowType, amount}]}` → Apply Payments, saved through `PaymentCalculatorController2.savePaymentBundle2Json`, as the Apply_Payments_Mobile quick action. Blocked without a deductible; hidden types (ACV, Recoverable Depreciation, Deductible (Commissions)) are refused; no hand-entered Deductible row when the deductible is applied.
- `GET contact-matches?firstName&lastName&email&mobile` and `POST contacts` → Add Contact (Add_Claim_Contact): matches on email, mobile phone, or first and last name; `409 already_linked` if the contact is already on the claim; new contacts follow New Claim's rules (duplicate rules, subcontractor company account).
- `GET feed`, `POST posts {text}` → the claim's Chatter feed, and Add a Post. Replies use §5.6a.
- `POST calls {subject, description?, contactId?}` → Log a Call: a completed Call task on the claim.
- `POST emails {fromAddressId?, to[], cc[], bcc[], subject, body}` → Send an Email: sent through Salesforce and logged on the claim as an EmailMessage.

### 5.7 New Claim (staff)

The Prospect Conversion Guided Process (`Prospect_Conversion_Guided_Process` flow) without a Prospect, in `PortalNewClaimService`. Every route returns `404` unless the user is internal (user type Standard).

- `GET /new-claim/options` → `{ perils, states, sources, defaultSource, contactRoles, users: [{userId, name}], currentUserId }`. `users` are active internal users, for Adjuster (the claim owner) and Account Manager.
- `GET /new-claim/accounts?q=&type=commercial?` → accounts whose name contains `q` (2+ characters, 20 at most): `[{ id, name, email, phone, city, state, kind: "Person"|"Business" }]`.
- `GET /new-claim/account-matches?firstName=&lastName=&email=` → Residential (record type Name `Residential1`) accounts with the same email, **or** the same first and last name (the flow's `Get_Matching_Person_Accounts`), plus anything the active Account duplicate rules match.
- `GET /new-claim/partner-matches?name=` → Commercial accounts with exactly this name (`Get_Matching_Partner_Accounts`).
- `GET /new-claim/contacts?q=` and `GET /new-claim/contact-matches?firstName=&lastName=&email=` → `[{ id, name, email, phone, accountName }]`; matches are the same email, or the same first and last name (`Get_Matching_Contacts`).
- `POST /new-claim` `{ account: {id} | {new: {firstName?, lastName, email?, phone?}}, claim: {name, street?, city?, state?, postalCode?, lossDate?, peril?, lossDescription?, claimNumber?, policyNumber?, insuranceCompanyId?, email?, phone?, source?, adjusterFees?, ownerId?, accountManagerId?}, contact?: {id, role} | {new: {firstName?, lastName, email?, phone?, company?}, role, partnerAccount?: {id} | {name}} }` → `201 { recordId, accountId }`.
  - One transaction: the person account (with the flow's `Create_Person_Account` fields: billing address = loss address, claim and policy numbers, description of loss, insurance company, email, phone, lead source), then the claim (`Create_Claim` fields, with the account), then the partner account and contact if new, then the `Claim_s_Contacts__c` link with the role. Any failure rolls everything back.
  - **Duplicates are always checked on the server**, whatever the app did: a new account with matches → `409 {"error":"duplicate_account","matches":[accounts]}`; a new partner account whose name exists → `409 duplicate_partner_account`; a new contact the active duplicate rules match → `409 duplicate_contact` with the contacts (as `CreateAssociatedPartyContactAction`). Nothing is created.
  - A new subcontractor (`Sub-Contractor`) contact needs `partnerAccount` (`400` otherwise). Owner defaults to the user; the source defaults to the picklist default. Picklist values, users, accounts, contacts and the insurance company are all checked (`400`).

### 5.8 Device

**[new]** `POST /devices` `{ "apnsToken": "..." }`: only if the SDK's built-in push registration isn't used (§8). *Not built: the app uses the SDK's push registration.*

---

## 6. Screens

### 6.1 Login
- Use the Mobile SDK's login screen pointed at the portal domain. Show the Accurate Adjustments logo above it.
- After the first successful login, offer **Face ID** (§8).

### 6.2 Home
1. **Hero:** a Salesforce-blue gradient card with today's date, "Welcome back, {firstName}!", the subtitle "We're here to help with your claim", and a white search bar, "Search claims, leads and cases", that opens global Search.
2. **Top bar:** the notifications bell only, 15% smaller than a standard bar button (14.5 pt icon, 38 pt button, both scaling with Dynamic Type).
   **Search sheet** (over `GET /search`, starting at 2 characters with a 300 ms debounce):
   - The field is focused and the keyboard is up as soon as the sheet opens.
   - The X at the top left always closes the sheet, even while typing. (The field is the app's own, not the system search bar, whose X only cancels the search.)
   - Scope chips: All, Claims, Leads and Cases, each with its result count, plus People for staff (§5.6a). People come first in the results.
   - Tapping a person opens their page inside the sheet: profile (photo initials, title and department, location, email and phone links, manager, About) and their Chatter feed. Each post has an inline reply box, and the user's own replies have an Edit button that edits the text in place (Save / Cancel). Filtering by scope happens on the device; it doesn't search again.
   - Before typing: up to 6 recent searches (newest first; tap one to run it again; *Clear* removes them). With no recents, tips show what can be found: a claim name or number, an address, a lead's name or email, and a case subject or number.
   - Results are grouped by type, with a count per group. The matching text is bold and blue. Tapping a result opens it.
   - When nothing matches, the sheet says so and suggests what else to try. If the current scope is empty but other scopes have results, it offers "Show all {n} results".
   - A search is saved to recents when it is submitted or a result is opened. Recents are stored on the device and cleared at sign-out.
   - Offline, the sheet says search needs a connection.
3. **Quick actions**, directly under the welcome, in two columns: *New Lead* | *New Event*, then *New Claim* (staff) or *My Claims* (portal users) | *New Task*. New Lead opens Submit a Lead. New Event and New Task appear only when `canCreateTasks`. Both forms start with *Related to*: a Claim | Lead switch, then a lookup that opens a searchable list of the user's claims or leads (search by name or address). Each row shows the name, **loss address** and status, and the chosen record's address shows on the form, so the right one is easy to confirm. New Task: related record, subject, optional due date, assign to (defaults to the user), details. New Event: related record, subject, all day or start/end (defaults to the next hour, for an hour), optional location, assign to, details.
   **New Claim** (staff) opens a sheet that follows the Prospect Conversion Guided Process:
   1. *Who is this claim for?* **Existing account** (search by name) or **New account**.
   2. New account: first name, last name (required), email, phone. Before anything is created the app asks for matches (§5.7). If there are any, the user **must choose one of them**; there's no way to create the new account while a match exists (as in the flow, where the matches table requires a selection). To change the person, go back and edit the details.
   3. Claim details: claim name (prefilled from the account), peril, loss date, description, loss address, insurance company (type-ahead), policy and claim numbers, homeowner email and phone (prefilled), adjuster (defaults to the user), account manager, source (picklist default), adjuster fees (0–100%).
   4. Claim contact (optional): None, Existing (search by name or email) or New, with a role (Property Contact, Sub-Contractor, Adjuster, Other). A new contact is checked for matches first; the user picks a match or chooses "None of these are a match". A new Sub-Contractor needs a company (Commercial) account: if one has the contact's company name, it must be chosen; otherwise pick an existing one or create it.
   5. Review, then **Create Claim**. If the server finds a duplicate, the app goes to the matching step to pick it (for a contact: use the existing one or skip the contact). On success the claim is saved, the sheet closes, and the app switches to the Claims tab and opens the new claim's detail page (after the sheet has finished closing, so the navigation isn't lost).
4. **Upcoming:** the next 5 items from `GET /agenda`, tasks with their due date (overdue ones in the warning colour) and events with day and time (or "All day", shown in UTC as Salesforce stores them), plus the related claim or lead and an event's location. Tapping an item with a related record opens it. Hidden when empty, unless the user can create tasks ("Nothing scheduled").
5. **Recent claims:** the 3 most recently updated claims, with status; tap to open, "See all" opens Claims.
6. **Recent activity:** published updates from `GET /activity` and, for staff, Chatter posts from `GET /feed`, newest first (8 at most). Staff (Salesforce user type Standard) get filter chips *Chatter* (the default), *Portal updates* and *All*. Portal users see portal updates only, with no filter, and the app doesn't call `GET /feed` for them. Each entry's header is its record: the type in regular weight and the name in bold ("Claim · **Smith - Roof**"), with a line under it saying what it is ("Portal update · {title}" or "Chatter · {author}"). Chatter posts not on a claim or lead show the group or user name as the header. Unread updates show a dot; tapping one opens the **Update sheet** (title, date, rendered HTML, and an "Open {Claim|Lead}" button) and marks it read. Tapping a Chatter post on a claim or lead opens that record.
7. Pull to refresh.

*(Changed 2026-10-12: the KPI tiles were replaced by Upcoming and Recent claims; "Request Assistance" is called "Ask Question" throughout the app (it's on claim and lead detail and Support; not on Home); Search, New Event, staff Chatter posts and the hero were added (search later moved from the top bar into the hero, replacing Next up and the unread chip); the status overview was removed; emails no longer appear in Upcoming; tasks and events can go on leads; Recent activity has record headers and a staff filter; Submit a Lead is New Lead on Home, and staff get New Claim.)*

### 6.3 Notifications (sheet from the bell icon)
- An **Unread / All** segmented control over `GET /activity`.
- Tapping an item opens the Update sheet and marks it read. **Mark all read** calls `POST /activity/read` with every unread ID.
- Empty state: "No unread notifications".

### 6.4 Claims list
- A search bar that matches claim name, claim number, address, status or peril, done on the device.
- Filters: **Status** (lifecycle stages), **Payment Collected** (*Any*, *Payment received*, *No payment yet*), **Peril** (built from the values in the data). Include **Clear filters**.
- **Claim card:**
  - claim name and claim number
  - status pill
  - loss address
  - peril
  - progress bar and "{n}% complete" (from the lifecycle stage)
  - payments collected
  - account manager
  - "Updated {date}"
- Sort by most recently updated.

### 6.5 Claim detail
**Header:** claim name, claim number, policy number, status pill.

**Top bar:** *Ask Question* (everyone) and *Edit Claim* (staff) as icons at the top right.

**Action strip (staff only)**, directly under the header: one card with round gradient icon buttons and short labels: *Payments* (Apply Payments), *Post* (Add a Post), *Log Call*, *Contact* (Add Contact) and *More* (a menu with *Send an Email*, *Update Address*, *Change Owner* and *Proof of Loss*). Five across; two across at accessibility text sizes. Each opens a sheet (§5.6b):
- **Apply Payments:** date collected, *Apply deductible* (with the claim's deductible), payment rows (type and amount; add and swipe to remove), and a live summary: RCV, payments received (everything except RCV, less any deductible rows), the deductible when applied, the adjuster fee ((received + applied deductible) × fee %), and the insured payment (received − fee, never below 0). Choosing *Deductible* as a type switches on *Apply deductible* instead, as in the quick action. Blocked, with a message, until the claim has a deductible.
- **Add Contact:** Existing (search) or New, with a role. New contacts are checked for matches (email, mobile phone, or name) first; then a company account for subcontractors; a duplicate-rule match lets the user add the existing contact or none.
- **Edit Claim:** the core fields. **Update Address:** with address lookup as you type. **Change Owner:** searchable list of internal users.
- **Proof of Loss:** the 13 fields with "n of 13 complete". *Generate Proof of Loss Document* (once all 13 are saved) opens Salesforce's DocMerge page (`/apex/hic_docmerge__Composer`) in an in-app browser; the user may need to sign in there. Not available in demo mode.
- **Add a Post:** posts to the claim's Chatter feed (staff only; homeowners don't see it). **Log a Call:** subject, optional contact from the claim, notes. **Send an Email:** From (the user or an org-wide address), To (defaults to the claim's email, with one-tap suggestions for the account and claim contacts), Cc, subject and message; sent through Salesforce and logged on the claim.

**Highlights row** (scrolls horizontally): Loss Date · Total RCV · Payments Collected · Deductible.

**Lifecycle:** a 7-stage tracker in this order:
`Preparation → Inspection → Negotiations → Restoration → Litigation → Settlement → Closed`

The card is **collapsible** and starts collapsed: the progress ring and the current status (large and bold) always show; tapping the card (or its chevron) shows or hides the stage list. Stages before the current one show as complete, the current stage is highlighted, and later stages show as upcoming. Show a progress ring with % complete, calculated as round(((index + 1) ÷ 7) × 100), where `index` is the stage's 0-based position. This matches the portal: Preparation 14%, Inspection 29%, Negotiations 43%, Restoration 57%, Litigation 71%, Settlement 86%, Closed 100%. The claim card's progress bar (§6.4) uses the same number. If the status isn't in this list, show the raw status and hide the ring and the bar.

**Segmented sections:**

| Section | Content |
|---|---|
| **Updates** | Published updates (`/updates`), newest first, one card each with title, date and HTML body. Empty state: "No updates have been published for this claim yet." Staff get a *Claim Feed / Portal Updates* filter that starts on **Claim Feed**: the claim's Chatter feed, with inline replies and editing of their own replies (§5.6a). |
| **Details** | *Claim snapshot*: peril, date of claim, loss address (tap to open in Maps), main phone, email, business email. *Loss and documentation*: loss date, date claim filed, loss description (HTML), and the "Photos or documents" link (`photosUrl`) if present. |
| **Insurance** | Insurance company, insurance main phone (tap to call), claim number, policy number, deductible. |
| **Files** | File list showing an icon by type, title, "{type} · {size} · Uploaded {date}" and "Uploaded by {name}". Tapping a file opens it in Quick Look. **Upload** button (§6.10). |
| **Payments** | One row per payment: name, date of notice, net deposit, insured payment, total RCV. Footer: total payments collected. Empty state: "No payment records have been found for this claim." |

**Contact Us card** (formerly "Your public adjuster team"):
- Adjuster: name, tap to call, tap to email.
- Desk adjuster: name, tap to email.
- Account manager: name, tap to call, tap to email.
- Adjuster fees as a %.

**Ask Question** (formerly Request Assistance), from the top-bar icon: a sheet titled "Regarding {claim name}" with a text editor (max 5,000 characters, with a counter) that calls `POST /cases`. There's no Add Comment on claims (removed at the business's request; leads keep it). On success: "Your request has been submitted. We will follow up with you shortly." Offer to open the new case.

### 6.6 Leads list
Same layout as the Claims list, with these differences:
- Filters: **Lead Status**, **Agreement** (*Any*, *Sent*, *Signed*, *Not sent*) and **Peril**.
- The card shows **agreement milestones**: "Sent {date}" and "Signed {date}". When no agreement has been sent, show "Visible once an agreement has been sent."
- A **Submit a Lead** button in the toolbar.
- Subtitle: "Leads connected to your email address."

### 6.7 Lead detail
- **Header:** lead name, status pill, claim number, policy number.
- **Lifecycle:** `New → Working → Qualified → Converted`. If the status is `Unqualified`, show `New → Working → Unqualified` with the last step in a neutral or warning style.
- **Agreement milestones:** Sent → Signed, with dates (`sentDate`, then `completedDate`). Steps not yet reached show as upcoming. When `hasAgreement` is `false`, show "Visible once an agreement has been sent."
- **Sections:**
  - *Updates*
  - *Details*: lead name, peril, loss address, phone, mobile, email, loss description, created, last updated, and the supporting-documents link (`documentsUrl`)
  - *Insurance*: company, claim filed?, claim number, policy number
  - *Files*, with upload
- **Team card** and the **Add Comment** and **Request Assistance** actions, the same as on claims. The one difference: a lead comment appears in the lead's *Updates* section once it's sent (§5.2), so on success show "Your comment has been submitted. Your account manager has been notified." and refresh *Updates*.

### 6.8 Submit a Lead
A single scrolling form in 5 numbered sections, with a sticky **Submit** button:

1. **Claimant information**
   - Name (required)
   - Email and phone. At least one is required; if both are empty, show "Enter at least one contact method: email or phone."
2. **Property address**
   - Street, city, state (US state picker), ZIP code (5 digits)
3. **Loss details**
   - Peril (picker from `GET /picklists/peril`)
   - Loss description (multi-line)
   - Optional link to photos (URL)
4. **Insurance**
   - Insurance company: a typeahead on `GET /insurance-companies`, starting at 2 characters with a 300 ms debounce. Show "No insurance companies found" when nothing matches, and "Insurance company search is currently unavailable." on error.
   - Policy number
   - "Has a claim been filed?" (Yes / No)
   - Claim number, shown only when the answer is Yes
5. **Referral (associated party)**
   - Company, name and phone
   - Email: prefilled with the user's email and **read-only**. This field is how the lead appears in the user's My Leads list.

**After a successful submit:** show the confirmation "Thank you, {name}. We have received your information and our team will review it promptly." Then show the **Supporting files** upload step for the new lead, with a **Done** button that returns to the lead's detail screen.

### 6.9 Support
**Cases list**
- Filter: **All / Open / Closed**.
- Search across subject, description, related record and status.
- Each row shows: case number, subject, status pill, related claim or lead (with an icon), account manager, and created date.
- Intro text: "Use Ask Question when you have a question about a claim or lead, such as a status update, a document request, or a follow-up on an inspection or estimate."

**Case detail**
- Header: subject, case number, status, date filed, account manager, and the related record. Tapping the related record opens the claim or lead detail using `relatedRecordId`. Hide the related record row when `relatedRecordId` is null.
- Description.
- **Case updates** as a chat-style thread. The user's own messages (`isOwn`) are right-aligned.
- A reply composer at the bottom (max 2,000 characters).
- Empty state: "No updates have been posted yet."

**Ask Question** (the toolbar button; formerly Request Assistance)
- Picker: "Claim or Lead" (required), listing the user's claims and leads.
- Comments field (required, max 5,000 characters).

### 6.10 File upload (shared)
- Sources:
  - **Camera** (photo)
  - **Photo Library**, multi-select with `PhotosPicker`
  - **Files**, with `fileImporter`
- Allowed types: `pdf, png, jpg, jpeg, heic, doc, docx, xls, xlsx`.
- Before upload, keep HEIC as it is (the server accepts it) and downscale photos so the longest side is at most 4,000 px.
- Show progress for each file. Uploads continue if the user leaves the screen, and failed uploads can be retried.
- Default title: "Photo {yyyy-MM-dd HH:mm}" for camera photos, otherwise the original file name.

### 6.11 Account
- Name and email (read-only).
- **Notifications** toggle, which deep-links to iOS Settings if notifications are denied.
- **Face ID** toggle.
- Links: *Contact support* (opens Support), *Privacy policy*, *Terms*.
- **Sign out**: revokes the token through the SDK logout and clears the cache and keychain.
- App version and build number.

---

## 7. States and behaviour (all screens)
- **Loading:** skeleton placeholders, not spinners, for lists and detail screens.
- **Error:** an inline message ("Unable to load claims. Pull to refresh or contact support.") with a **Retry** button. Never show raw server errors.
- **Offline:** show the last cached data with a banner reading "You're offline. Showing data from {time}." Disable all write actions, with a tooltip explaining why.
- **Pull to refresh** on every list and detail screen. Refresh automatically when the app returns to the foreground if the data is more than 5 minutes old.
- **Accessibility:** VoiceOver labels on every control, a minimum 44 pt tap target, and full Dynamic Type support up to the accessibility sizes.

---

## 8. Native enhancements (v1)

| Feature | Behaviour |
|---|---|
| **Push notifications** | Use the Mobile SDK push registration with APNs. The server sends a push when (a) a new update is **published** on the user's claim or lead, or (b) staff reply on the user's support case. Payload: `{ "type": "update" \| "caseReply", "recordId": "...", "commentId": "..." }`. Tapping the push deep-links to the record and opens the update. *(The server-side trigger is built by the Salesforce team.)* |
| **Face ID / Touch ID** | An optional app lock. Require it on launch and after 5 minutes in the background. Fall back to the device passcode. |
| **Camera and photo uploads** | §6.10 |
| **Tap to call / email / map** | Every phone number, email address and address. |
| **Deep links** | `aagaclaims://claim/{id}`, `aagaclaims://lead/{id}`, `aagaclaims://case/{id}`. Also handle portal universal links `https://portal.accurateadjustmentsga.com/s/detail/{id}` and `/s/my-case-detail?recordId={id}`. |
| **Offline cache** | Read-only cache of lists, details and updates (SmartStore or SwiftData). Never cache file contents beyond what Quick Look needs. |
| **App badge** | The app icon badge shows the unread update count. |

---

## 9. Brand and visual design
- **Logo:** `https://portal.accurateadjustmentsga.com/cms/delivery/media/MC7US4WNGSA5GEPDGQS3GZYNFDTQ`. The designer will supply the app icon and vector logo.
- **Theme (2026-10-12): Salesforce blue and white, premium and modern.** Every text colour passes WCAG AA (4.5:1) on every background it's used on.
  - Brand blue (text, links, icons, buttons) `#0B5CAB`; Salesforce bright blue `#0176D3` for gradients and accents; navy `#014486`
  - Text `#181818`; secondary text `#54606E`; border `#E1E6EE`
  - Background `#F4F7FB`; surface `#FFFFFF`; tinted surfaces `#EEF4FF` / `#DCEAFE`
  - Success `#22683E`; warning `#8C4B02`
  - Dark mode: blues `#78B0FD` / `#59A7FF` / `#AACBFF`, text `#F3F3F3` / `#A5AEBB`, surfaces `#161B24` / `#0B0F17` / `#152238`
  - Cards: white, 16 pt continuous corners, soft shadow (light mode). Buttons: capsules. Hero and splash: `#0176D3` → `#014486` gradient with white text.
- **Typography:** SF Pro, the system font. The portal uses Google Sans, so don't bundle it.
- **Tone:** warm, reassuring and plain-English. Customers are often stressed after a loss. Use "your claim", "your account manager" and "we'll follow up". Avoid insurance jargon in UI copy. Field names like RCV can stay, with a help (ⓘ) tip: "Replacement Cost Value: the full cost to repair or replace damaged property."
- **Design source of truth:** Figma files from the designer. Where they differ from this spec, the Figma layout wins and the data and behaviour in this spec win.

---

## 10. Security and privacy
- Tokens are stored only through the SDK (in the Keychain). Never log tokens, record IDs together with personal data, or HTML bodies.
- Use App Transport Security defaults with no exceptions. Certificate pinning is optional and not required for v1.
- Mask the app content in the app switcher snapshot when Face ID lock is on.
- No analytics SDKs in v1. If crash reporting is added, scrub personal data from it.
- App Privacy (App Store) declarations:
  - contact info (name, email, phone)
  - user content (photos, documents, messages)
  - identifiers (user ID)
  - none of it used for tracking

---

## 11. Out of scope for v1
- Portal adjuster or staff tools (claim status edits, task editing, commissions). Creating a task and seeing your agenda on Home are in scope (§5.5, §6.2).
- Payment image upload (an internal staff quick action)
- Editing claim or lead fields after submission
- Android and iPad-optimised layouts
- In-app chat other than support case replies

---

## 12. Milestones and acceptance criteria

1. **Foundation:** project, SDK login against the portal domain, mock `PortalAPI` with fixtures, tab shell, design tokens.
   *Done when* a user can sign in and out on a device and every tab shows mock data.
2. **Claims:** list, filters, detail (all sections), team card, Add Comment, Request Assistance.
   *Done when* every field in §5.1 is shown somewhere and lifecycle percentages match §6.5.
3. **Leads and Submit a Lead:** list, detail, agreement milestones, and the 5-section form with validation and the upload step.
4. **Support:** cases list, filters, thread, reply, Request Assistance.
5. **Home and notifications:** dashboard tiles, status overview, activity feed, read/unread, badge count.
6. **Native features:** push and deep links, Face ID, camera and file upload, offline cache.
7. **Hardening:** accessibility pass, error and offline states on every screen, unit and UI tests passing, TestFlight build.

**Overall acceptance:** a test homeowner and a test referral partner can each complete every task the web portal supports (§1) on an iPhone, using live Salesforce data, without opening the website.
