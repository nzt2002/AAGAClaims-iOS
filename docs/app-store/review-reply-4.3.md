# Reply to App Review: Guidelines 4.3 and 4.2.6 (2.0.0 rejection, 2026-11-13)

Paste the text under "Reply" into the Resolution Center message for the rejection. Don't resubmit.
Fill in every [bracketed] item first, and fix the listing items under "Before sending".

## Before sending
- Remove the unused app record "AAGA Claims" (bundle ID `com.62Z8PRAHTS.com.rileytestut.AltStore`,
  version 1.0, never submitted, no builds): App Store Connect → that app → App Information → Remove App.
  The reply below says ProClaimer is the only app on the account.
- Done 2026-11-13 through the API: Support URL and Marketing URL are https://getproclaimer.com/ (the
  footer has support@getproclaimer.com), and the copyright is "2026 Lyons Business Solutions, LLC".
- The Apple account is an Individual membership (seller "Simon Lyons"). Converting it to an Organization
  membership for Lyons Business Solutions, LLC is the strongest fix for 4.2.6 and guideline 5.1.1(ix). If
  you start that before sending, keep the last sentence of answer 9; otherwise delete it.

## Reply

Hello,

Thank you for the review. We believe ProClaimer meets guidelines 4.3(a), 4.3(b) and 4.2.6, and we have answered each question below.

1. What the app does and the problem it solves

ProClaimer is the mobile app for the ProClaimer claims platform, which public adjusting firms use to manage property insurance claims for the homeowners and businesses they represent. A public adjuster is hired by the policyholder (not the insurer) after a storm, fire or water loss to document the damage and negotiate the settlement. These claims often run for months, and the policyholder usually has no way to see progress except by phoning the firm.

The app gives each party a live view of the same claim record:
- Policyholders sign in to see their claim's current stage (Preparation, Inspection, Negotiations, Restoration, Litigation, Settlement, Closed), read updates their adjuster publishes, see each insurance payment recorded on the claim and the total collected, upload damage photos and documents from the camera or Files, ask questions in a support thread, and sign their adjuster agreement.
- Referral partners (roofers, contractors and agents who refer homeowners to the firm) submit new leads and follow each lead's status and agreement progress.
- Firm staff manage their claims and leads from the field: tasks and events, payments, the internal team feed, replies to policyholder questions, and calls to policyholders from the firm's business line with an in-app call screen.

Push notifications tell each user when something changes on their own claim or lead. Data comes live from the firm's account on the ProClaimer platform through authenticated APIs; nothing is static or bundled content.

2. Intended users

- Policyholders: homeowners and small-business owners with an open property insurance claim who have hired a public adjusting firm that uses ProClaimer. Many are dealing with a damaged home and want a simple, reassuring way to see where their claim stands.
- Referral partners: contractors, roofers and insurance agents who send claims to the firm and need to know what happened to each referral.
- Public adjusting firm staff: adjusters, desk adjusters and account managers at small firms (roughly 1–50 people) who work in the field.

Accounts are created by the firm for its own clients, partners and staff. There is no public sign-up. The demo account in App Review Information shows the policyholder experience with sample data.

3. The need or gap it addresses

Insurance carriers' apps serve the insurer's side of a claim. Contractor job-management apps track construction jobs, not the insurance claim lifecycle, settlement payments or a public adjuster's agreement. Public adjusting firms have generally kept clients informed by phone, text and email, so a policyholder can't check progress or payments without calling. ProClaimer connects the policyholder, the referral partner and the adjuster to one claim record: the firm publishes an update once, and every party sees it and is notified. We are not aware of another app that does this for public adjusters and their clients.

4. Beta testing

The app has been in TestFlight since 12 October 2026, with [number] builds, tested by the staff of Accurate Adjustments GA (our first customer firm) and, since 6 November, an external testing group of [describe: e.g. the firm's referral partners and policyholders]. Changes made because of beta feedback include:
- Sign-in could stay stuck on the launch screen on some phones; fixed in build 21.
- After turning on Face ID, the app could stay behind its privacy screen until it was reopened; fixed in builds 23–24.
- A crash at launch on devices with a pending crash report; fixed in build 27.
- Staff asked that the call screen's buttons act on the call directly (3.6.1), that one tap on End close both the app's call screen and the iPhone call screen (3.9.1), and that answered business-line calls have audio (3.5.1).
- Calls that fail to connect now say why instead of hanging up silently.
- [Add one or two pieces of policyholder or partner feedback, e.g. a layout or wording change they asked for.]

5. Standalone product or suite

ProClaimer is a standalone product and the only app on our developer account. It is the single app for every firm on the ProClaimer platform. We will not publish separate copies for individual firms: each firm's clients and staff use this same app and sign in to their firm's account.

6. Could it be delivered inside another app on our account?

No. There is no other app on our account.

7. Code shared with other apps on our account

None. There are no other apps on our account.

8. Code, SDK or content shared with third-party apps

The app is written in Swift and SwiftUI by our team. It isn't built from a template or an app generation service. It uses two standard third-party frameworks: the Salesforce Mobile SDK, which handles secure sign-in and token storage because the ProClaimer platform's back end runs on Salesforce, and Google reCAPTCHA Enterprise for in-app password reset. All the screens and features described above are our own code.

9. Was it created for a client who provided the content, concept or branding?

No. ProClaimer is my own product, owned by my company, Lyons Business Solutions, LLC. The concept, the ProClaimer name and branding, and the app's code are mine, and I am the provider of the ProClaimer service the app connects to. I developed it working closely with Accurate Adjustments GA, a public adjusting firm in Georgia, which is the first firm using ProClaimer and whose staff tested the app. Accurate Adjustments GA did not supply the app's concept, branding or content: the app is branded ProClaimer throughout, and each firm's claim records are that firm's own data in the ProClaimer service, in the same way a business's data lives in any software-as-a-service app. ProClaimer is designed to serve other firms through this same app.

The app is submitted under my developer account because I am its provider. The membership is currently an individual one in my name, as the owner of Lyons Business Solutions, LLC; I have started converting it to an organization membership for the LLC.

Thank you,
Simon Lyons, Owner, Lyons Business Solutions, LLC
support@getproclaimer.com · [Phone]
