# Legal research for the Izzy Clipz legal documents

**Researched:** November 5, 2026, and revised the same day after two independent reviews (see "Changes after review" at the end)\
**For:** drafting `privacy.md`, `terms.md`, `cancellation-policy.md` and `accessibility.md` (and `OWNER-CHECKLIST.md`)\
**Status:** research notes. This is not legal advice.

> These notes cover which laws and platform rules apply to Izzy Clipz Barbershop's website, its installable web apps and its two iPhone apps, and what the documents (and the product) must say or do to meet them. The documents built from these notes are **drafts for the owner**. **Have a California attorney review the documents, the fee settings and the retention plan before the live version goes public.**

## How to read this file

Each section has three parts:

- **The rule:** what it says, with its source and date.
- **Does it apply?** Yes or no for this shop, and why.
- **What to do:** what the documents must say, and any change the product needs.

Labels used throughout:

- **Applies.**
- **Probably doesn't apply**, with the reason.
- **Good practice:** not required, but cheap and protective.
- **Recent:** changed in 2025–2026.
- **Coming:** takes effect soon.

**Facts about the shop** come from the code and the spec, not assumptions. The code was read on branches `v5/int` and `v5/webapp-business` as of November 5, 2026. Some facts are unknown: the legal entity name, the shop's revenue, its number of employees and its email address. Where one matters, this file says so instead of guessing.

**How sources were checked:**

- Official sources were used wherever they could be read: California Attorney General, California Privacy Protection Agency (CPPA), FTC, DOJ, W3C, Apple, Stripe, Google and Yelp.
- The California Legislature's own site (leginfo) blocked automated reading. Statute text therefore comes from FindLaw's copies, marked "current as of January 1, 2026". Bill status comes from CalMatters Digital Democracy, cross-checked against law-firm alerts.
- Google's Maps Platform Terms were read on November 5, 2026 (last modified August 26, 2026); the clause the Terms of Service must carry is quoted in §12.
- While the documents were drafted, these points were checked again against their sources: Apple's App Review Guidelines (last updated October 16, 2026), Yelp's display requirements, the small claims limits, the gift card cash-out threshold, the FTC's review-rule warning letters, DOJ's Title II extension, WCAG 2.2 as an ISO standard, and SB 690.
- After the reviews, these were read on November 5, 2026: Yelp's API Terms of Use (last updated September 22, 2026); Stripe's Privacy Policy (last updated April 28, 2026); Vercel's Privacy Notice (June 1, 2026) and Data Processing Addendum (last updated March 17, 2026); Stripe's Terminal iOS setup page and its API reference for Checkout Sessions and for updating a Charge; Code of Civil Procedure §395 and Civil Code §§1723 and 1747.08 (FindLaw); Apple's Standard EULA; 28 C.F.R. §36.303 (Cornell LII); §3.2.3(e) of the Google Maps Platform Terms; and the shop's older website.

---

## At a glance

| # | Rule | Applies? | What the documents / product must do | Recent / coming |
|---|---|---|---|---|
| 1 | **CalOPPA** (privacy policy law) | **Applies** (site + apps collect name, phone, email) | Privacy Policy with the required elements, including every category of third party that receives PII (service providers and the developer who runs the systems) and whether other parties can collect data across sites (Stripe's card page does); a conspicuous "Privacy" link on the homepage and inside each app; Do Not Track statement; effective date; how changes are announced | — |
| 2 | **CCPA / CPRA** | **Probably doesn't apply** (revenue threshold $26,625,000; shop doesn't sell or share data) | Don't rely on it; offer access/correction/deletion anyway; say "we don't sell or share"; list retention periods | Recent: new regulations in force Jan 1, 2026. Coming: CPI threshold adjustment Jan 2027 |
| 3 | **Do Not Track / Global Privacy Control** | DNT statement **applies** (CalOPPA); honoring GPC is **good practice** | Say how DNT is handled (no cross-site tracking at all); say GPC is honored; optional `/.well-known/gpc.json` | Recent: Firefox dropped its DNT setting (2025). Coming: browsers must offer an opt-out signal from Jan 1, 2027 (AB 566) |
| 4 | **COPPA** (amended rule) | **Probably doesn't apply** (general-audience barbershop; no knowing collection from under-13s) | "Not for children under 13; a parent or guardian books for a child"; delete a child's data if found | Recent: compliance date Apr 22, 2026 |
| 5 | **California Digital Age Assurance Act** (AB 1043, as amended by AB 1856) | **Applies to both iPhone apps** from Jan 1, 2027 | **Must do:** ask iOS for the user's age range when the app is downloaded and launched (Apple's Declared Age Range API); decide what happens for under-13s; disclose it | **Coming: Jan 1, 2027** (apps downloaded earlier: by Jul 1, 2027) |
| 6 | **State app-store age laws** (Texas, Utah, Louisiana) | **May apply** to users in those states | Follow Apple's age-assurance guidance for those states | Recent: Texas enforced for new Texas accounts since Jun 4, 2026 (per Apple) |
| 7 | **Data breach law** (Civ. Code §1798.82) + reasonable security (§1798.81.5) + disposal (§1798.81) | **Applies** | Security section; breach-notice commitment "as California law requires"; real deletion | Recent: **30-day notice deadline** since Jan 1, 2026 (SB 446) |
| 8 | **CAN-SPAM** | **Probably doesn't apply today** (no marketing email; the server sends no email) | Say "no marketing emails or texts"; if that changes, get consent and honor opt-outs | — |
| 9 | **TCPA** | **Probably doesn't apply today** (no automated texts or calls in the code) | Phone number used only about the appointment; consent before any automated reminders | Recent: FCC narrowed the "revoke-all" rule, effective Nov 25, 2026; *McLaughlin* (Jun 2025) |
| 10 | **Honest Pricing Law** (SB 478, Civ. Code §1770(a)(29)) | **Applies** to prices shown | Prices include every mandatory charge; "From" prices must be real; no-show fee disclosed clearly (it's contingent, so it isn't part of the price) | In force since Jul 1, 2024 |
| 11 | **Gender pricing law for barbers** (Civ. Code §51.6) | **Applies** (in the shop) | Posted price list and sign in the shop; no price differences by gender (names already neutral) | — |
| 12 | **Liquidated damages** (Civ. Code §1671(d)) | **Applies** to the no-show / late-cancel fee | Fee must be a reasonable estimate of the shop's loss; **cap at the service price** (flat mode can exceed it today); a grace period for bookings made after the cutoff has passed; a no-show fee only after the appointment's end time; document how the amount was chosen | — |
| 13 | **Online agreement** (*Berman*, *Chabolla* line of cases) | **Applies** to how the fee agreement is shown | Keep the full policy text right above "Book appointment"; add links to the full policy and Terms; consider a checkbox | Recent: *Chabolla v. ClassPass* (9th Cir., Feb 2025) |
| 14 | **Stripe** rules for saved cards and public policies | **Applies** | Terms covering when the card may be charged, the amount rule and the event that triggers it; public refund/cancellation/contact info; clear statement descriptor; yearly PCI self-attestation | — |
| 15 | **Card-network stored-credential rules** (via Stripe) | **Applies** | Agreement shows last 4 digits, how it's used, the amount rule and its duration; notify changes; keep the consent record | — |
| 16 | **ADA Title III + Unruh Act** (accessibility) | **Applies** (physical shop; site and apps serve it) | Aim for WCAG 2.2 AA; accessibility statement; other ways to book, including ways to reach the shop without a voice call (relay calls, text, email); no overclaiming, on the site or on the Visit page | Recent: DOJ extended its Title II (government) deadlines Apr 2026; WCAG 2.2 became ISO/IEC 40500:2025 |
| 17 | **Apple App Store rules** | **Applies** | Privacy policy link in each app and in App Store Connect; accurate App Privacy answers; privacy manifests (present); account deletion not required; age rating answers; Tap to Pay rules | Recent: new age-rating questions (Jan 31, 2026); age-assurance APIs (2026) |
| 18 | **Google Maps Platform / Places** terms | **Applies** when live Google reviews show | "Google Maps" attribution, author credit, link to each review, ordering notice (all already done); Terms and Privacy mention Google's terms and privacy policy | Recent: "Google Maps" attribution wording |
| 19 | **Yelp API Terms of Use + display requirements** | **Applies** if Yelp reviews are shown | The API is described as for **non-commercial uses** (no promotional value to the user) and bars Yelp ratings next to other reviews, so **keep Yelp reviews off** (link only) unless Yelp gives written consent; the documents assume they're off | Recent: API terms updated Sep 22, 2026 |
| 20 | **FTC Consumer Review Rule; Consumer Review Fairness Act; Civ. Code §1670.8** | **Applies** | No clauses limiting reviews; no suppressing negative reviews; no incentives for positive ones | Recent: FTC warning letters Dec 2025 |
| 21 | **Gift cards** (Civ. Code §1749.5) | **Applies if sold** (checkout supports "gift card" items) | No expiry, no fees, cash back on request under **$15** | Recent: $15 threshold since Apr 1, 2026 (SB 22) |
| 22 | **CIPA** (wiretap/tracker lawsuits) | **Low risk** (no trackers) | Keep it that way; get advice before adding analytics or pixels | Recent: SB 690 signed Sep 30, 2026 (narrows one claim) |
| 23 | **Shine the Light** (Civ. Code §1798.83) | **Probably doesn't apply** (exempt under 20 employees; no marketing sharing) | Optional line: "we don't share your information with others for their marketing" | — |
| 24 | **Consumer contract limits** (Civ. Code §1668, CLRA, *City of Santa Barbara*, *McGill*) | **Applies** to the Terms | Keep "as is" disclaimers to the software; no waiver of liability for injuries from services; no arbitration; small claims allowed | Small-claims limits unchanged ($12,500 / $6,250) |
| 25 | **Right of publicity** (Civ. Code §3344) | **Applies** to photos of people (gallery) and barbers' names and bios | Written consent from people shown (a parent for a minor); **the gallery photos are already live on the public demo**, so take them down now | — |
| 26 | **Song-Beverly Credit Card Act** (Civ. Code §1747.08) | **Applies** to card payments in the shop | Don't ask for an email, ZIP code or phone number as part of a card payment; offer an email receipt only after the payment is approved, and don't keep the address | — |
| 27 | **Consumer venue** (Code Civ. Proc. §395(b)–(c)) | **Applies** to the Terms' courts clause | Keep the client's own county available; a clause waiving it is void | — |

---

## What the code shows (facts that decide what applies)

These were checked in the code on November 5, 2026. The data inventory (`data-inventory.md`) goes into more detail. Paths are relative to the repository root.

- **No email or text messages are sent by the system.**
  - The server's dependencies (`server/package.json`) include no email or SMS service, and `server/src` has no sending code.
  - Two related exceptions:
    - In-person card payments can pass a `receipt_email` to Stripe, and Stripe then sends its own receipt (`server/src/payments.ts`).
    - Fee charges deliberately send no receipt (`server/src/noshowfee.ts`).
  - The Business app has a "text this client" link (`sms:` in `IzzyClipzBusiness/Features/Schedule/AppointmentDetailView.swift`). It opens the barber's own Messages app, so any text is written and sent manually.
- **No analytics, trackers or third-party fonts on the website.** No analytics or pixel code exists in `server/web/src`. Fonts are the device's own system fonts first, then Inter, which is self-hosted (`server/web/src/styles/tokens.css`, `server/web/src/main.tsx`). Outside hosts are Stripe Checkout (`checkout.stripe.com`) plus links out to Google Maps, Google's privacy policy, Yelp, Instagram and Apple Maps, and reviewers' photos from Google's and Yelp's image servers.
- **Reviews** (`server/src/reviews.ts`):
  - Google:
    - Fetched live and never stored.
    - The only fields requested are `rating`, `userRatingCount`, `reviews` and `googleMapsUri`.
    - Up to 5 reviews are shown, in Google's order.
  - Yelp (only when the server has a Yelp key; see §12.2):
    - Cached for at most 24 hours: purged daily and dropped on read after 24 hours.
    - Up to 7 reviews are shown, in Yelp's default order.
  - **No filtering by star rating.**
- **What a booking holds** (`server/migrations/001_init.sql`, `server/src/validation.ts`):
  - Name (required).
  - US mobile number.
  - Email: optional on the website and in the shop's tools. The client iPhone app doesn't ask for it.
  - A note of up to 300 characters.
  - Service, barber and time.
- **No-show protection** (`server/src/noshow.ts`, `server/src/feecase.ts`, `server/src/cards.ts`, `server/migrations/004_no_show_protection.sql`):
  - Off until the owner turns it on.
  - Percent mode: 1–100% of the service price, default **100%**.
  - Flat mode: $0.50–$500, default $20. **Flat mode charges the flat amount even when the service costs less.**
  - Late cancellations can be turned off by the owner (`lateCancelEnabled`); then only no-shows can be charged.
  - Late-cancellation window: 30 minutes to 48 hours, default **1 hour**.
  - The client saves a card on Stripe's own Checkout page in setup mode. Nothing is charged then.
  - The exact policy text is shown on Stripe's page (`custom_text.submit`) and stored with the booking, together with the consent time (`no_show_policy`, `no_show_consent_at`).
  - The server keeps only the card brand, last 4 digits, expiry and Stripe IDs.
  - Fees are charged later, off-session, only when the owner acts, at most once per appointment, and with no time limit after the visit today.
  - A booking with a card on file can be marked a no-show, and charged, as soon as its start time has passed (`patchOwnerAppointment` in `server/src/appointments.ts`, `chargeCase` in `server/src/noshowfee.ts`), although the documents say a client who arrives before the end isn't a no-show. A completed appointment without a sale can also be changed to a no-show.
  - A client's cancellation counts as late whenever it's inside the window, even one made a minute after booking a time that was already inside it (`cancelledLate` in `server/src/feecase.ts` doesn't look at `created_at`). Bookings can start 30 minutes ahead (`leadTimeMinutes` in `server/data/catalog.json`), and the window can be up to 48 hours. The booking screens warn about it ("This time is less than 1 hour away, so cancelling it may be charged $40").
- **Agreement screen:**
  - App: "By booking, you agree to this:" plus the full policy text (`IzzyClipz/Features/Booking/NoShowViews.swift`).
  - Website: "What you agree to by booking" (`server/web/src/booking/ReviewStep.tsx`).
  - Both sit above a button labelled **"Book appointment"**. On the website, the line "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy." sits right above the button, with both linked (the iPhone app gets the same line).
- **Saved cards:**
  - The app's "Remember me on this iPhone" option **starts ticked** (`IzzyClipz/App/AppRouter.swift`). It keeps the card for later bookings.
  - The website's equivalent starts unticked.
  - Nothing in the server ever removes a saved card or deletes Stripe's customer record.
  - Without "Remember me", the website and the app forget the card's key right after booking (`server/web/src/booking/ReviewStep.tsx`, `keepOrForgetCard` in `IzzyClipz/Features/Booking/BookingModels.swift`), so the client has nothing left to remove that card with.
- **Abuse protection:**
  - Rate-limit keys use a SHA-256 of the client's IP address, cut to 32 characters, with no secret added (`server/src/ratelimit.ts`).
  - That is a scrambled form of the IP, not an anonymous one: the IPv4 space is small enough to reverse it by trying every address.
  - These rows are deleted daily.
- **Daily cron** (`server/vercel.json`, schedule `17 11 * * *`, `server/src/cron.ts`):
  - Deletes old rate-limit rows, API usage counters and the Yelp cache.
  - **Nothing deletes old appointments, sales names or saved cards.** That is the retention gap.
- **Client iPhone app:**
  - No Stripe SDK: Stripe's page opens in a system web sheet (`ASWebAuthenticationSession`).
  - **Local notifications only**: there is no push registration.
  - Calendar through EventKitUI's add-event sheet.
  - MapKit; UserDefaults and Keychain.
  - No location, camera or photo permissions.
  - The privacy manifest declares Name, Phone Number, Payment Info and Other User Content, with no tracking, and UserDefaults reason `CA92.1`.
  - Notification permission is asked right after the first booking, because the appointment's reminders start on (`appointments.add(confirmation, remind: true)` in `BookingModels.swift`; `performSync` in `IzzyClipz/Stores/AppointmentStore.swift`).
  - "Forget my details" clears only the remembered name and number and the card. Stored appointments keep the client's name, number and note until 30 days after each one, and "Remove from this list" works only for past or cancelled ones. Keychain items (appointment keys, the card key, unconfirmed bookings with their number) can stay after the app is deleted.
  - The Visit tab's "Website" row, its Share link and every Add to Calendar event use the shop's older website, https://www.izzyclipzbarbershop.net. It runs on Squarespace (it sets Squarespace's `crumb` cookie and loads Squarespace's scripts), and its booking button goes to the shop's old booking page on Squire (checked November 5, 2026).
- **Business iPhone app:**
  - Stripe Terminal SDK 6.0.0 and the Tap to Pay entitlement.
  - Permission strings for Bluetooth (required by Stripe's SDK), camera, photo library and location while in use. The location string says Stripe checks location during each card payment.
  - Its privacy manifest declares **no collected data types**. That may be incomplete (see §11).
  - The receipt email is typed on the take-payment screen before the card is tapped (`IzzyClipzBusiness/Features/Payments/TakePaymentView.swift`), sent to Stripe with the payment and kept in `payments.receipt_email` (`server/src/payments.ts`). See §9.3.
  - Without a note, the payment's description sent to Stripe is "<service> with <barber> for <client's name>" (`IzzyClipzBusiness/Payments/CheckoutModel.swift`).
- **Products and gift cards:**
  - Products are a showcase only: "Available at the shop", with no online sales.
  - The shop's checkout can ring up "custom items like a gift card" in person, and the catalog lists "Credit card" and "Gift card" as payment methods.
- **Gallery:** the client app and the website show six photos of the shop's work. They show clients' faces, and at least one appears to be a minor. They came from the shop's older website (`README.md`, "Where the data came from"), and they're already live on the public demo: its script bundle loads all six (checked November 5, 2026).
- **Hosting:** Vercel Functions in region `pdx1`, with a Neon Postgres database.
- **Who else can reach the data:** the developer who deploys the server sets its secrets, including the owner key, the database address and the Stripe key (`server/README.md`). With `STRIPE_CONNECT=on`, the Stripe key is the developer's own Connect platform key, and every Stripe call for the shop is made on the shop's connected account with it. The owner checklist has the developer run the privacy tools against the live database. So the developer is a recipient of clients' information that the Privacy Policy must name (§1).

---

## 1. California Online Privacy Protection Act (CalOPPA)

**The rule.** Business and Professions Code §§22575–22579 ([FindLaw §22575](https://codes.findlaw.com/ca/business-and-professions-code/bpc-sect-22575/)) applies to operators of commercial websites or "online services" that collect personally identifiable information (PII) from California consumers. They must **conspicuously post** a privacy policy that:

1. identifies the categories of PII collected and the categories of third parties it may be shared with;
2. describes the process for reviewing and requesting changes to one's PII, if the operator offers one;
3. describes how users are told about material changes to the policy;
4. states its effective date;
5. discloses how the operator responds to browser "Do Not Track" signals or similar mechanisms, if it collects PII about a person's online activities over time and across other sites; and
6. discloses whether other parties may collect such information when people use the site or service.

Other points:

- "PII" includes a first and last name, a physical address, an email address, a phone number and any identifier that allows contacting a person. The AG notes it can also include passively collected data such as device identifiers ([AG guide, May 2014](https://oag.ca.gov/sites/all/files/agweb/pdfs/cybersecurity/making_your_privacy_practices_public.pdf)).
- The AG treats a mobile app as an "online service".
- An operator is in violation if it fails to post a policy within 30 days of being notified, or if it fails to follow its own policy knowingly and willfully, or negligently and materially.

**The AG's recommendations** ([Making Your Privacy Practices Public, May 2014](https://oag.ca.gov/sites/all/files/agweb/pdfs/cybersecurity/making_your_privacy_practices_public.pdf)). These go beyond the statute, but are widely followed:

- **Language and format:** plain language, no jargon, a readable or "layered" format, and printable.
- **Website:** a homepage link containing the word **"privacy"**, made conspicuous (larger type, contrasting color), plus a privacy link on every page where personal information is collected.
- **App:** link to the policy on the app's store page *and* inside the app (settings, About, Information).
- **Do Not Track:** a clearly labelled section, for example "How We Respond to Do Not Track Signals". Describe the response rather than only linking to a program, and say whether other parties track visitors.
- **Contents:**
  - Uses beyond what the service needs.
  - Types of companies data is shared with, with links to their privacy policies where possible.
  - **A retention period for each category.**
  - Choices, and how to exercise them.
  - How access and correction work, and how identity is verified.
  - A general description of security.
  - A contact for privacy questions.
- **Changes:** don't rely only on changing the page to announce material changes.

**Does it apply? Applies.** The website, both web apps and both iPhone apps are commercial and collect names, phone numbers and emails. CalOPPA has no size threshold.

The public demo keeps bookings in the browser only, so arguably nothing is "maintained" by the operator there. Post the policy anyway, and say how the demo differs.

**What to do.**

- **Privacy Policy:** include all six statutory elements and follow the AG recommendations above. Name the third parties (Stripe, Vercel, Neon, Google and Apple, plus Yelp if its reviews are ever shown) and link to their privacy policies.
  - **The developer counts too.** The developer who runs the systems can reach clients' information (see "What the code shows"), so the policy names the developer as a category of recipient and limits the use to running the systems, fixing problems and carrying out requests. The owner checklist backs that with a written agreement.
  - **Element 6 (other parties):** Stripe's card page collects "the devices and browsers you use across our Sites and third-party websites" and activity indicators "to help us detect fraud" ([Stripe Privacy Policy](https://stripe.com/privacy), last updated April 28, 2026, §2(a)), and uses End Customers' data "for Stripe's own purposes such as enhancing security" (§1.2(b)). Stripe has announced an update to that policy for November 20, 2026, so check it again before go-live. Google receives visitors' IP addresses when reviewers' photos load. The policy says so, instead of saying that no other company can collect such information.
- **Website:** add a footer "Privacy" link on every page, with the Terms, Accessibility and Cancellation Policy links. Keep it visible on the homepage and the booking steps.
- **Apps:** add a "Privacy Policy" link inside both iPhone apps, plus the policy URL on the App Store pages. Apple requires the in-app link anyway (§11).
- **Changes:** announce material changes with a notice in the apps and on the site, not just by updating the page. Apply them only going forward.

---

## 2. Do Not Track and Global Privacy Control (GPC)

**Do Not Track (DNT).** CalOPPA requires the disclosure described in §1. The AG prefers a plain description of what the site does with the signal.

- **Recent:** Mozilla removed Firefox's DNT setting in version 135 (early 2025) because "many sites do not respect" it. It now points users to GPC instead ([PCWorld, Dec 2024](https://www.pcworld.com/article/2556498/firefoxs-do-not-track-feature-is-going-away-because-websites-ignore-it.html); [Engadget](https://www.engadget.com/cybersecurity/firefox-will-no-longer-support-do-not-track-feature-141543907.html)).

**Global Privacy Control.** GPC is a browser signal asking sites not to sell or share the person's data ([globalprivacycontrol.org](https://globalprivacycontrol.org/)). Per the W3C specification ([w3c.github.io/gpc](https://w3c.github.io/gpc/)):

- Browsers send the `Sec-GPC: 1` header and expose `navigator.globalPrivacyControl`.
- A site may publish `/.well-known/gpc.json` containing `{"gpc": true, "lastUpdate": "YYYY-MM-DD"}` to declare that it honors GPC.

What the law requires around GPC:

- CCPA regulations require *covered* businesses to treat GPC as a request to opt out of sale and sharing.
- **Recent:** from January 1, 2026, they must also **show** that the signal was honored, for example an "Opt-Out Request Honored" message ([Covington, Nov 5, 2025](https://www.globalpolicywatch.com/2025/11/california-finalizes-updates-to-existing-ccpa-regulations/); [Nelson Mullins, Jan 13, 2026](https://www.nelsonmullins.com/insights/alerts/fcc-download/all/show-me-that-you-ve-opted-me-out-new-ccpa-rules-require-businesses-to-prove-compliance)).
- **Coming:** AB 566, the California Opt Me Out Act, was signed October 8, 2025. From **January 1, 2027**, browsers must offer a setting that sends an opt-out preference signal ([Hunton](https://www.hunton.com/privacy-and-information-security-law/california-enacts-first-in-nation-law-requiring-web-browser-opt-out-preference-signal); [Orrick, Oct 10, 2025](https://infobytes.orrick.com/2025-10-10/california-enacts-browser-opt-out-signal-legislation)). More visitors will send GPC.

**Does it apply?**

- **DNT statement: applies** (CalOPPA).
- **Honoring GPC: good practice.** The CCPA probably doesn't apply (§3), and the shop doesn't sell or share data, so there is nothing for the signal to switch off.

**What to do.**

- **Privacy Policy section "How we respond to Do Not Track and Global Privacy Control signals".** Say:
  - We don't track you across other websites or apps. Two other companies can receive information from visitors' devices: Stripe's card page (device and browser details, including across other sites that use Stripe, to prevent fraud) and Google (IP address and browser details when reviewers' photos load). Saying that no other company can track visitors would be wrong (see §1, element 6).
  - Visitors are treated the same with or without DNT.
  - We treat GPC as a request not to sell or share your personal information. We don't sell or share it in any case.
- **Optional product changes:** publish `/.well-known/gpc.json`, and show a short "Your browser's privacy signal is on; we honor it" note where it's detected.

---

## 3. CCPA / CPRA

**The rule.** The CCPA (Civ. Code §1798.100 et seq.) applies to a for-profit "business" doing business in California that meets **one** of these thresholds:

- **(A)** Annual gross revenue over **$26,625,000**. This is the CPI-adjusted figure since January 1, 2025 ([CPPA](https://www.cppa.ca.gov/regulations/cpi_adjustment.html), posted Dec 17, 2024). The CPPA adjusts it every odd-numbered year, so **the next adjustment is due in January 2027**. The AG reads this revenue test as worldwide revenue, not just California revenue.
- **(B)** Buys, sells or shares the personal information of 100,000 or more consumers or households a year. "Share" means for cross-context behavioral advertising.
- **(C)** Gets 50% or more of its revenue from selling or sharing personal information.

**Recent:** new and amended regulations took effect January 1, 2026. They cover risk assessments, automated decision-making, cybersecurity audits, mandatory opt-out confirmation, access to data going back to January 1, 2022, and treating the data of known under-16s as "sensitive" ([Covington](https://www.globalpolicywatch.com/2025/11/california-finalizes-updates-to-existing-ccpa-regulations/); [Foley, Sept 2025](https://www.foley.com/insights/publications/2025/09/updated-ccpa-regulations-approved-by-california-office-of-administrative-law/)). These apply only to covered businesses.

For covered businesses, the CCPA also requires:

- answering requests within **45 days**, extendable once by 45 days with notice;
- offering two request methods, including a toll-free number, unless the business is online-only;
- updating the privacy policy **at least every 12 months** ([Civ. Code §1798.130, FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-1798-130/)).

**Does it apply? Probably doesn't apply.**

- We don't know the shop's revenue. The owner should confirm it is below $26,625,000.
- The code doesn't sell personal information or share it for advertising: there are no ad pixels or trackers. So thresholds (B) and (C) are zero, however many clients the shop has.
- This changes if ad trackers or "sharing" are ever added. That is another reason to keep the site tracker-free.

**What to do.** The documents shouldn't claim CCPA compliance obligations the shop doesn't have, or say flatly "the CCPA doesn't apply to us". Instead, adopt its main protections as **good practice**:

- Describe what is collected, where it comes from, why, who receives it (service providers only) and how long it is kept.
- State plainly: "We don't sell or share your personal information," and that the site doesn't track people for ads.
- Offer **access, correction and deletion** to everyone, with no different treatment for people who ask.
- **Verification without accounts:** match the name, phone number and an appointment detail, then confirm by calling or texting back the number on file.
- **Response time:** aim for 45 days or less, borrowing the CCPA's benchmark.
- **Review:** look at the policy at least once a year and update "last updated".

---

## 4. Children and teens

### 4.1 COPPA and the amended COPPA Rule

**The rule.** COPPA covers operators of sites and apps **directed to children under 13**, or with **actual knowledge** that they collect personal information from a child under 13.

**Recent:** the FTC's amended Rule was published April 22, 2025 (90 FR 16918), took effect June 23, 2025, and had a **compliance date of April 22, 2026** ([Federal Register](https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule)). Its key changes:

- separate parental consent before disclosing children's data to third parties, for example for targeted ads;
- no indefinite retention, plus a **written data retention policy published in the online notice**;
- a written information security program;
- biometric and government identifiers added to "personal information"

([FTC, Jan 16, 2025](https://www.ftc.gov/news-events/news/press-releases/2025/01/ftc-finalizes-changes-childrens-privacy-rule-limiting-companies-ability-monetize-kids-data); [Fenwick](https://www.fenwick.com/insights/publications/what-the-amended-coppa-rule-means-for-data-retention-practices)).

**Does it apply? Probably doesn't apply.** A barbershop booking site and app is general-audience: no child-directed content, ads or design. Bookings come from adults or parents. Information a parent gives about a child isn't information collected *from* a child.

That could change under California's age-signal law (§4.2). An app that receives an "under 13" signal has actual knowledge.

**What to do.**

- **Privacy Policy:**
  - "Our website and apps aren't meant for children under 13, and we don't knowingly collect their personal information."
  - "A parent or guardian should make bookings for a child."
  - "If we learn we collected a child's information without a parent, we'll delete it. Contact us."
- **Product:** when the age signal (§4.2) says the user is under 13, don't take their details. Show "Please ask a parent or guardian to book" and the shop's phone number.

### 4.2 California's Digital Age Assurance Act (AB 1043, as amended by AB 1856) — **Coming: January 1, 2027**

**The rule.** AB 1043 was signed October 13, 2025, and amended by **AB 1856 (Chapter 184, Statutes of 2026, chaptered September 10, 2026)**. Its main points:

- **Operating systems:** must collect the user's age or birth date at account setup and pass an **age-bracket signal** to app stores and developers.
- **Developers:** the enrolled text keeps the rule that a developer "shall request a signal with respect to a particular user" from the operating system or app store **when the application is downloaded and launched** ([CalMatters Digital Democracy, AB 1856](https://calmatters.digitaldemocracy.org/bills/ca_202520260ab1856)).
- **Effect of a signal:** a developer that receives one is deemed to have **actual knowledge** of the user's age range on that device.
- **Requests without a legal duty:** AB 1856 also bars requesting a signal when no law requires it.
- **Dates:** requirements start **January 1, 2027**. For apps downloaded before then, the summary of the bill says developers must request signals by **July 1, 2027**.
- **Enforcement:** the AG only, with penalties up to **$2,500 per affected child** for negligent violations and **$7,500** for intentional ones ([Kelley Drye, Oct 21, 2025](https://www.kelleydrye.com/viewpoints/blogs/ad-law-access/faq-digital-age-assurance-act-california-youth-safety-on-the-internet); [Inside Privacy, Sep 21, 2026](https://www.insideprivacy.com/childrens-privacy/california-enacts-several-minors-privacy-and-safety-laws/)).

Commentators read the developer duty differently:

- [Fenwick (Oct 9, 2026)](https://www.fenwick.com/insights/publications/california-enacts-comprehensive-child-safety-laws-targeting-ai-chatbots) stresses the ban on requests without a legal duty.
- The bill text itself still contains the download-and-launch request duty.

**A California attorney should confirm this before January 1, 2027.**

**Does it apply? Applies** to both iPhone apps. Each is an "application" with a developer, and neither seems to fall under any exclusion in the materials reviewed.

**What to do.**

- **Product (both apps), must do:** adopt Apple's **Declared Age Range API** in any version of the apps available on or after January 1, 2027 (a must-do in the owner checklist, not a recommendation). Apple's tool returns an age range and how it was confirmed ([Apple, Age assurance](https://developer.apple.com/support/age-assurance)). Decide what an under-13 user sees (see §4.1).
- **Privacy Policy, once this is built:** say the app asks the iPhone for an age range because California law requires it, uses it only to apply age rules, and doesn't store it. Say only what is true of the implementation. The current documents say nothing about it, because nothing is built yet.

### 4.3 Other states' app-store age laws (Texas, Utah, Louisiana)

**The rule.**

- **Texas SB 2420** requires age verification through the app stores, parental consent for under-18 downloads and purchases, and notices of "significant changes".
  - A federal court blocked it on December 23, 2025 ([Privacy World](https://www.privacyworld.blog/2025/12/federal-judge-enjoins-enforcement-of-texas-app-store-age-verification-law/)).
  - The Fifth Circuit then stayed that injunction ([Pearl Cohen, Jun 28, 2026](https://www.pearlcohen.com/fifth-circuit-stays-injunctions-against-texas-app-store-accountability-act/)).
  - Apple applied the rules to **new Texas accounts from June 4, 2026**. It told developers to review the Declared Age Range API, the Significant Change API (PermissionKit) and related tools, and said it's "the developer's responsibility to determine when there's a significant change" ([9to5Mac, Jun 3, 2026](https://9to5mac.com/2026/06/03/apple-says-texas-app-store-age-assurance-rules-start-tomorrow-after-court-ruling/)).
- **Utah** (May 2026) and **Louisiana** (July 1, 2026) have similar laws, which Apple supports with the same tools ([Apple developer news, Feb 2026](https://developer.apple.com/news/?id=f5zj08ey)).
- The litigation is ongoing.

**Does it apply? May apply** if people in those states download the apps (App Store distribution is national). The practical risk is low for a local shop, but the developer account holder should follow Apple's guidance and have the attorney confirm. Limiting the apps' App Store availability to the United States, and following Apple's age-assurance steps, keeps this simple.

### 4.4 California's other minors' rules

- **Marketing restricted products to minors** (Bus. & Prof. Code §22580; [FindLaw](https://codes.findlaw.com/ca/business-and-professions-code/bpc-sect-22580/)): bars marketing alcohol, tobacco, tattoos and similar products to minors on child-directed services or to known minors. **Doesn't apply**: the shop markets none of these.
- **AB 2246 (Chapter 187, Statutes of 2026, signed September 10, 2026)** replaces the enjoined Age-Appropriate Design Code. It covers businesses whose online services are "likely to be accessed by children" (under 18). The six indicators include being child-directed, ads aimed at children, child-appealing design and audience data ([Hunton, Oct 7, 2026](https://www.hunton.com/privacy-and-cybersecurity-law-blog/california-enacts-new-law-governing-online-services-accessed-by-children)).
  - **Probably doesn't apply.** A barbershop booking app fits none of the indicators.
  - We couldn't confirm whether the new law borrows the CCPA's "business" thresholds, as the old one did. Attorney to confirm.
- **CCPA minors' rules** (opt-in before selling or sharing an under-16's data): only for covered businesses, and the shop doesn't sell or share data anyway.
- **Minors' contracts** (Family Code §6710; [FindLaw](https://codes.findlaw.com/ca/family-code/fam-sect-6710/)): a minor may cancel ("disaffirm") a contract before turning 18 or within a reasonable time after. A no-show fee agreed by a minor could therefore be unenforceable.
  - **Terms / Cancellation Policy:** "You must be 18 or older to save a card for a booking, or use a card with the cardholder's permission. A parent or guardian should book for anyone under 18." Owner to confirm the age rule. (The documents say: under 13, a parent or guardian books; to add a card, 18 or older, and the card must be yours or used with the cardholder's permission.)

---

## 5. Security, breach notification and disposal

**The rules.**

- **Breach notice** ([Civ. Code §1798.82, FindLaw, current as of Jan 1, 2026](https://codes.findlaw.com/ca/civil-code/civ-sect-1798-82/)):
  - **Recent:** SB 446 was signed October 3, 2025, and took effect January 1, 2026. Affected Californians must now be notified **within 30 calendar days** of discovering a breach. Delays are allowed for law enforcement or to work out the scope ([Moore & Van Allen](https://www.mvalaw.com/data-points/california-amends-data-breach-notification-requirements); [National Law Review](https://natlawreview.com/article/california-enacts-30-day-data-breach-notification-deadline)).
  - If more than 500 Californians are notified, a sample notice goes to the AG **within 15 days** of notifying them.
  - The notice must be titled "Notice of Data Breach", use set headings ("What Happened?", "What Information Was Involved?", "What We Are Doing", "What You Can Do", "For More Information") and be at least 10-point type.
  - The duty covers "personal information" as defined in the statute:
    - a name plus an SSN, a government ID number, a card number *with its security code*, medical or health insurance data, biometric data and similar; **or**
    - a username or email plus a password or security answer.
  - Encrypted data is covered only if the key was also taken.
- **Reasonable security** ([§1798.81.5](https://codes.findlaw.com/ca/civil-code/civ-sect-1798-81-5/)): keep "reasonable security procedures and practices appropriate to the nature of the information", and require the same by contract of non-affiliated third parties that receive it.
- **Disposal** ([§1798.81](https://codes.findlaw.com/ca/civil-code/civ-sect-1798-81/)): when records are no longer kept, shred, erase or otherwise make the personal information unreadable.
- **PCI DSS** ([Stripe security guide](https://docs.stripe.com/security/guide)):
  - Stripe is a certified PCI Level 1 service provider.
  - Each business must accept payments in a PCI-compliant way and **attest to it annually**, through the Stripe Dashboard's compliance documents.
  - Card brand, last 4 digits and expiry are outside PCI scope and can be stored.

**Does it apply? Applies.** Notes on the shop's data:

- A breach of only names, phone numbers and appointment times may not legally require notice under §1798.82, because those aren't "personal information" as defined there.
- Owner credentials are another matter. The owner key and the computer sign-in codes and sessions are credentials that open an online account, and could count.
- Either way, telling affected clients is the decent and expected thing to do.

**What to do.**

- **Privacy Policy, security section.** Describe safeguards in general terms only, as the AG recommends:
  - card numbers go only to Stripe, never to the shop;
  - connections are encrypted;
  - owner access is protected;
  - information is kept only as long as needed (see §17).
- **Privacy Policy, breach section:** "If a breach affects your personal information, we'll notify you as California law requires." Avoid promises beyond the law, such as "within 24 hours".
- **Don'ts:** **never claim "PCI certified"**, an audit or a certification that didn't happen. Say "card payments are handled by Stripe, which is certified to the PCI DSS".
- **Owner checklist:** complete Stripe's yearly PCI self-assessment.

---

## 6. Email and text messages (CAN-SPAM, TCPA)

**What the code does.** See "What the code shows":

- no marketing;
- no email or SMS sending by the server;
- optional client email on the website and in the shop's tools;
- Stripe receipts for in-person card payments when staff enter an email;
- a manual "text this client" link in the Business app.

**CAN-SPAM** ([FTC guide](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business), Aug 2023, penalty updated since):

- What counts depends on an email's **primary purpose**.
- Transactional or relationship messages are largely exempt and only need truthful routing information. Examples: confirming an agreed transaction, or delivering a service already agreed.
- Commercial email needs accurate headers, honest subject lines, an ad disclosure, a physical postal address and an opt-out honored within 10 business days.
- The guide puts penalties at up to **$53,088 per email**.

**TCPA:**

- Autodialed or prerecorded calls and texts need prior consent. Marketing needs prior express written consent.
- **Recent:** the FCC's consent-revocation rules took effect April 11, 2025. The FCC then replaced the "revoke-all" part with a narrower rule, effective November 25, 2026 ([Report and Order, 91 FR 67214, October 26, 2026](https://www.federalregister.gov/documents/2026/10/26/2026-21821/enhancing-the-ability-of-consumers-to-control-the-robocalls)): a caller may treat an opt-out as covering only the category of informational robocalls it was aimed at, and may name one exclusive way to opt out. These rules cover only autodialed or prerecorded calls and texts, which the shop doesn't send.
- The FCC's "one-to-one consent" rule was eliminated in July 2025.
- **Recent:** in *McLaughlin Chiropractic v. McKesson* (U.S. Supreme Court, June 20, 2025, 6–3), the Court held that district courts aren't bound by the FCC's interpretations of the TCPA. Commentators note it leaves *Facebook v. Duguid*'s narrow "autodialer" definition in place ([Steptoe](https://www.steptoe.com/en/news-publications/the-supreme-court-makes-clear-that-district-courts-are-not-bound-by-the-fccs-interpretation-of-the-telephone-consumer-protection-act.html); [Reed Smith](https://www.reedsmith.com/our-insights/blogs/viewpoints/102kq4q/supreme-court-gives-courts-wide-latitude-to-disregard-fcc-guidance-on-the-telepho/)).

**Does it apply? Probably doesn't apply today.**

- Nothing automated is sent.
- Stripe receipts are transactional.
- A barber texting a client by hand from their own phone about an appointment is ordinary communication. Promotional texts would still carry risk.

**What to do.**

- **Privacy Policy and Terms:**
  - "We use your phone number and email only to contact you about your appointments."
  - "We don't send marketing emails or texts."
  - "If you pay by card at the shop and give an email, Stripe emails your receipt."
- **Owner checklist:** don't send promotional texts or emails without consent. If automated reminders are added, get clear consent at booking, honor "STOP", and update the policy first.

---

## 7. Prices and fees: honest pricing, gender pricing, discounts, gift cards

### 7.1 Honest Pricing Law (SB 478) — Civ. Code §1770(a)(29), in force July 1, 2024

**The rule.** It is unlawful to advertise, display or offer a price that doesn't include all mandatory fees or charges, apart from government taxes and actual shipping costs ([FindLaw §1770](https://codes.findlaw.com/ca/civil-code/civ-sect-1770/)). The AG's guidance ([oag.ca.gov/hiddenfees](https://oag.ca.gov/hiddenfees)) adds:

- It is a transparency law, not a price control.
- Fees for optional services needn't be included.
- **"Fees that are contingent on certain later conduct by a consumer are not mandatory and do not need to be included in the advertised price."** The examples given are late equipment-return fees and smoking fees.
- A card fee isn't mandatory if the customer can avoid it by paying another way.
- A variable fee added later is prohibited.
- A business that doesn't yet know its final charge "should wait to display a price until they know how much they will charge."

The CLRA also bars "advertising goods or services with intent not to sell them as advertised" (§1770(a)(9)) and "inserting an unconscionable provision in the contract" (§1770(a)(19)).

The FTC's federal fee rule (16 CFR Part 464, in force May 12, 2025) covers **only live-event tickets and short-term lodging** ([Kelley Drye](https://www.kelleydrye.com/viewpoints/blogs/ad-law-access/ftc-issues-faqs-on-fees-rule-affirms-rule-to-become-effective-next-week); [Sidley](https://sidley.com/en/insights/newsupdates/2024/12/ftc-announces-final-junk-fees-rule-that-is-significantly-narrower-than-proposed-rule)). It **doesn't apply**.

**Does it apply? Applies** to every price shown on the site and in the apps.

**What to do.**

- **Terms:**
  - "Prices shown include everything you'll be charged for the service."
  - "We don't add booking, service or other required fees."
  - "Tips are always optional." Voluntary tips are outside SB 478.
  - Only say "no card fees" if that's true. If the shop ever adds a card surcharge, get legal advice first. (The Terms promise no booking fees or other required charges on top of the price, and don't mention card fees by name. The owner checklist, section 1, asks the owner to confirm the shop never adds a card fee or other extra charge at the counter: a surcharge rung up as a custom checkout item would break the Terms' promise, and would breach SB 478 unless clients could avoid it by paying another way and it was disclosed.)
- **"From" prices:** a price varies by barber, so "From $X" must be **a real, bookable lowest price** for that service. The exact price for the chosen barber must show before booking, as the Review step does now. One offering is a true starting price ("From $80" for a lightener with Izzy, `priceKind: startingAt`), so the Terms say the barber gives the final price before starting work, and that the client can say no without any fee. The Terms' promise that "the price you see is what you pay" names both exceptions (that starting price, and the range shown for "any barber" when barbers' prices differ, as for Haircut & Beard at $55 or $60), because an absolute promise next to an exception would be read against the shop (Civ. Code §1654).
- **The no-show / late-cancel fee** is contingent on the client's later conduct, so it **isn't part of the advertised price**. It must still be shown **clearly before booking**, as it is now (on "Pick a day and time", on Review, and on Stripe's page), so it doesn't deceive.

### 7.2 Gender pricing: barbers and hair salons (Civ. Code §51.6)

**The rule** ([FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-51-6/)):

- **No price differences by gender** for services of similar or like kind. Differences based on time, difficulty or cost are allowed.
- **Barbers and hair salons** must:
  - disclose in writing the price of each "standard service", meaning the 15 most requested services;
  - **post a price list** in at least 14-point bold type;
  - give a complete written price list on request;
  - **post a sign** in at least 24-point bold type stating that California law prohibits gender-based price discrimination and that a complete price list is available on request (exact statutory wording).
- Failing to correct a violation within 30 days of written notice costs a **$1,000** penalty.

**Does it apply? Applies** to the shop.

- The online service names are gender-neutral, which is good: Haircut, Military Haircut, Seniors Haircut, Haircut & Beard, VIP, Hot Towel Shave and so on (`server/data/catalog.json`).
- The online menu helps, but **doesn't replace** the posted list and sign in the shop.

**What to do.**

- **Owner checklist:** post the price list and the statutory sign in the shop, and keep prices based on time and difficulty.
- **Terms:** a short line that prices depend on the service and barber, never on gender.

### 7.3 Senior and military prices

The Unruh Act bars arbitrary discrimination, not every distinction. California courts have upheld age-based discounts. *Koire v. Metro Car Wash* (1985) noted that "charging different prices to children and senior citizens is sometimes permissible and socially desirable" ([Stanford SCOCAL](https://scocal.stanford.edu/opinion/koire-v-metro-car-wash-28485)). *Starkman v. Mann Theatres* (1991) upheld senior and child ticket pricing ([Justia](https://law.justia.com/cases/california/court-of-appeal/3d/227/1491.html)).

"Seniors Haircut" and "Military Haircut" are fine. Describe them accurately, and apply eligibility rules evenly. Because of these services, the Terms' non-discrimination line doesn't say prices never depend on any personal characteristic; it says prices never depend on gender, and that no one is refused service or treated unfairly because of a protected characteristic.

### 7.4 Gift cards (if the shop sells them in person)

**Rule** ([Civ. Code §1749.5](https://codes.findlaw.com/ca/civil-code/civ-sect-1749-5/)):

- no expiration dates;
- no service or dormancy fees, apart from a narrow exception;
- **Recent:** from **April 1, 2026** (SB 22, Chapter 207, Statutes of 2025), a card with **less than $15** left must be redeemed in cash on request. The threshold was $10 ([Morgan Lewis, Mar 2026](https://www.morganlewis.com/pubs/2026/03/california-raises-gift-card-cash-out-threshold-to-15); confirmed by [Stradling](https://www.stradlinglaw.com/news-insights/california-increases-gift-card-cash-out-threshold-to-dollar15-starting-april-1-2026.html)).

**What to do.** The apps don't sell gift cards, but the catalog lists "Gift card" as a payment method, so the Terms carry one line: gift cards bought at the shop don't expire, carry no service fees, and can be cashed out under $15 on request. Owner checklist: confirm and follow these rules for any gift card sold in the shop.

---

## 8. The no-show and late-cancellation fee

### 8.1 What the shop does today

See "What the code shows":

- off by default;
- **default 100% of the service price** within **1 hour** of the start, or for a no-show;
- percent mode 1–100%, or flat mode $0.50–$500;
- late cancellations can be switched off, leaving only no-shows chargeable;
- the policy text is shown before booking and on Stripe's page, and stored with the booking with the consent time;
- the barber decides each time whether to charge ("may charge");
- charged later, off-session, to the saved card, at most once per appointment.

### 8.2 Is a 100% fee enforceable? Civil Code §1671(d)

**The rule.** [Civ. Code §1671](https://codes.findlaw.com/ca/civil-code/civ-sect-1671/):

- Most contracts use a lenient test: a liquidated-damages clause is valid unless shown unreasonable (§1671(b)).
- **Consumer contracts for services "primarily for personal, family, or household purposes"** fall under §1671(c)(1) and (d) instead. There, a liquidated-damages clause is **void**, except for an agreed amount presumed to be the damage **"when, from the nature of the case, it would be impracticable or extremely difficult to fix the actual damage."**

The courts' test, from *Cellphone Termination Fee Cases* (2011) 193 Cal.App.4th 298 ([opinion copy](https://hallapproved.com/ca/cases/appeals/2011/5810082)):

1. Fixing actual damages must be impracticable or extremely difficult.
2. The amount must "represent a reasonable endeavor to estimate fair compensation for the loss sustained."
3. Consumer clauses are presumed void, so **the business carries the burden**.
4. The test looks at the circumstances **when the term was set**: "the required reasonable endeavor logically must have preceded the setting of those amounts" (citing *Hitz*).
5. A clause that "bears no reasonable relationship to the range of actual damages" is a penalty (*Ridgley v. Topa Thrift & Loan* (1998) 17 Cal.4th 970).

In that case, Sprint's early-termination fees were held to be penalties. They had been set **to deter** cancellations rather than to estimate loss, and after-the-fact justifications didn't save them.

A term that "merely provides an option of alternative performance" escapes §1671. But courts look at substance. *Garrett* warns against "a single, definite performance with an additional charge contingent on the breach." A no-show fee looks like exactly that.

**Analysis for this shop (attorney to confirm):**

- **Treat both fees as liquidated damages** and meet §1671(d). Don't rely on an "alternative performance" label.
- **Part 1, impracticable to fix:** this is plausible. A barber's time is the service. Whether a slot left empty at short notice can be refilled depends on walk-ins and the day, so the loss can't be fixed in advance.
- **Part 2, a reasonable estimate:**
  - *No-show* at 100%: arguably reasonable, since the slot's revenue is usually lost entirely. But the shop's real loss is the price minus costs saved (supplies). 100% sits at the top of the range.
  - *Late cancellation with a 1-hour window* at 100%: similar reasoning, as there's little time to rebook.
  - *Longer windows* at 100% are **harder to defend**: the owner can set up to 48 hours, and a slot cancelled a day ahead can often be refilled.
  - **Flat mode is the clearest risk.** A $20 flat fee on a $5 service (the menu has $5 items) is four times the price and bears "no reasonable relationship" to the loss.

### 8.3 What makes the fee more defensible

1. **A reasonable amount:**
   - **Product:** cap every fee at the booked service's price, so flat mode can never exceed it.
   - Consider a lower percentage for late cancellations than for no-shows, or for longer windows.
   - Never charge more than the amount shown at booking. The server already uses the stored amount.
2. **Write down the reasoning when choosing the amount.** For example: "a no-show leaves the barber's slot empty; we can rarely fill it within an hour."
3. **Clear notice before booking:**
   - Keep the notice on the time picker and on Review, and the text on Stripe's page.
   - **Add a link** to the full Cancellation & No-Show Policy and the Terms next to the agreement text.
4. **Consent stored:** keep the exact text, the consent time, and the card brand and last 4 digits for each booking. This is strong evidence if the client disputes the charge (§9).
5. **The shop's discretion:**
   - "May charge" is good. It lets the barber waive the fee for emergencies, first-time slips or a refilled slot.
   - Apply the waiver criteria **evenly**. Uneven waivers could look discriminatory under the Unruh Act (§10).
   - Only promise a waiver rule if it will always be kept.
6. **An easy free-cancellation path:**
   - "Cancelling in the app more than [window] before is free."
   - The Policy should also say what happens if a client *calls* the shop in time. Owner decision; recommended: also free. **In the code, a booking the shop cancels can never be charged**, whenever it's cancelled, so the documents say a cancellation made by the shop, including after a client calls, has no fee.
7. **Tell the client when a fee is charged.**
   - The server sends no receipt for fees.
   - Card networks require telling cardholders about changes, and Stripe recommends clear, recognizable charges (§9).
   - Have the barber text or call, or send a receipt when an email is on file. Set a recognizable **statement descriptor**, for example "IZZY CLIPZ".
8. **Adults only:** require the card saver to be 18+ or have the cardholder's permission (§4.4).
9. **"Remember me":** in the iPhone app it **starts ticked**, and with a card it keeps the card for later bookings. Stripe's guidance is to "explicitly collect consent ... for this specific use", for example a "Save my payment method for future use" checkbox; a box that starts ticked isn't explicit consent. **Required:** start it unticked in the app, as on the website (on only when the device already remembers the client). Without "Remember me", the card should be deleted once its booking can no longer be charged, instead of staying at Stripe for up to 12 months with no way for the client to remove it.
10. **A charging deadline.** Nothing limits how long after a visit a fee can be charged. Card-network rules say not to charge "beyond the duration expressly agreed by the cardholder" (§9.2). The documents promise fees are charged within **7 days** after the appointment time, or not at all, and the code should enforce it.
11. **A grace period for bookings made after the cutoff has passed.** With a 30-minute lead time and a window of up to 48 hours, a client can book a time that's already inside the window, and today a cancellation one minute later is a late cancellation at 100%, although the shop lost nothing (the time was free a minute earlier). A fee where the actual loss is plainly zero looks like a penalty under §1671(d) (*Ridgley*; *Cellphone Termination Fee Cases*). The documents give a **15-minute grace period** after booking (owner decision, attorney to confirm), and the code must enforce it and say so on the booking screens.
12. **When a no-show can be charged.** The documents say a client who arrives before the end of the appointment isn't a no-show. The server must match: a booking with a card on file can be marked a no-show, and charged, only after its end time, and once it's marked completed it can't become a no-show. Otherwise a client charged at 10:01 who arrives at 10:10 has a dispute the policy can't settle, and the shop has CLRA (§1770(a)(14)) and chargeback exposure.
13. **Say what the fee is.** A short recital in the policy ("the fee is our agreed estimate of that loss, not a penalty", with why the loss is hard to know in advance) supports part 1 of the §1671(d) test. It doesn't replace a reasonable amount.

### 8.4 Forming the agreement online

**Cases:**

- *Berman v. Freedom Financial* (9th Cir. 2022) and *Chabolla v. ClassPass* (9th Cir., Feb. 27, 2025): online terms bind only with **reasonably conspicuous notice** and an **unambiguous manifestation of assent**.
- In *Chabolla*, the notice sat below the buttons in light grey, and the button wording didn't match the notice. The court favored notices placed **just above the action button** that **explicitly tie the button to agreement** ([Fenwick, Mar 27, 2025](https://www.fenwick.com/insights/publications/thats-a-wrap-ninth-circuit-signals-tougher-standards-for-enforceability-of-online-agreements); [Eric Goldman](https://blog.ericgoldman.org/archives/2025/03/the-ninth-circuit-has-a-lot-to-say-about-online-contract-formation-much-of-it-confusing-chabolla-v-classpass.htm)).
- A 2026 follow-on, *Blackburn v. ClassPass*, distinguished *Chabolla* on its facts ([Eric Goldman, Apr 2026](https://blog.ericgoldman.org/archives/2026/04/remember-when-the-ninth-circuit-rejected-classpass-tos-formation-about-that-blackburn-v-classpass.htm)).

**Status: largely already fine for the fee.**

- The full policy text appears above the button.
- The lead-in says "By booking, you agree to this:" (app) or "What you agree to by booking" (web), and the button says **"Book appointment"**.
- Stripe's page also shows the policy above its submit button.

**The Terms of Service aren't shown at booking yet**, so on their own they would be a weak "browsewrap". The documents rely on a notice directly above "Book appointment": "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy", with both linked.

**Improvements:**

- link the full Cancellation Policy and Terms in that block;
- keep the text high-contrast and readable at large text sizes;
- optionally add an unticked "I agree to the Cancellation & No-Show Policy" checkbox. It's strongest for disputes, and Stripe's own guidance favors explicit consent (§9).

### 8.5 What the Cancellation & No-Show Policy page must say

It must match the server exactly:

- **Free cancellation:** cancelling more than the window before the start is free, in the app, on the website, or by phone (a cancellation made by the shop is never charged).
- **The window:**
  - Default 1 hour, but the shop can change it.
  - **The window and fee shown when you booked apply to that booking.** The server stores them.
  - Shop policy changes apply only to new bookings. The site shows "The shop just changed its policy" before booking.
- **What triggers a fee:**
  - **Late cancellation:** cancelling less than the window before the start. Exactly the window before is still free. The app and website ask the client to confirm first.
  - **No-show:** not coming and not cancelling.
  - The Policy must also say whether lateness counts. Owner decision. The documents say a client who arrives after the appointment time has ended is a no-show, and otherwise the barber fits them in if possible; a no-show fee can be charged only after the end time, which the code must enforce (§8.3 item 12).
  - **Booking after the cutoff has passed:** the booking screens warn about it. Cancelling within 15 minutes of booking is free for every booking, as the server enforces it (§8.3 item 11).
- **How much:**
  - Exactly the amount shown at booking: a percentage of the service price, default 100%, or a flat amount.
  - **Never more than the service price**, once the cap above is built.
- **Discretion:** the shop *may* charge; the barber decides; waivers are applied fairly.
- **When and how:**
  - Charged after the missed or late-cancelled appointment, to the card saved through Stripe, within 7 days.
  - Nothing is charged at booking.
  - The client will be told (see §8.3 item 7).
- **The card:**
  - Saved with Stripe. The shop never sees the full number.
  - Kept for later bookings only if "Remember me" is chosen; otherwise deleted once its booking can no longer be charged.
  - How to remove it.
  - The agreement for a booking ends when the client comes, cancels on time, the shop cancels, or 7 days after the appointment.
- **Disagreeing with a charge:** contact the shop first (phone or in person). This doesn't limit the client's rights with their card issuer.
- **Who can agree:** adults, or with the cardholder's permission (§4.4).
- **Demo:** in the demo, nothing is sent and no card is saved.

---

## 9. Stripe's requirements and the card networks' rules

### 9.1 Stripe

**Saving a card for later off-session charges** ([Stripe, Save a payment method — Compliance](https://docs.stripe.com/payments/save-and-reuse?payment-ui=elements)):

- "You're responsible for your compliance with all applicable laws, regulations, and network rules when saving a customer's payment details."
- "Add terms to your website or app that state how you plan to save payment method details and allow customers to opt in."
- You can use a saved method "only for the specific usage you've included in your terms," and should "explicitly collect consent", for example with a checkbox.
- To charge when the customer is offline, the terms must include:
  - the customer's agreement to your initiating a payment, or a series of payments, on their behalf for specified transactions;
  - the anticipated timing and frequency;
  - how you determine the amount;
  - the cancellation policy, for subscriptions.
- **Status:** the stored policy text covers the triggering events, the amount and the free-cancellation rule. The Cancellation Policy and Terms cover timing ("after the appointment", within 7 days), duration and how to remove the card. Opting in must be explicit, so "Remember me" has to start unticked in the app too (§8.3 item 9).

**Checkout options** ([Stripe, Checkout custom text and policies](https://docs.stripe.com/payments/checkout/custom-components?ui=full-page); [setup mode](https://docs.stripe.com/payments/checkout/save-and-reuse?payment-ui=stripe-hosted)):

- `custom_text.submit` takes up to 1,200 characters, with **Markdown links** allowed. It can link to the full policy.
- `consent_collection.terms_of_service: "required"` shows a checkbox. It needs a Terms of Service URL in the Dashboard's **Public details**, and records `consent.terms_of_service = accepted`.
- In setup mode, Checkout shows Stripe's own payment-method reuse text by default. The code doesn't hide it; keep it shown.
- Checkout Settings can show the shop's support phone and email and its Terms and Privacy links. These must be filled in under Public details.

**Public business information and website requirements:**

- Customers see the business name, website, support phone, email and address, and the statement descriptor, on statements and receipts ([Stripe, Set up your account](https://docs.stripe.com/get-started/account/activate)).
- Stripe expects a business's site or app to show:
  - the business name;
  - accurate descriptions of its services;
  - customer-service contact details;
  - a refund and dispute policy;
  - a cancellation policy;
  - a return policy, if physical goods are sold (products are sold only in the shop);
  - any legal restrictions;
  - promotion terms

  ([Stripe support FAQ](https://support.stripe.com/questions/business-website-for-account-activation-faq)).
- **Status:** the Cancellation & No-Show Policy covers cancellations and fee disputes. The Terms have a "Refunds" line the owner must fill in (what happens if a client is unhappy with a service or a product); the documents don't invent one. If products aren't fully refundable or exchangeable for 7 days, Civil Code §1723 also requires the policy to be posted at the counter.

**Disputes** ([Stripe, Preventing disputes](https://docs.stripe.com/disputes/prevention/best-practices); [How disputes work](https://docs.stripe.com/disputes/how-disputes-work)):

- Include refund and cancellation policies in the Terms and require agreement.
- Issuers may reject a checkbox that "only contains a link". There must be evidence that the customer saw "a full copy of your policies prior to their purchase". The shop shows the full text: good.
- Use a recognizable statement descriptor (5–22 characters).
- Cardholders can usually dispute **within 120 days**. For appointments, the window "starts on the event date, not the payment date."
- The business usually has 7–21 days to respond.

**PCI:** see §5. **Connect:** the shop connects its own Stripe account, so Stripe processes the payments. The Privacy Policy should link [Stripe's privacy policy](https://stripe.com/privacy).

**Tap to Pay on iPhone** (Business app; [Stripe docs](https://docs.stripe.com/terminal/payments/setup-reader/tap-to-pay?platform=ios)):

- requires Apple's Tap to Pay entitlement (`com.apple.developer.proximity-reader.payment.acceptance`, present in `IzzyClipzBusiness/IzzyClipzBusiness.entitlements`), granted to the developer account under Apple's own Tap to Pay terms;
- requires location permission while taking payments: Stripe "must know where payments occur" and turns payments off without it ([Stripe Terminal iOS setup](https://docs.stripe.com/terminal/payments/setup-integration?terminal-sdk-platform=ios)); the app asks for it while in use;
- Stripe Terminal 6.0.0's own privacy manifest declares **coarse location** and **product interaction** data (not linked to the user, not used for tracking). The Business app's App Privacy answers should include them (§11);
- the card is read by Apple's Tap to Pay technology, so card numbers never reach the shop's app or server. The Privacy Policy says so. Today the payment description sent to Stripe includes the client's name when staff type no note (`IzzyClipzBusiness/Payments/CheckoutModel.swift`); the documents assume it no longer does (§18), and that a receipt email is asked for only after the payment (§9.3).

### 9.2 Card-network rules for stored cards

Visa's stored-credential framework ([Visa, "Improving Authorization Management for Transactions with Stored Credentials"](https://usa.visa.com/dam/VCOM/global/support-legal/documents/stored-credential-transaction-framework-vbs-10-may-17.pdf), in force since October 2017) applies, through Stripe, to Visa cards saved for later charges. Its requirements are a sound model for every card the shop saves.

**Before storing a card, the merchant must have an agreement that shows:**

- the truncated card number (last 4 digits);
- how the cardholder will be told about changes to the agreement;
- when the agreement expires, if it does;
- how the stored card will be used;
- for merchant-initiated charges: the cancellation and refund policies, the merchant's location, the amount or how it's calculated, and the event that will prompt the charge.

**While it's stored:** tell the cardholder about any change to the agreement, keep the agreement for as long as the consent lasts (and give it to the issuer on request), and don't charge beyond the agreed duration, after the cardholder cancels under the agreed policy, or after a decline without a new authorization.

**Does it apply? Applies.**

**What to do.**

- The booking screens show the card's type and last 4 digits ("Visa •••• 4242") and the policy text: good.
- The Cancellation & No-Show Policy states how the card is used (only the fee for a booking made with it), the amount rule, the triggering events, when the agreement ends (7 days after the appointment at the latest), the refund and dispute path, the shop's address, and how changes work (they never apply to existing bookings).
- Keep the stored text and consent time; give a copy on request.

### 9.3 Asking for an email at the counter (Song-Beverly Credit Card Act)

**The rule** ([Civ. Code §1747.08, FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-1747-08/)):

- A business that accepts credit cards may not request, or require as a condition of accepting the card, that the cardholder provide "personal identification information" which the business then writes down or records (subdivision (a)).
- That means information about the cardholder that isn't on the card, such as an address or phone number (subdivision (b)). The California Supreme Court held a ZIP code counts (*Pineda v. Williams-Sonoma Stores, Inc.* (2011) 51 Cal.4th 524), and a federal court treated an email address the same way in a case about e-receipts (*Capp v. Nordstrom, Inc.*, E.D. Cal., Oct. 21, 2013, an unpublished ruling on a motion to dismiss).
- There are exceptions, for example for information needed "for a special purpose incidental but related to the individual credit card transaction" such as shipping or delivery (subdivision (c)(4)). Whether an e-receipt fits is unsettled.
- Civil penalties: up to $250 for a first violation and $1,000 for each later one (subdivision (e)), and class actions are common.

**Does it apply? Applies** to card payments taken in the shop. The Business app asks for an optional "Receipt email" on the same screen as the payment, before the card is tapped, and the server records it in `payments.receipt_email` (see "What the code shows").

**What to do.**

- **Product (required):** offer the email receipt only after the payment has been approved; say it's optional and only for the receipt; send it to Stripe without keeping it (Stripe's API sends a new receipt when `receipt_email` is set on a charge afterwards: "If this field is updated, then a new email receipt will be sent to the updated address", [Update a charge](https://docs.stripe.com/api/charges/update)); never require a ZIP code, phone number or email to take a card.
- **Privacy Policy:** describe the email receipt as offered after the payment, optional, passed to Stripe and not kept.
- **Attorney:** confirm the approach.

---

## 10. Accessibility: ADA Title III, the Unruh Act and WCAG 2.2

**The rules.**

- **ADA Title III** bars disability discrimination by "places of public accommodation", which include barbershops. DOJ has no Title III regulation with a technical web standard, but its [Guidance on Web Accessibility and the ADA](https://www.ada.gov/resources/web-guidance/) (March 18, 2022) says businesses open to the public must make their websites accessible, and points to WCAG as helpful guidance.
- **The Ninth Circuit** (which covers California) held that the ADA applies to a business's website and app when they connect customers to its physical locations: *Robles v. Domino's Pizza, LLC*, 913 F.3d 898 (9th Cir. 2019). California's Court of Appeal reached the same result for a restaurant's website in *Thurston v. Midvale Corp.* (2019) 39 Cal.App.5th 634. For a website-only business, *Martinez v. Cot'n Wash, Inc.* (2022) 81 Cal.App.5th 1026 held that a website isn't a place of public accommodation under the ADA, and that without an ADA violation an Unruh claim needs intentional discrimination, which failing to fix a known problem doesn't show by itself. *Martinez v. San Diego County Credit Union* (2020) 50 Cal.App.5th 1048 applied the nexus test to a business with physical branches. Izzy Clipz has a physical shop, so the *Robles* line applies.
- **The Unruh Civil Rights Act** (Civ. Code §51) makes any ADA violation a violation of state law (§51(f)), and §52(a) sets **statutory damages of at least $4,000 for each offense** (in practice, each visit or occasion), plus attorney's fees; for building-access claims, §55.56(f) counts occasions, not violations ([FindLaw §51](https://codes.findlaw.com/ca/civil-code/civ-sect-51/); [§52](https://codes.findlaw.com/ca/civil-code/civ-sect-52/)). Website accessibility suits against small California businesses are common because of this.
- **WCAG 2.2** became a W3C Recommendation in October 2023, and **Recent:** was approved as international standard **ISO/IEC 40500:2025** ([W3C, Oct 21, 2025](https://www.w3.org/WAI/news/2025-10-21/wcag22-iso)). Level AA is the usual target.
- **Recent:** DOJ's 2024 rule for state and local governments (Title II) uses WCAG 2.1 AA. An interim final rule published **April 20, 2026** pushed its compliance dates back a year ([Seyfarth, Apr 2026](https://www.adatitleiii.com/2026/04/doj-extends-ada-title-ii-website-accessibility-deadlines-for-governmental-entities-but-litigation-and-compliance-risks-remain/)). It doesn't apply to private businesses, but shows the standard regulators use.
- **The physical shop:** California's Construction-Related Accessibility Standards Compliance Act lets a business that has had its premises inspected by a Certified Access Specialist (CASp) ask for a 90-day stay and an early evaluation conference if it's sued over building access (Civ. Code §55.54; [DGS, CASp property inspection](https://www.dgs.ca.gov/DSA/Resources/CASp-Property-Inspection)).

**Does it apply? Applies.** The shop is a public accommodation, and its website and apps book appointments there.

**What the code shows** (website code on `v5/webapp-business`, apps on `v5/int`):

- **Website:** axe-core checks (`server/web/e2e/support.ts`, `expectAccessible`) run on every page, each booking step and the Business pages, at desktop (1440 px) and phone (390 px) sizes in Chromium, and fail on any **serious or critical** violation; a test books a whole appointment with the keyboard alone (`server/web/e2e/booking.spec.ts`); the nine main pages in `PAGES` (`server/web/e2e/pages.spec.ts`) are checked to fit 375 px without sideways scrolling, and the booking steps, the confirmation and the Business pages are checked at the phone size (390 px) through `screenshot()`; a skip link, focus moved to the main content on navigation, labelled form fields with announced errors; `prefers-reduced-motion` and Windows High Contrast (`forced-colors`) styles, with one test that checks the logos on three pages in High Contrast. The legal pages aren't in any test list, or in the service worker's page list (`server/web/src/sw/routes.ts`), until they're added with them.
- **Apps:** Dynamic Type text styles throughout (`IzzyClipz/Theme/Typography.swift`), VoiceOver labels on controls in both apps, and Reduce Motion in the client app. A few fixed-size icons and large numbers don't scale.
- **Not done:** no manual testing by assistive-technology users, no outside audit, no accessibility audits in the iOS UI tests, no tests at 320 px or at large text sizes. axe-core's WCAG 2.2 rule for target size ("target-size") is off by default, so the website's checks don't cover it.
- **Shop listing:** the Visit page shows "Wheelchair accessible", "ADA-compliant entrance" and "Accessible parking near the entrance" (`server/data/catalog.json`, `IzzyClipzData.swift`). "ADA-compliant" is a legal conclusion that no inspection supports; advertising compliance that isn't there invites ADA and Unruh claims. Say what's there ("step-free entrance") instead, before launch, since the Accessibility Statement points to the Visit page.

**What a good accessibility statement contains** ([W3C, Developing an Accessibility Statement](https://www.w3.org/WAI/planning/statements/)): a commitment and the standard aimed for; what has been done; known limitations, including third-party content; other ways to get the service; how to report problems and when to expect a reply; and the date it was last reviewed. Don't claim conformance that hasn't been checked.

**What to do.**

- **Accessibility Statement:** WCAG 2.2 AA as the goal; only the measures above, worded as the tests really check them; the known limits (no audit, Stripe's page, Google's content, maps); phone booking and walk-ins as alternatives; a 5-business-day reply to reports.
- **Ways to reach the shop without a voice call.** A voice line, a visit and a letter don't work for people who are deaf, hard of hearing or speech-disabled. Title III requires "appropriate auxiliary aids and services where necessary to ensure effective communication" (28 C.F.R. §36.303(c)(1)), listing text-based ones such as written notes and text telephones (§36.303(b)(1)), and a business must "respond to telephone calls from a telecommunications relay service ... in the same manner that it responds to other telephone calls" (§36.303(d)(4)); the Unruh Act adopts this through Civ. Code §51(f). W3C's guidance also asks for several ways to make contact. So the statement offers relay calls (711), texts (once the owner confirms the number takes them) and the shop's email (a launch blocker).
- **Owner checklist:** reword "ADA-compliant entrance" before launch; consider a CASp inspection; welcome service animals and relay calls.
- **Product (recommended):** add accessibility audits to the iOS UI tests, test at the largest text sizes and at 320 px, and have someone who uses a screen reader try a booking.

---

## 11. Apple's App Store rules

**The rules** ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), last updated October 16, 2026):

- **5.1.1(i) Privacy policies:** "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app in an easily accessible manner." The policy must identify what data the app collects, how and all its uses; "confirm that any third party with whom an app shares user data ... will provide the same or equal protection of user data as stated in the app's privacy policy"; and "explain its data retention/deletion policies and describe how a user can revoke consent and/or request deletion of the user's data."
- **5.1.1(ii) Permission:** apps that collect user or usage data must get consent and give an easy way to withdraw it; purpose strings must clearly describe the use.
- **5.1.1(v) Account sign-in:** "If your app supports account creation, you must also offer account deletion within the app."
- **5.1.2 Data use and sharing:** no sharing without permission; tracking needs App Tracking Transparency.
- **App Privacy details** ("nutrition labels") in App Store Connect must match what the app and its SDKs collect. **Privacy manifests** (`PrivacyInfo.xcprivacy`) must declare collected data and the reasons for "required reason" APIs such as UserDefaults ([Apple, Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)).
- **Recent:** new age-rating questions in App Store Connect (from January 31, 2026) and the age-assurance tools in §4.2–4.3.

**Does it apply? Applies** to both apps.

- **Account deletion doesn't apply.** Neither app creates accounts: the client app uses per-booking keys, and the Business app uses the shop's owner key.
- **Privacy manifests are present.** The client app's declares Name, Phone Number, Payment Info and Other User Content. The Business app's declares nothing, though Stripe Terminal's own manifest declares coarse location and product interaction.

**What to do.**

- **Both apps:** a "Privacy Policy" link inside the app (client app: the Visit tab and Your details; Business app: Settings), and the policy's web address in App Store Connect.
- **Privacy Policy:** covers both apps, names the third parties, and gives retention and deletion. Guideline 5.1.1(i) asks the policy to "confirm" that third parties give "the same or equal protection", but the confirmation has to be true. Stripe uses End Customers' data for its own purposes where allowed (its Privacy Policy, §1.2(b)), Apple handles App Store, MapKit and Tap to Pay data under its own terms, and Vercel acts as a controller for some service data (its Data Processing Addendum, §4.b). So the policy says that Vercel and Neon process data for the shop under data protection terms (which the owner confirms are in place), and that Stripe and Apple also use some information as their own privacy policies explain. It doesn't claim that every provider protects data at least as well as the policy.
- **Apple's standard license agreement:** without a custom one, the client app is licensed under Apple's Standard EULA, which has its own "as is" disclaimer, caps the developer's liability at $50, and picks Santa Clara County courts. The Terms say they apply together with it, and that they win in a conflict unless Apple requires its own terms. The attorney should confirm that, or the shop can give the app a custom license agreement that includes Apple's minimum terms.
- **App Store Connect answers:**
  - client app: Name, Phone Number, Payment Info, Other User Content, and consider Email Address (Stripe's page, opened from the app, collects one);
  - Business app: Coarse Location and Product Interaction (Stripe), Photos or Videos (product photos), and, to be safe, Name, Phone Number, Email Address and Other User Content for the clients' details that staff enter.
- **Support URL and contact:** guideline 1.5 asks for an easy way to contact the developer; the shop's phone works, and the shop's email (a must-do in the owner checklist) is better.

---

## 12. Google Maps Platform and Yelp

### 12.1 Google Maps Platform (reviews from the Places API)

**The rule** ([Google Maps Platform Terms of Service](https://cloud.google.com/maps-platform/terms), last modified August 26, 2026):

- **§3.2.2(a)(i) Terms of service and privacy policy:** "The Customer Application's terms of service will (A) notify users that the Customer Application includes Google Maps features and content; and (B) state that use of Google Maps features and content is subject to the then-current versions of the: (1) Google Maps End User Additional Terms of Service at https://maps.google.com/help/terms_maps/; and (2) Google Privacy Policy at https://policies.google.com/privacy."
- **§3.2.2(b) Attribution:** display all attribution Google provides, and don't modify, obscure or delete it.
- **§3.2.3(a)–(b) No scraping or caching:** don't store Google Maps Content (including "user reviews") beyond what the service-specific terms allow.
- **§3.2.3(e) No use with non-Google maps:** "Customer will not use the Google Maps Core Services with or near a non-Google Map in a Customer Application", for example "display or use Places content on a non-Google Map". The client app's Visit tab has an Apple map; Google's reviews are on a separate Reviews screen, and the Visit tab only links to it. Keep it that way: no Google reviews or rating on a screen with the Apple map.
- Google's Places policies also ask for author attribution, a link to each review and, recommended, a note on how reviews are sorted.

**Does it apply? Applies** when live Google reviews show.

**What the code does:** Google reviews are fetched live and never stored; the website and app show "Reviews from Google Maps", author names and links, Google's order ("Up to five reviews that Google picks, in Google's order"), and links to Google's terms and privacy policy (`server/web/src/pages/ReviewsPage.tsx`, `IzzyClipz/Features/Reviews/ReviewsView.swift`).

**What to do.** The Terms of Service carry the §3.2.2(a)(i) notice word for word in substance, and the Privacy Policy links Google's privacy policy.

### 12.2 Yelp

**The rules.**

- **Yelp's API Terms of Use** ([terms.yelp.com/developers/api_terms](https://terms.yelp.com/developers/api_terms/), last updated September 22, 2026):
  - Section 1: the API is made available "to enable you to access and present Yelp Content to on your consumer-facing content distribution platform (i.e. non-commercial uses, as defined below), including but not limited to your website and mobile apps".
  - Section 5: "'Non-commercial use' means any use of the Yelp Content which does not generate promotional or monetary value for the creator or the user, or such use does not gain economic value from the use of our content for the creator or user, i.e. you." Anyone "interested in commercial use of the Yelp Content" is sent to insights-api.yelp.com.
  - §5(c): don't "display or use Yelp user review ratings ... alongside or in conjunction with other user-generated content".
  - §5(d): don't "use Yelp Content for any commercial purpose without the express written consent of Yelp".
  - §5(a): don't store Yelp content for more than 24 hours.
  - Yelp's paid plans change call limits; the terms send anyone interested in commercial use to Yelp's commercial offering instead.
- **Yelp's Display Requirements** ([terms.yelp.com/developers/display_requirements](https://terms.yelp.com/developers/display_requirements/), read November 5, 2026), which are conditions of the API license:
  - "The following Yelp-branded stars sprite must be used when representing a Yelp rating. Generic or unbranded stars are not permitted."
  - Make Yelp's logo prominently visible on all content from Yelp, and make it link to Yelp.
  - Link directly to the Yelp pages whenever showing star ratings, review excerpts and review counts; include "read more" links.
  - Show aggregate star ratings side by side with the number of reviews.
  - Don't blend Yelp ratings with other sources, don't store data longer than 24 hours, and don't suggest that critical reviews can be removed.

**Does it apply? Applies** if Yelp reviews are shown. The terms can be read two ways: section 1 seems to treat showing Yelp content on a consumer-facing site as the permitted use, but the definition excludes any use that brings "promotional or monetary value" to the user of the API, and a shop's own website and app exist to promote the shop. Under that definition, showing the shop's Yelp reviews there is commercial use, which needs Yelp's written consent (§5(d)). The other rule is clearer: the website's Reviews page shows Yelp's rating on the same page as Google's reviews, and its home page shows both ratings in one tile, which §5(c) forbids. Attorney to confirm the reading; until Yelp consents in writing, the safe course is to keep Yelp reviews off.

**What the code does:** Yelp reviews show only when the server has a Yelp key (`YELP_API_KEY`, which needs a paid Yelp plan). Without one, the website and the app show a "Read our reviews on Yelp" link instead. With one, the 24-hour limit, links and review counts are done, but the rating uses generic stars, there's no Yelp logo, and Yelp's rating sits next to Google's.

**What to do.**

- **Must do before launch:** keep Yelp reviews off, with no Yelp key on the live server, and link to the shop's Yelp page instead. The documents are written that way: the Privacy Policy, the Terms and the Accessibility Statement say the website and apps show Google's reviews and link to Yelp.
- **If the owner wants Yelp reviews later:** first get Yelp's written consent for this use; then use Yelp's branded stars and logo, keep the Yelp rating off any screen or tile with Google's, and update the documents before turning them on. Add back to the Privacy Policy that reviewers' photos also load from Yelp's servers (in "Reviews", in the Do Not Track section and in "What our website loads"), that Yelp receives the visitor's IP address and browser details (with Yelp's privacy policy link), and that Yelp reviews are kept no more than 24 hours; to the Terms (sections 9 and 10) that the website and app show Yelp's reviews as Yelp provides them; and to the Accessibility Statement ("Content from other companies") that Yelp's reviews are shown as Yelp provides them.

---

## 13. Reviews: FTC Consumer Review Rule, Consumer Review Fairness Act, Civ. Code §1670.8

**The rules.**

- **FTC Trade Regulation Rule on the Use of Consumer Reviews and Testimonials** ([16 CFR Part 465](https://www.ecfr.gov/current/title-16/chapter-I/subchapter-D/part-465)), in force since **October 21, 2024**: bans fake reviews, buying reviews conditioned on their sentiment, undisclosed insider reviews, company-controlled "independent" review sites, suppressing reviews (for example by intimidation or by hiding negative ones on the business's own site), and fake social-media influence. **Recent:** on **December 22, 2025** the FTC sent its first warning letters under the rule to 10 companies, citing penalties of up to $53,088 per violation ([Arnold & Porter, Jan 2026](https://www.arnoldporter.com/en/perspectives/blogs/consumer-products-and-retail-navigator/2026/01/ftc-warning-letters-over-consumer-review-rule)).
- **Consumer Review Fairness Act** (15 U.S.C. §45b): form-contract clauses that restrict or penalize customers' honest reviews are void.
- **Civ. Code §1670.8** ([FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-1670-8/)): a consumer contract can't waive the right to make statements about the business, and the business can't threaten or penalize a consumer for making them.

**Does it apply? Applies.**

**What the code does:** shows Google's and Yelp's reviews in their own order, with no filtering by rating; asks happy clients for a Google review without any incentive.

**What to do.** The Terms say clients are free to review the shop honestly anywhere, that reviews aren't hidden because of their rating, and that the shop never pays for reviews or rewards positive ones. Owner checklist: never offer discounts or gifts for positive reviews, never post reviews for the shop yourself, and don't ask staff or family to.

---

## 14. Tracking lawsuits (CIPA) and Shine the Light

**CIPA (California Invasion of Privacy Act).** Plaintiffs have filed thousands of claims against websites that use chat widgets, pixels and analytics, under Penal Code §§631, 632, 632.7 and 638.51. **Recent:** SB 690 was signed on **September 30, 2026**. From January 1, 2027, private lawsuits under §638.51 ("pen register" and "trap and trace") over websites and apps are no longer allowed; only the Attorney General can sue. Private claims under §§631, 632 and 632.7 remain ([PPC Land, Oct 1, 2026](https://ppc.land/newsom-bans-one-kind-of-private-web-tracking-lawsuit-as-claims-near-4-000/); [Benesch](https://www.beneschlaw.com/insight/governor-newsom-signs-sb-690-california-eliminates-private-right-of-action-for-website-pen-register-and-trap-and-trace-claims-under-cipa/)).

**Does it apply? Low risk.** The website and apps load no analytics, pixels, chat widgets or trackers. Keep it that way, and get legal advice before adding any.

**Shine the Light** (Civ. Code §1798.83; [FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-1798-83/)): businesses that share personal information with third parties for their direct marketing must disclose it on request. Businesses with fewer than 20 employees are exempt. **Probably doesn't apply**, and the shop shares nothing for marketing. The Privacy Policy says so in one line.

---

## 15. Limits on what the Terms can say, and how disputes are handled

**The rules.**

- **Civ. Code §1668** ([FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-1668/)): contracts that exempt anyone from responsibility for their own fraud, willful injury to a person or property, or violation of law are against public policy.
- **Releases of future gross negligence** are unenforceable: *City of Santa Barbara v. Superior Court* (2007) 41 Cal.4th 747. Exculpatory clauses in contracts affecting the public interest are invalid: *Tunkl v. Regents of University of California* (1963) 60 Cal.2d 92.
- **CLRA** (Civ. Code §1751; [FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-1751/)): any waiver of the Consumers Legal Remedies Act's protections is void.
- **Public injunctive relief** can't be waived in every forum: *McGill v. Citibank, N.A.* (2017) 2 Cal.5th 945.
- **Arbitration:** enforceable in principle, but for a small shop it adds cost and complexity, invites challenges over formation and fairness, and gains little. Small claims court is fast and cheap for both sides.
- **Small claims limits** ([California Courts](https://selfhelp.courts.ca.gov/small-claims-california), checked November 5, 2026): up to **$12,500** for individuals and **$6,250** for businesses. Lawyers can't represent parties in court.
- **Consumer venue** ([Code Civ. Proc. §395, FindLaw](https://codes.findlaw.com/ca/code-of-civil-procedure/ccp-sect-395/)): in an action "arising from an offer or provision of goods, services, loans or extensions of credit intended primarily for personal, family or household use", the court in the county where the buyer signed the contract, lived when it was made, or lives when the action begins is a proper court (§395(b)); "Any provision of an obligation described in subdivision (b) waiving that subdivision is void and unenforceable" (§395(c)). A clause sending every dispute to San Diego County would be partly void against clients who live elsewhere, for example if the shop ever sued to collect a fee.

**Does it apply? Applies** to the Terms.

**What to do.** The Terms:

- keep "as is" disclaimers to the website and apps, and say plainly that they don't limit responsibility for services at the shop;
- limit liability for the website and apps to the greater of $100 or what the client paid for the appointment in question, with carve-outs for personal injury, fraud, willful harm, gross negligence, violations of law and non-waivable consumer rights (attorney to review the cap);
- set out an informal step first (call, 30 days to fix it), allow small claims, name the courts of San Diego County unless the law gives the client a court in another county (such as their own), choose California law, and use **no arbitration and no class waiver**;
- keep card-dispute rights intact.

---

## 16. Photos and names (right of publicity)

**The rule.** Civ. Code §3344 ([FindLaw](https://codes.findlaw.com/ca/civil-code/civ-sect-3344/)): using someone's name, photograph or likeness to advertise or sell, without their consent, makes the user liable for at least $750 or actual damages, plus profits and attorney's fees. For a minor, a parent or legal guardian must consent.

**Does it apply? Applies.** The gallery on the website and in the app shows six clients' faces, and at least one looks under 18. **They're already published:** the public demo (izzy-clipz.vercel.app) loads all six, and they're in the app builds. They came from the shop's older website, so whether the shop owns them, or has a license to use them, isn't confirmed. The barbers' names, titles, bios and Instagram handles also appear (with initials, not photos).

**What to do.**

- **Now:** take the photos of identifiable people off the public demo and out of the app builds, the apparent minor first, until signed releases exist, or replace them with photos that show no faces (the owner checklist's "Do this now" item). Removal only after someone asks isn't enough under §3344.
- **Before launch:** written permission from each person shown (from a parent or guardian for anyone under 18); confirm that the shop owns, or has a license to, every photo, since the Terms say the shop's photos belong to it or to its licensors; get each barber's OK to show their name, photo and bio, and remove them when they leave.
- **Privacy Policy:** says that a photo in which someone can be recognized is shown only with that person's consent (a parent's or guardian's for anyone under 18), and that anyone in one can ask for it to be taken down. It doesn't say the website or apps show such photos, so it stays true while the gallery is off.

---

## 17. Retention: what the documents promise

The AG's CalOPPA guide asks for a retention period for each category (§1), Apple asks the policy to explain retention and deletion (§11), and California's disposal law asks for real deletion (§5). Today nothing deletes clients' details or saved cards.

**The plan the documents use** (details and code changes in `data-inventory.md`, G1 and G2):

- **Contact details on appointments** (name, number, email, note): removed **12 months after the appointment**, except while a fee for it is still pending. The appointment stays as an anonymous record, so the analytics don't change.
- **Names on sales, and the descriptions of card payments taken at the shop:** removed after **12 months**. Receipt emails aren't kept at all (§9.3), and payment descriptions stop including the client's name (§18). The copies in the shop's Stripe account stay as long as Stripe keeps payment records, and the policy says so.
- **Fee evidence:** the agreed text, consent time, fee, status and card type and last 4 stay with the anonymous record, so the shop can still answer a card dispute. With fees charged within 7 days of the appointment and disputes usually allowed for 120 days (§9.1), 12 months covers the dispute window comfortably; a separate 18-month hold for fee records isn't needed.
- **Saved cards:** deleted at Stripe when the card expires, after 12 months without a booking, when the client removes it or asks, or, for a card saved without "Remember me", once its booking can no longer be charged; in each case once no booking still needs it. Detaching the card and deleting the Stripe Customer stops the card being charged, but doesn't remove the email from the shop's Stripe account: the completed Checkout Session keeps what the client typed on Stripe's page, and Stripe's API can't delete a Checkout Session (it can only create, update, retrieve, list and expire one). Stripe's Redaction Jobs (public preview, November 2026) can remove it from the shop's Dashboard and API, with limits (a payment only after 90 days; a redacted payment can't be refunded and loses any dispute); the shop hasn't adopted them, so the Privacy Policy says the Stripe records have no set end date. The policy says so instead of promising the email is deleted.
- **Already true today:** scrambled IP addresses about 2 days; Google content not stored (and the Yelp cache at most 24 hours, if Yelp reviews are ever turned on); the host logs the shop can see up to 30 days depending on the plan, while Vercel may keep some traffic information longer under its own Privacy Notice (it acts as a controller for some of it), which the policy says; database restore history up to 30 days depending on the plan.
- **Tax records:** sales totals and items stay (without names), which is what tax records need.

The periods are proposals for the owner to confirm (`OWNER-CHECKLIST.md`).

---

## 18. What the documents promise that the code must do first

The documents are written for the live version, and they're not in effect until it ships: their dates say "[TO FILL IN]". These promises aren't kept by the code yet. **All of them ship in one release together with the documents**, with tests that fail if any piece is missing; publishing the documents first would make them untrue on the day they go up.

1. **Publish the four policies and link them** on every page (live site and demo), in both apps and in the booking steps (CalOPPA §1, Apple §11, the fee notice §8.3). Add the four pages to the website's accessibility, phone-size and offline lists, and check that no "TO FILL IN" is left in them.
2. **Show the Terms and the Cancellation & No-Show Policy at booking**, directly above "Book appointment" (§8.4).
3. **Cap every fee at the booked service's price** (§8.2–8.3).
4. **Stop charging fees 7 days after the appointment** (§8.3 item 10, §9.2).
5. **A no-show only after the end time:** a booking with a card on file can be marked a no-show, and charged, only after its end time, and a completed one can't become a no-show (§8.3 item 12).
6. **The 15-minute grace period:** cancelling within 15 minutes of booking is never a late cancellation, for any booking; the booking screens mention it for a time already past the cutoff (§8.3 item 11).
7. **Remove clients' contact details after 12 months** with the daily job (§17).
8. **Delete saved cards** when they expire, go 12 months unused, or are removed, and once the booking is over for a card saved without "Remember me" (§17).
9. **Tools to answer privacy requests:** find, export, correct and delete one person's data (§3).
10. **"Remember me" starts unticked in the iPhone app** (§8.3 item 9).
11. **The line under the details form** says the details go to the shop "and the services that run its booking", not "only to" the shop (§1).
12. **The app opens the new website**, not the older Squarespace one, from its Website row, Share link and calendar events (§1, and "What the code shows").
13. **Yelp reviews stay off** (§12.2).
14. **Receipt emails only after the card payment, and not kept** (§9.3).
15. **No client name in Tap to Pay payment descriptions** (§17).
16. **The Business app's location question gives Stripe's real reason** (fraud and disputes), as the Privacy Policy now does (§9.1).
17. **The Visit page's accessibility lines say only what's been checked** (§10).
18. **Apple's Declared Age Range API in both apps** before January 1, 2027 (§4.2). This is a legal requirement rather than a promise of the documents, and the Privacy Policy's "Children" section changes when it ships.

The gallery photos are a separate, urgent step: they come off the public demo and out of the app builds now, not at launch (§16).

## 19. Recommended, but not promised by the documents

- Apple's age-assurance steps for Texas, Utah and Louisiana (§4.3).
- Accurate App Store privacy answers for both apps (§11).
- The fee notice says "is charged"; the agreed text says "may charge". Use "may be charged" in the notice too, and "online" rather than "in the app" in the stored text, for new bookings.
- Clear `sale_draft` once a sale is recorded.
- Use an HMAC with a server secret for the rate-limit IP hash; add a Content-Security-Policy and Permissions-Policy to the live site, as the demo has.
- Publish `/.well-known/gpc.json` (§2).
- Show a charged fee on the website's My appointments page, as the iPhone app does, and offer staff a ready-made text to tell the client.
- Accessibility audits in the iOS UI tests, and a test with a screen-reader user (§10).
- A "Remove everything from this iPhone" action that also removes past appointments and their keys.

## Changes after review (November 5, 2026)

Two independent reviews checked the drafts against the law and the code. Every finding was checked again before acting on it. What changed:

- **Not in effect until the code ships.** The four documents' dates are now "[TO FILL IN]", and the owner checklist and §18 tie publishing to the release that makes them true.
- **No-show fee:** a 15-minute grace period for bookings made after the cutoff has passed, a short "estimate, not a penalty" recital, a no-show fee only after the appointment's end time (matching the late-arrival rule), and a completed appointment that can't become a no-show (§8.3 items 11–13).
- **Privacy Policy:** the Do Not Track section now says Stripe's card page and Google can collect device details (§1, §2); providers are described one by one instead of all being "bound to this policy" (§11); Vercel's own log retention is acknowledged (§17); the developer is named as a recipient (§1); notification prompts, "Forget my details", the Keychain and "Remove from this list" are described as the app really works; saved cards without "Remember me" are deleted once their booking is over, and the Stripe email that can't be deleted is disclosed (§17); the older website and Squire are excluded by name; receipt emails are offered after payment and not kept (§9.3); the Tap to Pay location reason is Stripe's own.
- **Yelp:** its API terms describe the API as for non-commercial uses and bar Yelp ratings next to other reviews, so the documents assume Yelp reviews are off and only linked (§12.2).
- **Terms:** both price exceptions ("From" and "any barber"), a warning not to cancel online inside the cutoff to rebook, cancelling only on the device used to book, a refund line for the owner to fill in, the consumer's own county kept available (§15), and Apple's standard license agreement brought into "the whole agreement" (§11).
- **Accessibility Statement:** relay calls, texts (once confirmed) and email; the phone-size and High Contrast claims worded as the tests really check them; the Visit page's "ADA-compliant" line made a launch item (§10).
- **Owner checklist:** a "do this now" step for the gallery photos (§16); must-dos for the shop email, texts and relay, a refund policy, Yelp, the older website and Squire, a developer agreement, providers' data protection terms, no card fees, and the age signal.

### Later the same day: the 15-minute grace period for every booking

The server implements the grace period as the drafter's rule reads (a client cancellation counts as late only when it's after the cutoff and more than 15 minutes after booking), so it covers every booking, not only those made after the cutoff had passed. That's never stricter than the earlier wording, and simpler to explain, so the Cancellation & No-Show Policy, the Terms and the owner checklist now say "cancelling within 15 minutes of booking is always free".

## The owner's first answers (November 11, 2026)

The owner started answering the checklist page. What changed in the documents:

- **Legal name and type of business.** The owner chose "LLC" and wrote "Izzy Clipz Barbershop" as the legal name. A California LLC's name must contain "limited liability company", "LLC" or "L.L.C." (Corporations Code §17701.08(a)), so "Izzy Clipz Barbershop" alone is probably the shop's trade name rather than the LLC's registered name. Each document's first paragraph now says "Izzy Clipz Barbershop is operated by [TO FILL IN: the LLC's exact registered name], a limited liability company." The registered name, not a guess, goes there. Naming the business behind the shop also helps with Business and Professions Code §17538(d), which asks online sellers to disclose "the legal name under which the business is conducted" and its street address.
- **Texts.** The owner answered that (442) 341-3053 takes phone calls only. Every offer to text the shop is out of the Accessibility Statement, and so is "We can also text you the details", which could promise something the shop's line can't do. The statement still offers calls, relay calls (711), email and walking in. The other documents only say the shop *may* call or text a client about an appointment, which stays true.
- **Getting into the shop.** The owner confirmed "Room for a wheelchair inside, at the chairs and the counter" and "Accessible parking near the entrance", and didn't tick a step-free entrance. Those two lines go back on the Visit page (website and app) with the next release, and the "call us" line about getting in stays, so that someone who uses a wheelchair asks about the entrance before coming. The Accessibility Statement doesn't list the shop's features, so it doesn't change.

## Legal check (November 14, 2026)

Three independent reviewers checked the four documents against current California and federal law (privacy; terms and fees; accessibility), verifying time-sensitive points against primary sources on November 14, 2026. They found no blockers. What changed, and why:

**Fees (Cancellation & No-Show Policy, owner checklist).**
- *Civil Code §1671(d).* A fee in a consumer services contract is void unless the shop's loss was impracticable or extremely difficult to fix and the amount was a reasonable effort to estimate it, made before the amount was set; percentage-of-price fees and reasons given afterwards are treated with suspicion (*Cellphone Termination Fee Cases* (2011) 193 Cal.App.4th 298; *Ridgley v. Topa Thrift & Loan* (1998) 17 Cal.4th 970; *Del Monte Properties v. Dolan* (2018) 26 Cal.App.5th Supp. 20; *Munguia-Brown v. Equity Residential*, N.D. Cal. No. 16-cv-01225, orders of Aug. 12, 2019 and Apr. 8, 2024; *Bayol v. Zipcar* (N.D. Cal. 2015) 78 F.Supp.3d 1252). The "Why we have it" recital now says the fee is set from the shop's own records before it's turned on, the policy promises no late-cancellation fee when someone else takes the time, and the checklist asks for a dated written record each time the fee or cutoff changes, kept 4 years, plus the attorney's approval before no-show protection is turned on. A lower cap for long cutoffs is a recommended code change.
- *Visa Core Rules (October 24, 2026 edition).* A fee charged later to a saved card is an unscheduled credential-on-file transaction (Visa's "No-Show Transaction" type is only for lodging and rentals): it needs a receipt at the time of the charge, and after a decline the cardholder must be told in writing and given at least 7 days to pay another way. The policy now promises both; the receipt is a code change (owner checklist §3, item 19), because the server sends none today.
- *Disability.* 28 C.F.R. §36.302(a) and Civ. Code §51(f), §52(a): the policy now says a fee is waived, or another fair change made, when a missed or late-cancelled appointment was caused by a disability.
- *Email.* Since the shop's number takes calls only, email is the only written channel: bookings and cancellations by email now count the same as by phone, from the time sent (28 C.F.R. §36.303).

**Terms.**
- *Business and Professions Code §17538(d).* Before charging a card in an online transaction, a vendor must disclose its refund policy, legal name and street address, on the booking screens, with an adjacent line offering them by email (sent within 5 days). The Terms and the Cancellation & No-Show Policy now give the address and the email line in their first paragraph; the footer and "Review and book" are a code change (§3, item 20).
- *Civil Code §1670.15* (SB 82, Stats. 2025, ch. 350, in force January 1, 2026): dispute terms must be limited to the goods or services the agreement covers, so section 14 now starts with its scope.
- *Civil Code §1670.8.5* and Bus. & Prof. Code §101(h): a licensee's consumer contract can't limit complaints to the licensing board. "Talk to us first" is now optional, and the Terms say complaints to the Board of Barbering and Cosmetology aren't limited.
- *Civil Code §1668, §1751, §1770(a)(14), (19)*: the liability limit never reduces a refund of a fee or anything else paid.
- *Apple's standard license agreement* ($50 cap, injury exclusion, Santa Clara courts; read November 14, 2026): where it and the Terms differ, the one giving the client more rights applies, and the booking's own terms decide a fee.
- *Unruh Act* (Civ. Code §51(b), (e)(4), as amended by SB 1137, in force January 1, 2025): race includes hair texture and protective hairstyles, now named; and 16 Cal. Code Regs. §984 (no work on infected or broken skin, or with head lice), now a health line with no fee for a moved appointment.
- *Assistive technology*: the ban on automated tools is now a ban on bots and scripts, with assistive technology always welcome (42 U.S.C. §12182(b)(2)(A)).
- *SB 478* (Civ. Code §1770(a)(29); the Attorney General's FAQ): "From $80" for the lightener is a risk; the owner checklist asks for a range with a top price.
- *Civil Code §51.6*: the checklist gives the exact sign wording and the full price-list rule.

**Privacy Policy.**
- *Stripe's records*: the shop's Stripe account keeps payments, fees, receipt emails and the card page's email with no set end date; the policy now says so, in the deletion promise and the retention table (Stripe's Redaction Jobs are a public preview, docs.stripe.com/privacy/redaction, read November 14, 2026).
- *Retention*: calls, texts and emails with clients (deleted within 12 months) and notes of privacy requests (2 years) are now in the table (Apple guideline 5.1.1(i), last updated October 16, 2026; the Attorney General's *Making Your Privacy Practices Public*, May 2014).
- *Age range*: the Children section now describes Apple's Declared Age Range as Apple documents it: in some regions iOS shares automatically, with the region's own brackets, how the age was set and whether parental controls are on; the apps use only whether the person is under 13.
- *Receipt email*: "we don't keep it" now says the address stays with the payment in the shop's Stripe account (Civ. Code §1747.08; *Harrold v. Levi Strauss & Co.* (2015) 236 Cal.App.4th 1259).
- *Third parties*: each provider protects data with security at least as strong as the shop's (Apple guideline 5.1.1(i)); Stripe's November 20, 2026 privacy policy covers devices across websites and apps.
- *TCPA*: the FCC's revoke-all rule was narrowed, effective November 25, 2026 (91 FR 67214).
- Checked and current: CalOPPA, COPPA as amended (compliance April 22, 2026), SB 446's 30-day breach notice, Shine the Light, Google Maps Platform and Stripe terms. SB 923, AB 2561 and AB 2246 don't change the documents.

**Accessibility.**
- No Title III web rule yet; DOJ's 2022 guidance stands; the April 20, 2026 interim rule moved only Title II deadlines. *Robles* and *Martinez v. San Diego County Credit Union* still apply; Unruh's $4,000 minimum is unchanged; WCAG 2.2 is ISO/IEC 40500:2025 and WCAG 3 is still a draft. The 2026 bills that would have softened accessibility claims (SB 84, AB 649, AB 2190) died, so there is no cure period.
- The biggest risk is the building: the owner checklist now asks the owner to check the entrance and remove a step where readily achievable (28 C.F.R. §36.304), to get a CASp inspection, to match the Google, Yelp and Apple Maps listings to the Visit page, and to train staff on service animals (28 C.F.R. §36.302(c)) and Tap to Pay's accessible PIN entry. The Visit page's "Accessible parking" becomes "Disabled parking space", and its call line will offer relay calls and email (§3, item 21).
- The statement welcomes every kind of relay call, narrows "anything else you need" to "anything else about your visit", says what to do when the sign-in code runs out, and names the short labels that don't follow Dynamic Type. App Store Accessibility Nutrition Labels are ticked only after real testing.

**Questions for the attorney** (from the three reviews):
1. The barbers' pay arrangement, and whether a fee of up to 100% paid to the LLC is a reasonable estimate of the LLC's own loss; the highest late-cancellation fee and longest cutoff that can be defended; what the written record should contain.
2. Whether §17538(d) applies to free online bookings whose only online charge is a later fee, and where the disclosures belong (website, app); whether the Electronic Commerce Act notice (Civ. Code §1789.3) applies.
3. "From $80" under SB 478; SB 82's reach beyond arbitration; a custom license agreement for the iPhone app instead of Apple's standard one.
4. Whether the consent line above "Book appointment" is enough after *Cruz v. Tapestry* (2025) 113 Cal.App.5th 943, or bookings with a card on file need an unticked "I agree" box.
5. Fee waivers for disability; the health line under the ADA's direct-threat rule (28 C.F.R. §36.208); counting email cancellations from the time sent.
6. Age signals: whether a 13–17 signal should stop a minor from adding a card (the 18+ rule), and whether asking on iOS 26.0–26.1 is acceptable under AB 1856; whether AB 2246 (from January 1, 2027) reaches a shop this size.
7. Stripe redaction for deletion requests and old records; the email Stripe's card page requires under Song-Beverly (*Apple Inc. v. Superior Court* (2013) 56 Cal.4th 128); the 12-month and 2-year retention periods; Apple's 5.1.1(i) wording.
8. The entrance: what's readily achievable, who pays under the lease (28 C.F.R. §36.201(b)), staff help as an alternative meanwhile (§36.305); a CASp inspection now; whether to keep the statement's specific list of known gaps; insurance for access claims.
