# Owner checklist for the legal documents

**For:** Izzy and whoever helps run the shop's website and apps\
**Prepared:** November 5, 2026, and revised the same day after two independent reviews

This folder has four documents for clients: the [Privacy Policy](privacy.md), the [Terms of Service](terms.md), the [Cancellation & No-Show Policy](cancellation-policy.md) and the [Accessibility Statement](accessibility.md). They're written for the live version of the website and apps, and they also say how the demo differs.

**They're drafts, not legal advice.** They're based on the research in [research.md](research.md) and on what the code really does ([data-inventory.md](data-inventory.md)). Have a California attorney review them before they go live.

**They're not in effect yet.** They describe the website and apps as they'll be once the code changes in section 3 are made. Publish them only in the same release as those changes, never before. Everything marked "[TO FILL IN: ...]" in them, including the dates at the top, must be filled in (or the line deleted, where the note says so) before they go live.

## 0. Do this now

- [ ] **Take the gallery photos off the public demo and out of the app builds.** The six gallery photos show clients' faces, and the first one appears to show someone under 18. They're live on the public demo (izzy-clipz.vercel.app) and inside the app builds, including the test builds. California law (Civil Code §3344) requires each person's consent, or a parent's or guardian's for a minor, before their photo is used to promote a business. Ask your developer to remove them, or swap in photos that show no faces, and to put the demo back up without them now. A photo of a person goes back only once you have that person's signed permission.

## 1. Before going live: must do

- [ ] **Have a California attorney review the four documents. This is strongly recommended.** Ask them to look in particular at:
  - the no-show and late-cancellation fee: whether the amount (100% of the price by default) and the cutoff hold up under California's rule for fees in consumer contracts (Civil Code §1671), the "agreed estimate of that loss, not a penalty" wording, the 15-minute grace period for bookings made after the cutoff has passed, the rule that a no-show fee is charged only after the appointment's end time, and whether to add an "I agree" checkbox;
  - the limit on liability (Terms, section 13), the choice of no arbitration, the courts clause (section 14), and how the Terms fit with Apple's standard license agreement for the iPhone app (section 17), or whether to give the app a custom license agreement instead;
  - the refund policy you choose (Terms, section 4);
  - the retention periods (12 months) and the request process in the Privacy Policy;
  - asking for a receipt email when a client pays by card at the counter (California's Song-Beverly Credit Card Act, Civil Code §1747.08);
  - the written agreement with your developer (below);
  - California's new age-signal law for apps, which starts January 1, 2027 (below);
  - whether the shop meets any of the CCPA thresholds (you'd need yearly revenue over $26,625,000, so almost certainly not).
- [ ] **Add the shop's legal name and type of business**, for example "Izzy Clipz Barbershop is operated by [legal name], a California [LLC / corporation / sole proprietorship]." Put it in the first paragraph of each of the four documents, and use the same name in Stripe and App Store Connect.
- [ ] **Get an email address for the shop**, used only for shop business (not anyone's personal email), and put it wherever the documents say "[TO FILL IN: the shop's email address]". The documents can't go live without it: the Accessibility Statement must offer ways to reach the shop other than a voice call, Stripe's receipts show a support email, and Apple asks for a support contact.
- [ ] **Texts and relay calls.** The Accessibility Statement says clients can text (442) 341-3053. Keep those lines only if that number takes texts and someone reads them during opening hours; otherwise delete them. Tell everyone who answers the phone that calls through a relay service (711) are welcome: answer them like any other call, and don't hang up on the relay operator.
- [ ] **Choose a refund policy** (section 2) and write it into the Terms (section 4, "Refunds"). Stripe expects a refund and dispute policy on the website. If the shop doesn't give full refunds or exchanges on products for at least 7 days, also post the product policy at the counter (Civil Code §1723).
- [ ] **Photos: permission and ownership.** Before any gallery photo of a person goes back on the website or in the apps, get written permission from each person shown (from a parent or guardian for anyone under 18), or use photos that show no faces. The Privacy Policy says that a photo in which someone can be recognized is shown only with that person's permission. Also confirm the shop owns, or has permission to use, every photo: they came from the shop's older website, and the Terms say the shop's photos belong to the shop or to the people who license them to it.
- [ ] **The shop's accessibility details on the Visit page:** "Wheelchair accessible", "ADA-compliant entrance" and "Accessible parking near the entrance". Check each one. "ADA-compliant" is a legal claim that no inspection backs up: replace it with a plain description of what's there (for example "Step-free entrance"), and remove anything you can't confirm. The Accessibility Statement points to the Visit page, so this must be done before it goes live.
- [ ] **Yelp reviews stay off.** Yelp's API terms (last updated September 22, 2026) describe the API as being for "non-commercial uses", which they define as use that brings no promotional or money value, and they don't allow Yelp ratings next to other reviews. The shop's own website and app are there to promote the shop, and today they show Yelp's rating next to Google's. So the documents say the website and apps show Google's reviews and only link to Yelp. Make sure the live server has no Yelp key (`YELP_API_KEY` unset). If you'd like Yelp reviews later, first get Yelp's written permission, use Yelp's own stars and logo, keep Yelp's rating away from Google's, and update the Privacy Policy, the Terms and the Accessibility Statement before turning them on (research.md §12.2 says what to add).
- [ ] **The older website and Squire.** The iPhone app links to the shop's older website (izzyclipzbarbershop.net, on Squarespace), whose booking button goes to the shop's old booking page on Squire. Have your developer point the app at the new website instead (section 3). Then decide what happens to the older website and the Squire page: closing them, or sending visitors to the new website, is best. The Privacy Policy ("Who we are") and the Terms (section 1) say they're not covered. If you close both, or the address izzyclipzbarbershop.net moves to the new website, delete those sentences.
- [ ] **A written agreement with your developer.** The developer can reach clients' information: the database, the server's settings and keys, and the shop's Stripe account. The Privacy Policy says the developer may use that access only to keep things working, fix problems and carry out clients' requests. Put that in writing: confidentiality, security, use only for the shop, telling you straight away about any breach, and returning or deleting the shop's data and keys when the work ends. Your attorney can give you a short template.
- [ ] **Own the accounts.** The accounts for Vercel, Neon, Stripe, Apple Developer, Google Cloud (the reviews key) and GitHub should belong to the shop, with your developer invited as a member, or at least the shop should have owner access to each. When the developer's work ends, remove their access and change the owner key.
- [ ] **Data protection terms with Vercel and Neon.** The Privacy Policy says they process clients' information under data protection terms that require them to keep it secure and use it only to provide their services. Vercel's Data Processing Addendum applies to its Pro and Enterprise plans (see section 4). Confirm that Neon's applies to the shop's database (Neon's terms point to its Data Processing Addendum). Keep a copy of each.
- [ ] **No card fees at the counter.** The Terms promise there are no booking fees or other required charges on top of the price. Confirm the shop never adds a card fee or any other extra charge when ringing up a client, including as a custom checkout item. If you ever want one, ask your attorney first and update the Terms and the prices shown.
- [ ] **Age range in both iPhone apps, from January 1, 2027.** California's Digital Age Assurance Act (AB 1043, as amended by AB 1856) requires apps to ask the device for the user's age range when the app is downloaded and launched. Any version of the apps available on or after January 1, 2027 must do it (section 3). The Attorney General can seek up to $2,500 per affected child, or $7,500 if it's intentional. When it's built, update the Privacy Policy's "Children" section: what the app asks for, that it isn't stored, and what happens for someone under 13.
- [ ] **Decide who answers requests**, and who covers when they're away. The documents promise:
  - privacy requests: confirm within 10 business days, answer within 45 days;
  - accessibility problems: a reply within 5 business days, and booking for the client right away by phone (or as soon as you see their text or email);
  - questions about a fee: a reply within 5 business days;
  - photo takedowns: off the website as soon as possible, out of the app in its next update.
- [ ] **Confirm the decisions in section 2**, or tell your developer what to change.
- [ ] **Make sure every code change in section 3 is done, tested and released together with the documents.** The documents promise them.
- [ ] **Fill in the dates on the day the release goes live.** Replace each "[TO FILL IN: ...]" date at the top of the four documents with that day. Nothing marked "TO FILL IN" may be left in them when they go live.

## 2. Decisions to confirm

| Decision | What the documents say now | Where |
|---|---|---|
| How long clients' details are kept | Name, number, email and note are removed 12 months after the appointment | Privacy Policy |
| How long saved cards are kept | With "Remember me": until the card expires, goes 12 months without a booking, or the client removes it. Without it: until the booking it was saved for can no longer be charged (7 days after the appointment at the latest) | Privacy Policy, Cancellation & No-Show Policy |
| "Remember me" | Starts off on the website and in the iPhone app, unless that phone or computer already remembers the client | Privacy Policy, Cancellation & No-Show Policy |
| The fee amount | What you set in the app: a percentage of the service's price (100% unless you lower it) or a set amount, **never more than the service's price** | Cancellation & No-Show Policy |
| The cutoff for free cancelling | What you set in the app: 1 hour unless you change it (30 minutes to 48 hours) | Cancellation & No-Show Policy |
| Late cancellations | Charged like a no-show, unless you turn late cancellations off in the app | Cancellation & No-Show Policy |
| Booking after the cutoff has passed | Cancelling within 15 minutes of booking is free; after that, it's a late cancellation | Cancellation & No-Show Policy, Terms |
| No-shows and late arrivals | A client who arrives before the appointment's end time isn't a no-show, and you fit them in if you can. A no-show fee can be charged only after the end time | Cancellation & No-Show Policy, Terms |
| A client who came | Never charged a no-show fee: once an appointment with a card on file is marked completed, it can't become a no-show | Cancellation & No-Show Policy |
| The deadline to charge a fee | Within 7 days after the appointment, or not at all | Cancellation & No-Show Policy |
| Cancelling or changing by phone | Free whenever the shop cancels or moves an appointment, including when a client calls before it starts. (The system can't charge a booking the shop cancelled.) | Cancellation & No-Show Policy, Terms |
| Telling clients about a fee | You'll text or call them when you charge it | Cancellation & No-Show Policy |
| Ages | Under 13: a parent or guardian books. To add a card: 18 or older | Terms, Privacy Policy, Cancellation & No-Show Policy |
| "From" prices | For a service whose price depends on the work (like the lightener), the barber gives the final price before starting, and the client can say no without a fee | Terms |
| "Any barber" prices | Where barbers' prices differ (Haircut & Beard is $55 or $60), the booking screens show the range and the client pays the price of the barber who takes the booking | Terms |
| **Refunds (to decide)** | Nothing yet: the Terms say "[TO FILL IN]". Decide what happens if a client isn't happy with a service (for example "tell us within [X] days and we'll fix it at no charge", or "we decide case by case"), and your policy for products. The Terms already say card refunds go back to the card | Terms |
| Gift cards | No expiry, no fees, cash back under $15 on request (California law) | Terms |
| Limit on liability for the website and apps | The greater of $100 or what the client paid for that appointment, with the exceptions the law requires | Terms |
| Reviews | Google's reviews are shown; Yelp is only linked | Privacy Policy, Terms, Accessibility Statement |
| Receipt emails at the counter | Offered only after the card payment goes through, never needed to pay, passed to Stripe and not kept | Privacy Policy |

**Write down why you chose the fee amount, and keep the note.** For example: "When a client doesn't come or cancels within an hour, the barber's chair usually stays empty, because it's too late to book someone else." If a client ever challenges the fee, the question is whether it was a reasonable estimate of the shop's loss when you set it. Long cutoffs at 100% (say, 24 hours or more) are harder to defend than short ones, because a slot cancelled a day ahead can often be filled. The 15-minute grace period is there for the same reason: when someone books a time after the cutoff has passed and cancels straight away, the shop has lost nothing, because the time was free a moment earlier.

## 3. Code changes the documents depend on

Your developer has the exact details (research.md §18 lists them). **Ship them all in one release, together with the four documents, and don't publish the documents before.** Add tests that fail if any of them is missing. In plain words:

1. **Put the four documents on the website** (live and demo), with links at the bottom of every page, inside both iPhone apps, and next to the fee notice in the booking steps. Include the new pages in the website's accessibility, phone-size and offline checks, and check that nothing marked "TO FILL IN" is left in them.
2. **Show "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy"**, with links, just above the "Book appointment" button, on the website and in the app.
3. **Never let the fee be more than the price of the service** (today the set-amount option can charge $20 on a $5 service).
4. **Stop fees from being charged more than 7 days after the appointment.**
5. **No-shows only after the end time:** a booking with a card on file can be marked a no-show, and charged, only after its end time; and once it's marked completed, it can't become a no-show.
6. **The 15-minute grace period:** a client who books a time after the cutoff has passed can cancel free for 15 minutes, and the booking screens say so.
7. **Remove clients' names, numbers, emails and notes automatically** 12 months after the appointment.
8. **Delete saved cards at Stripe** when they expire, go 12 months unused, or the client removes them, and once the booking is over for a card saved without "Remember me".
9. **Simple tools to find, correct and delete one person's information** when they ask, including a copy of the cancellation terms they agreed to.
10. **Start "Remember me" off in the iPhone app**, as on the website.
11. **Change the line under the details form** to "Your details go to Izzy Clipz Barbershop and the services that run its booking, as our Privacy Policy explains."
12. **Point the app's "Website" row, its Share link and its calendar events at the new website**, not the older one.
13. **Keep Yelp reviews off** (no Yelp key on the live server).
14. **Receipt emails at the counter:** ask only after the card payment has gone through, send the address to Stripe, and don't keep it.
15. **Leave the client's name out of card payment descriptions** sent to Stripe.
16. **Reword the Business app's location question:** Stripe needs the location to reduce fraud and disputes (not "card networks require it").
17. **Fix the Visit page's accessibility lines** (section 1).
18. **Ask for the user's age range in both apps** before January 1, 2027.

**Recommended, but not promised by the documents:**

- Say "may be charged" in the fee notice (the agreed terms say "may charge"), and "online" instead of "in the app" in the terms for new bookings.
- Small security improvements: a secret in the rate-limit scrambling, and the same security headers on the live site as on the demo.
- Show a charged fee under My appointments on the website, as the app does, and give staff a ready-made text to tell the client.
- Add accessibility checks to the iPhone apps' tests, and have someone who uses a screen reader try booking.
- A "Remove everything from this iPhone" action in the app, which also removes past appointments and their keys.

## 4. Accounts and settings

### Stripe

- [ ] The Stripe account is in the shop's legal name.
- [ ] **Public details:** business name, support phone (442) 341-3053, the shop's email, address, website, and the links to the Terms of Service and Privacy Policy. Stripe's receipts need a support email and a privacy policy link.
- [ ] **Statement descriptor:** something clients will recognize on their card statement, like "IZZY CLIPZ".
- [ ] **Email receipts:** decide whether Stripe emails receipts for successful payments. If it's on, clients who saved a card also get a receipt when a fee is charged.
- [ ] **PCI:** complete Stripe's yearly PCI self-assessment in the Stripe Dashboard. Never write down or store anyone's card number.
- [ ] Know how to refund a fee charged by mistake (Stripe Dashboard, Payments, Refund).
- [ ] **Who sits between the shop and its Stripe account.** The server can use the shop's own Stripe key ("direct mode"), or connect the shop's account through your developer's Stripe platform (Stripe Connect). With Connect, the developer's platform can act on the shop's account, so the developer agreement in section 1 must cover it. Using the shop's own key, set by the shop, keeps that access with the shop.

### Hosting and other services

- [ ] **Use a paid Vercel plan for the live version.** Vercel's free Hobby plan is for non-commercial use only, and its Data Processing Addendum covers the Pro and Enterprise plans.
- [ ] Keep the database's restore history at 30 days or less, and keep the hosting logs you control (Vercel's runtime logs, and any log drain you add) at 30 days or less. The Privacy Policy promises both.
- [ ] Leave `YELP_API_KEY` unset on the live server (section 1).

### App Store Connect (both apps)

- [ ] Publish the apps under the shop's own Apple Developer account, so the seller's name matches the documents.
- [ ] Enter the Privacy Policy's web address for each app.
- [ ] Fill in the App Privacy answers accurately:
  - **Izzy Clipz:** Name, Phone Number, Payment Info, Other User Content, and Email Address (Stripe's card page asks for one).
  - **Izzy Clipz Business:** Coarse Location and Product Interaction (Stripe's Tap to Pay software), Photos or Videos (product photos), and Name, Phone Number, Email Address and Other User Content (clients' details staff enter).
- [ ] Answer the age rating questions, and add a support contact (the shop's email).
- [ ] Make the apps available in the United States only, unless you plan otherwise.
- [ ] **Before January 1, 2027:** the age-range change in section 3 is in both apps.

## 5. In the shop

- [ ] **Post the price list and the sign California requires in barbershops** (Civil Code §51.6): the prices of your most requested services in at least 14-point bold type, and a sign in at least 24-point bold type saying that California law prohibits pricing based on gender and that a complete price list is available on request. Use the exact wording in the law.
- [ ] **Keep prices based on the service, the time and the work**, never on gender.
- [ ] **Gift cards:** no expiry dates, no fees, and cash back on request when less than $15 is left.
- [ ] **Card payments:** never require a ZIP code, phone number or email to take a card. Offer an email receipt only after the payment has gone through, and only for the receipt.
- [ ] **Barbers:** get each barber's OK to show their name, bio and Instagram, and take them off when they leave.
- [ ] **Consider a CASp inspection** (a Certified Access Specialist checks the premises). In California it gives the shop extra protection if anyone sues over physical access.
- [ ] **Service animals are welcome** (the Accessibility Statement says so), and so are calls through a relay service (711).

## 6. Running the no-show policy day to day

- **You decide each time** whether to charge. Treat everyone the same way: if you waive the fee for one emergency, waive it for similar ones.
- **Don't mark anyone a no-show before their appointment's end time.** A client who arrives before the end isn't a no-show: fit them in if you can, or move them to another time.
- **Charge within 7 days** of the appointment, or not at all.
- **When you charge a fee, text or call the client** (the Text and Call buttons are on the appointment). The policy promises this.
- **When a client calls before their appointment to cancel, cancel it in the app.** When they call to change it, move it for them (book the new time, then cancel the old one in the app). There's no fee when the shop cancels. Don't leave it and mark it as a no-show.
- **Never change a completed appointment to a no-show.**
- **If a client disagrees with a fee,** listen, check, refund it in Stripe if it was a mistake, and reply within 5 business days.
- **If the card is declined,** you can ask the client to pay the fee at the shop.

## 7. Handling requests and problems

### Privacy requests (a copy, a correction or deletion)

1. Write down the date and what was asked.
2. Check it's really them: their name, mobile number and a detail of one of their appointments, then call or text the number on file.
3. Confirm you've received it within 10 business days.
4. Ask your developer to run the privacy tools (find, correct, or delete).
5. Answer within 45 days. If you need more time, tell them why (up to 45 more days).
6. Keep a short note of each request (date, what was asked, what you did) for 2 years.

### Data breaches

If you think someone got into the shop's systems (for example, a lost iPhone with the Business app, a leaked owner key, or a computer you don't recognize in the signed-in list):

1. Change the owner key and sign out every computer.
2. Call your developer and your attorney the same day.
3. If clients' information was affected, California law may require telling them within 30 days. Your attorney will tell you what to send.

### Messages and reviews

- **Only text or call clients about their appointments.** No promotional texts or emails without written permission and a legal check first.
- **Never offer anything in return for reviews**, don't post reviews of the shop yourselves, and don't ask staff or family to.

## 8. Keeping the documents up to date

- **Review all four documents at least once a year**, and change the "Last updated" date when you edit them.
- **Update them, and ask your attorney, before** you:
  - send reminders by text or email, or any marketing;
  - add analytics, ads, social media pixels or chat widgets to the website or apps;
  - add client accounts or logins;
  - take payments online for services or sell products online;
  - change how the no-show fee works;
  - show Yelp reviews;
  - start collecting anything new, or use a new outside service with clients' information.
- **When the website moves to the shop's own web address**, update the links in App Store Connect and Stripe.
- **Whenever the code changes how it stores, sends or deletes information**, have your developer update [data-inventory.md](data-inventory.md) and check the Privacy Policy still matches.
