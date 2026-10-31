# App Store submission kit: ProClaimer 1.1.0

Everything to enter in App Store Connect for the first release. Paste-ready text is in
`listing.md`, the privacy questionnaire answers are in `app-privacy.md`, and the notes for Apple's
reviewer are in `review-notes.md`. Screenshots are in `~/Desktop/ProClaimer App Store Screenshots`
(iPhone 6.9-inch 1320×2868 and iPad 13-inch 2064×2752, seven each, taken 2026-10-31 from version 1.1.0's
demo data with the demo banner hidden: Home, Claims, a claim, its progress, its payments, a lead, Search).

## Checklist
- [x] Privacy policy: live at `https://proclaimer-app.pages.dev/privacy/` (Cloudflare Pages project
      `proclaimer-app`, 2026-10-31). Enter that as the Privacy Policy URL. When
      `app.accurateadjustmentsga.com` points at the project (CNAME `app` → `proclaimer-app.pages.dev` in Wix),
      the same page is also at `https://app.accurateadjustmentsga.com/privacy/`.
- [ ] App information: name, subtitle, category, age rating and copyright (`listing.md`).
- [ ] Version 1.1.0: description, keywords, promotional text, support URL and screenshots.
- [ ] App Privacy: answer the questionnaire (`app-privacy.md`).
- [ ] App Review information: sign-in details and notes (`review-notes.md`). Enter the demo
      account's password in App Store Connect only; never put it in documents.
- [ ] Build: choose the latest 1.1.0 build once it has finished processing.
- [ ] Export compliance: already answered in the build (no non-exempt encryption).
- [ ] Pricing and availability: free; United States (or your choice).
- [x] Push notifications: APNs key added to the AAGA Claims iOS External Client App (2026-10-31).
- [ ] Release: "Manually release this version" is safest for the first release.
