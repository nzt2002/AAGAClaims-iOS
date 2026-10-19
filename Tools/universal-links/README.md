# app.accurateadjustmentsga.com: universal links

Salesforce serves its own `apple-app-site-association` on portal.accurateadjustmentsga.com and lists
only Salesforce's apps, and the main website (Wix) can't serve one. So links that should open the app
use **app.accurateadjustmentsga.com**, with the portal's paths:

- `https://app.accurateadjustmentsga.com/s/detail/{claim or lead id}`
- `https://app.accurateadjustmentsga.com/s/my-case-detail?recordId={case id}`

With the app installed, iOS opens the record in the app. Without it, this site redirects to the
same page on the portal.

## Publish (Cloudflare Pages, free)

1. Cloudflare dashboard → Workers & Pages → Create → Pages → **Upload assets**. Upload this folder
   (`.well-known/`, `_headers`, `_redirects`). Name the project `aaga-app-links`.
2. In the project, open **Custom domains** and add `app.accurateadjustmentsga.com`. Cloudflare creates the DNS record.
3. Check it: `curl -i https://app.accurateadjustmentsga.com/.well-known/apple-app-site-association`
   should return 200 with `Content-Type: application/json` and no redirect.

Then use app.accurateadjustmentsga.com instead of portal.accurateadjustmentsga.com in the email
templates whose links should open the app.
