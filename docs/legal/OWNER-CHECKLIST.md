# Owner checklist for the legal documents

**For:** Izzy and whoever helps run the shop's website and apps\
**Prepared:** November 5, 2026

This folder has four documents for clients: the [Privacy Policy](privacy.md), the [Terms of Service](terms.md), the [Cancellation & No-Show Policy](cancellation-policy.md) and the [Accessibility Statement](accessibility.md). They're written for the live version of the website and apps, and they also say how the demo differs.

**They're drafts, not legal advice.** They're based on the research in [research.md](research.md) and on what the code really does ([data-inventory.md](data-inventory.md)). Work through this list before they go live.

## 1. Before going live: must do

- [ ] **Have a California attorney review the four documents. This is strongly recommended.** Ask them to look in particular at:
  - the no-show and late-cancellation fee: whether the amount you choose (100% of the price by default) and the cutoff hold up under California's rule for fees in consumer contracts (Civil Code §1671), and whether to add an "I agree" checkbox;
  - the limit on liability in the Terms (section 13), and the choice of no arbitration;
  - the retention periods (12 months) and the request process in the Privacy Policy;
  - California's new age-signal law for apps, which starts January 1, 2027 (see section 4 below);
  - whether the shop meets any of the CCPA thresholds (you'd need yearly revenue over $26,625,000, so almost certainly not).
- [ ] **Add the shop's legal name and type of business**, for example "Izzy Clipz Barbershop is operated by [legal name], a California [LLC / corporation / sole proprietorship]." Put it in the first paragraph of each of the four documents, and use the same name in Stripe and App Store Connect.
- [ ] **Get an email address for the shop**, used only for shop business (not anyone's personal email). Add it to the "Contact us" part of each document, to "How to ask" in the Privacy Policy and to "Tell us about a problem" in the Accessibility Statement. Until then, the documents work with the phone number, in person and by mail.
- [ ] **Decide who answers requests**, and who covers when they're away. The documents promise:
  - privacy requests: confirm within 10 business days, answer within 45 days;
  - accessibility problems: a reply within 5 business days, and booking by phone right away;
  - questions about a fee: a reply within 5 business days;
  - photo takedowns: off the website as soon as possible, out of the app in its next update.
- [ ] **Confirm the decisions in section 2**, or tell your developer what to change.
- [ ] **Make sure the code changes in section 3 are done.** The documents promise them.
- [ ] **Set the dates.** The documents are dated November 5, 2026. If they go live on a later day, change "Effective date" and "Last updated" at the top of each one to the go-live date.

## 2. Decisions to confirm

| Decision | What the documents say now | Where |
|---|---|---|
| How long clients' details are kept | Name, number, email and note are removed 12 months after the appointment | Privacy Policy |
| How long saved cards are kept | Until the card expires, goes 12 months without a booking, or the client removes it | Privacy Policy, Cancellation & No-Show Policy |
| The fee amount | What you set in the app: a percentage of the service's price (100% unless you lower it) or a set amount, **never more than the service's price** | Cancellation & No-Show Policy |
| The cutoff for free cancelling | What you set in the app: 1 hour unless you change it (30 minutes to 48 hours) | Cancellation & No-Show Policy |
| Late cancellations | Charged like a no-show, unless you turn late cancellations off in the app | Cancellation & No-Show Policy |
| The deadline to charge a fee | Within 7 days after the appointment, or not at all | Cancellation & No-Show Policy |
| Cancelling by phone | Free whenever the shop cancels, including when a client calls before the appointment starts. (The system can't charge a booking the shop cancelled.) | Cancellation & No-Show Policy, Terms |
| Late arrivals | Arriving after the appointment time has ended counts as a no-show; otherwise you fit them in if you can | Cancellation & No-Show Policy, Terms |
| Telling clients about a fee | You'll text or call them when you charge it | Cancellation & No-Show Policy |
| Ages | Under 13: a parent or guardian books. To add a card: 18 or older | Terms, Privacy Policy, Cancellation & No-Show Policy |
| "From" prices | For a service whose price depends on the work (like the lightener), the barber gives the final price before starting | Terms |
| Gift cards | No expiry, no fees, cash back under $15 on request (California law) | Terms |
| Limit on liability for the website and apps | The greater of $100 or what the client paid for that appointment, with the exceptions the law requires | Terms |
| "Remember me" in the iPhone app | It's on unless the client turns it off (on the website it starts off). The documents describe both. Research suggests starting it off in the app too. | Privacy Policy |

**Write down why you chose the fee amount, and keep the note.** For example: "When a client doesn't come or cancels within an hour, the barber's chair usually stays empty, because it's too late to book someone else." If a client ever challenges the fee, the question is whether it was a reasonable estimate of the shop's loss when you set it. Long cutoffs at 100% (say, 24 hours or more) are harder to defend than short ones, because a slot cancelled a day ahead can often be filled.

## 3. Code changes the documents depend on

Your developer has the exact details. In plain words:

1. **Put the four documents on the website** (live and demo), with links at the bottom of every page, inside both iPhone apps, and next to the fee notice in the booking steps.
2. **Show "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy"**, with links, just above the "Book appointment" button, on the website and in the app.
3. **Never let the fee be more than the price of the service** (today the set-amount option can charge $20 on a $5 service).
4. **Stop fees from being charged more than 7 days after the appointment.**
5. **Remove clients' names, numbers, emails and notes automatically** 12 months after the appointment.
6. **Delete saved cards at Stripe** when they expire, go 12 months unused, or the client removes them.
7. **Simple tools to find, correct and delete one person's information** when they ask, including a copy of the cancellation terms they agreed to.

**Recommended, but not promised by the documents:**

- Show Yelp's own star images and logo with Yelp reviews (Yelp's rules don't allow generic stars), or hide the Yelp section until then.
- Before January 1, 2027, have both iPhone apps ask the iPhone for the user's age range (Apple's age tools), as California's new law requires.
- Start "Remember me" off in the iPhone app, as on the website.
- Say "may be charged" in the fee notice (the agreed terms say "may charge"), and "online" instead of "in the app" in the terms for new bookings.
- Leave the client's name out of card payment descriptions sent to Stripe.
- Small security improvements: a secret in the rate-limit scrambling, and the same security headers on the live site as on the demo.
- Show a charged fee under My appointments on the website, as the app does, and give staff a ready-made text to tell the client.
- Add accessibility checks to the iPhone apps' tests, and have someone who uses a screen reader try booking.

## 4. Accounts and settings

### Stripe

- [ ] The Stripe account is in the shop's legal name.
- [ ] **Public details:** business name, support phone (442) 341-3053, the shop's email, address, website, and the links to the Terms of Service and Privacy Policy.
- [ ] **Statement descriptor:** something clients will recognize on their card statement, like "IZZY CLIPZ".
- [ ] **Email receipts:** decide whether Stripe emails receipts for successful payments. If it's on, clients who saved a card also get a receipt when a fee is charged.
- [ ] **PCI:** complete Stripe's yearly PCI self-assessment in the Stripe Dashboard. Never write down or store anyone's card number.
- [ ] Know how to refund a fee charged by mistake (Stripe Dashboard, Payments, Refund).

### Hosting and other services

- [ ] **Use a paid Vercel plan for the live version.** Vercel's free Hobby plan is for non-commercial use only.
- [ ] The accounts for Vercel, Neon, Stripe, Apple Developer, Google Cloud (the reviews key), Yelp and GitHub belong to the shop, or the shop has owner access to each.
- [ ] Vercel's, Neon's and Stripe's data protection terms apply to the shop's accounts (the Privacy Policy says these providers are bound to protect clients' information).
- [ ] Keep the database's restore history at 30 days or less, and don't keep hosting logs longer than 30 days. The Privacy Policy promises both.

### App Store Connect (both apps)

- [ ] Publish the apps under the shop's own Apple Developer account, so the seller's name matches the documents.
- [ ] Enter the Privacy Policy's web address for each app.
- [ ] Fill in the App Privacy answers accurately:
  - **Izzy Clipz:** Name, Phone Number, Payment Info, Other User Content, and Email Address (Stripe's card page asks for one).
  - **Izzy Clipz Business:** Coarse Location and Product Interaction (Stripe's Tap to Pay software), Photos or Videos (product photos), and Name, Phone Number, Email Address and Other User Content (clients' details staff enter).
- [ ] Answer the age rating questions, and add a support contact.
- [ ] Make the apps available in the United States only, unless you plan otherwise.
- [ ] **Before January 1, 2027:** the age-range change in section 3 is in both apps.

## 5. In the shop

- [ ] **Post the price list and the sign California requires in barbershops** (Civil Code §51.6): the prices of your most requested services in at least 14-point bold type, and a sign in at least 24-point bold type saying that California law prohibits pricing based on gender and that a complete price list is available on request. Use the exact wording in the law.
- [ ] **Keep prices based on the service, the time and the work**, never on gender.
- [ ] **Gift cards:** no expiry dates, no fees, and cash back on request when less than $15 is left.
- [ ] **Gallery photos:** the six photos on the website and in the app show clients' faces, and at least one looks under 18. Get written permission from each person (from a parent or guardian for anyone under 18), or replace the photos.
- [ ] **Barbers:** get each barber's OK to show their name, bio and Instagram, and take them off when they leave.
- [ ] **The shop's accessibility details:** the Visit page says "Wheelchair accessible", "ADA-compliant entrance" and "Accessible parking near the entrance". Make sure each is true. "ADA-compliant" is a legal claim: unless an inspection backs it up, change it to a plain description such as "step-free entrance".
- [ ] **Consider a CASp inspection** (a Certified Access Specialist checks the premises). In California it gives the shop extra protection if anyone sues over physical access.
- [ ] **Service animals are welcome** (the Accessibility Statement says so).
- [ ] **The shop's older website** (izzyclipzbarbershop.net), which the app opens, isn't covered by these documents. Give it its own privacy policy, or stop linking to it.

## 6. Running the no-show policy day to day

- **You decide each time** whether to charge. Treat everyone the same way: if you waive the fee for one emergency, waive it for similar ones.
- **Charge within 7 days** of the appointment, or not at all.
- **When you charge a fee, text or call the client** (the Text and Call buttons are on the appointment). The policy promises this.
- **When a client calls before their appointment to cancel, cancel it in the app.** There's no fee when the shop cancels. Don't leave it and mark it as a no-show.
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
  - start collecting anything new, or use a new outside service with clients' information.
- **When the website moves to the shop's own web address**, update the links in App Store Connect and Stripe.
- **Whenever the code changes how it stores, sends or deletes information**, have your developer update [data-inventory.md](data-inventory.md) and check the Privacy Policy still matches.
