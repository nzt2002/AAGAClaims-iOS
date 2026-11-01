# App Privacy answers (App Store Connect → App Privacy)

**Do you or your third-party partners collect data from this app?** Yes.
**Tracking:** No. The app doesn't track users across other companies' apps or websites, and has no ads or analytics SDKs.
**Third party:** Google reCAPTCHA Enterprise (in-app password reset) collects the types marked *reCAPTCHA* below,
for fraud prevention (App Functionality), per its privacy manifest; none of it is used for tracking.

For every type below: **Linked to the user's identity: Yes** · **Used for tracking: No** · **Purpose: App Functionality** (Crash Data and Other Diagnostic Data: also *Analytics*, to fix crashes).

| Category | Data type | Why |
|---|---|---|
| Contact Info | Name | Portal account and claim records |
| Contact Info | Email Address | Sign-in, notifications, support |
| Contact Info | Phone Number | Claim and lead contact details |
| Contact Info | Physical Address | Loss addresses on claims and leads |
| Financial Info | Other Financial Info | Insurance payments recorded on claims |
| User Content | Photos or Videos | Damage photos the user uploads |
| User Content | Customer Support | Support cases and replies |
| User Content | Other User Content | Claim updates, comments, posts, files |
| Identifiers | User ID | Salesforce user ID for the session |
| Identifiers | Device ID | Push notification token (only if notifications are allowed); *reCAPTCHA* device signals |
| Usage Data | Product Interaction | *reCAPTCHA* only (fraud prevention) |
| Diagnostics | Crash Data | MetricKit crash reports (Mobile App Logs); *reCAPTCHA* |
| Diagnostics | Performance Data | *reCAPTCHA* only (fraud prevention) |
| Diagnostics | Other Diagnostic Data | App hang reports |

**Not collected:**
- Location: photos are sent without their GPS location.
- Health, contacts, browsing and search history, purchases.
- Sensitive info, audio, and gameplay content.

Account deletion: available in the app (tap your initials at the top right → Delete Account).
