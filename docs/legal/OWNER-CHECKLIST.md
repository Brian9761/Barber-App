# Owner checklist for the legal documents

**For:** Izzy and whoever helps run the shop's website and apps\
**Prepared:** November 5, 2026, and revised the same day after two independent reviews

This folder has four documents for clients: the [Privacy Policy](privacy.md), the [Terms of Service](terms.md), the [Cancellation & No-Show Policy](cancellation-policy.md) and the [Accessibility Statement](accessibility.md). They're written for the live version of the website and apps, and they also say how the demo differs.

**They're drafts, not legal advice.** They're based on the research in [research.md](research.md) and on what the code really does ([data-inventory.md](data-inventory.md)). Have a California attorney review them before they go live.

**They're not in effect yet.** They describe the website and apps as they'll be once the code changes in section 3 are made. Publish them only in the same release as those changes, never before. Everything marked "[TO FILL IN: ...]" in them, including the dates at the top, must be filled in (or the line deleted, where the note says so) before they go live.

## 0. Do this now

- [ ] **Take the gallery photos off the public demo and out of the app builds.** *Done on the public demo since November 5 (only the storefront photo is shown). The iPhone apps' next test build leaves them out, and the old test build will be taken down when it's up.* The six gallery photos show clients' faces, and the first one appears to show someone under 18. They're live on the public demo (izzy-clipz.vercel.app) and inside the app builds, including the test builds. California law (Civil Code §3344) requires each person's consent, or a parent's or guardian's for a minor, before their photo is used to promote a business. Ask your developer to remove them, or swap in photos that show no faces, and to put the demo back up without them now. A photo of a person goes back only once you have that person's signed permission.

## 1. Before going live: must do

- [ ] **Have a California attorney review the four documents. This is strongly recommended.** Ask them to look in particular at:
  - the no-show and late-cancellation fee: whether the amount (100% of the price by default) and the cutoff hold up under California's rule for fees in consumer contracts (Civil Code §1671), the "agreed estimate of that loss, not a penalty" wording, the 15-minute grace period (cancelling within 15 minutes of booking is always free), the rule that a no-show fee is charged only after the appointment's end time, and whether to add an "I agree" checkbox;
  - the limit on liability (Terms, section 13), the choice of no arbitration, the courts clause (section 14), and how the Terms fit with Apple's standard license agreement for the iPhone app (section 17), or whether to give the app a custom license agreement instead;
  - the refund policy you choose (Terms, section 4);
  - the retention periods (12 months) and the request process in the Privacy Policy;
  - asking for a receipt email when a client pays by card at the counter (California's Song-Beverly Credit Card Act, Civil Code §1747.08);
  - the written agreement with your developer (below);
  - California's new age-signal law for apps, which starts January 1, 2027 (below);
  - whether the shop meets any of the CCPA thresholds (you'd need yearly revenue over $26,625,000, so almost certainly not).
- [ ] **The shop's exact legal name.** You answered that the shop is an LLC and wrote "Izzy Clipz Barbershop" as its legal name. An LLC's registered name has to contain "LLC", "L.L.C." or "Limited Liability Company" (California Corporations Code §17701.08), so check the exact name on the LLC's registration (the Secretary of State's bizfile record), for example "Izzy Clipz Barbershop LLC". Your developer has added "Izzy Clipz Barbershop is operated by [TO FILL IN: the LLC's exact registered name], a limited liability company." to the first paragraph of each of the four documents; that name goes there. Use the same name in Stripe and App Store Connect.
- [ ] **Get an email address for the shop**, used only for shop business (not anyone's personal email), and put it wherever the documents say "[TO FILL IN: the shop's email address]". The documents can't go live without it: the Accessibility Statement must offer ways to reach the shop other than a voice call, Stripe's receipts show a support email, and Apple asks for a support contact.
- [x] **Texts.** You answered that (442) 341-3053 takes phone calls only, so the Accessibility Statement no longer offers texting the shop. If someone starts reading texts on that number during opening hours, ask your developer to add the texting lines back.
- [ ] **Relay calls.** Tell everyone who answers the phone that calls through a relay service (711) are welcome: answer them like any other call, and don't hang up on the relay operator.
- [ ] **Choose a refund policy** (section 2) and write it into the Terms (section 4, "Refunds"). Stripe expects a refund and dispute policy on the website. If the shop doesn't give full refunds or exchanges on products for at least 7 days, also post the product policy at the counter (Civil Code §1723).
- [ ] **Show who you are, and the refund policy, before any card is charged.** California's law for businesses that take payments online (Business and Professions Code §17538(d)) asks for the refund policy, the legal name and the street address to be shown before any charge, on the booking screens, with a line saying how to get them by email (and you must send them within 5 days when asked). The Terms and the Cancellation & No-Show Policy now say so in their first paragraph; your developer adds the same to the website's footer and to "Review and book" once you've filled in the legal name, the email and the refund policy (section 3).
- [ ] **Prices that depend on the work (the lightener).** The Lightener Process is listed "From $80". The Attorney General's guidance on California's Honest Pricing Law (SB 478) says a listed price must be the whole amount, and a business that doesn't know the price yet shouldn't show one. Give it a range with a real top price (for example "$80–$140, depending on length and design"), or fixed-price options that can each be booked, and tell your developer. Then the Terms' "From" wording changes to the range. Ask your attorney.
- [ ] **Before you turn on no-show protection** (it's off until you turn it on): have your attorney approve the fee and the cutoff; write the record described in section 2; make sure fee receipts work (section 3); and keep the cutoff short. A 100% fee with a cutoff of a day or more is the hardest to defend under California's rule for fees in consumer contracts (Civil Code §1671), because a time cancelled a day ahead can often be filled. If you want a long cutoff, lower the late-cancellation fee for it, and ask your developer for that setting (section 3, Recommended).
- [ ] **Photos: permission and ownership.** Before any gallery photo of a person goes back on the website or in the apps, get written permission from each person shown (from a parent or guardian for anyone under 18), or use photos that show no faces. The Privacy Policy says that a photo in which someone can be recognized is shown only with that person's permission. Also confirm the shop owns, or has permission to use, every photo: they came from the shop's older website, and the Terms say the shop's photos belong to the shop or to the people who license them to it.
- [x] **The shop's accessibility details on the Visit page.** You confirmed two: "Room for a wheelchair inside, at the chairs and the counter" and "Accessible parking near the entrance". They go back on the Visit page, on the website and in the app, with the next release. You didn't tick a step-free entrance, so the Visit page also keeps "Questions about getting in or around the shop? Call (442) 341-3053 and we'll help." If the entrance has no steps, or has a ramp, tick that on the checklist page and it goes back too. (The old lines "Wheelchair accessible" and "ADA-compliant entrance" stay off: nobody had checked them, and "ADA-compliant" is a legal claim. Never use it unless an inspection backs it up.)
- [ ] **The entrance: find out what it's like, and fix it if there's a step.** Check the way in, from the disabled parking space to the counter: is there a step or a lip at the door, how wide is the doorway, and is the door hard to open? Write down what you find and take photos. If there's a step or another barrier, the law expects you to remove it where that's easy to do and doesn't cost much, starting with the entrance and the parking (a ramp is the usual fix). Lawsuits over building access are common in California, and the minimum damages are $4,000 for each visit where someone runs into a barrier or is put off from coming (both 2026 bills that would have given small businesses time to fix barriers first died). Ask your landlord who fixes what (a lease signed since 2017 must say whether the building has had a CASp inspection), and ask your attorney. Until it's fixed, tell everyone at the shop how to help someone get in, and have your developer add one plain line about the entrance to the Visit page (section 3).
- [ ] **Accessibility details on Google, Yelp and Apple Maps.** Check what the shop's listings say about the entrance, the parking, seating and the restroom. Turn on only what's true (Google's "Wheelchair-accessible entrance" means a doorway about 3 feet wide with no steps), and ask for anything wrong to be corrected. Keep them the same as the Visit page.
- [ ] **Yelp reviews stay off.** Yelp's API terms (last updated September 22, 2026) describe the API as being for "non-commercial uses", which they define as use that brings no promotional or money value, and they don't allow Yelp ratings next to other reviews. The shop's own website and app are there to promote the shop, and today they show Yelp's rating next to Google's. So the documents say the website and apps show Google's reviews and only link to Yelp. Make sure the live server has no Yelp key (`YELP_API_KEY` unset). If you'd like Yelp reviews later, first get Yelp's written permission, use Yelp's own stars and logo, keep Yelp's rating away from Google's, and update the Privacy Policy, the Terms and the Accessibility Statement before turning them on (research.md §12.2 says what to add).
- [ ] **The older website and Squire.** The shop's older website (izzyclipzbarbershop.net, on Squarespace) has a booking button that goes to the shop's old booking page on Squire. The iPhone app now points at the new website instead. Close the older website and the Squire page, or send their visitors to the new website, before the documents go live. Besides the privacy reasons, they're the shop's own pages, so their accessibility is the shop's responsibility too, but nobody has checked them, and the Accessibility Statement doesn't cover them. The Privacy Policy ("Who we are") and the Terms (section 1) say they're not covered. If you close both, or the address izzyclipzbarbershop.net moves to the new website, delete those sentences.
- [ ] **A written agreement with your developer.** The developer can reach clients' information: the database, the server's settings and keys, and the shop's Stripe account. The Privacy Policy says the developer may use that access only to keep things working, fix problems and carry out clients' requests. Put that in writing: confidentiality, security, use only for the shop, telling you straight away about any breach, and returning or deleting the shop's data and keys when the work ends. Your attorney can give you a short template.
- [ ] **Own the accounts.** The accounts for Vercel, Neon, Stripe, Apple Developer, Google Cloud (the reviews key) and GitHub should belong to the shop, with your developer invited as a member, or at least the shop should have owner access to each. When the developer's work ends, remove their access and change the owner key.
- [ ] **Data protection terms with Vercel and Neon.** The Privacy Policy says they process clients' information under data protection terms that require them to keep it secure and use it only to provide their services. Vercel's Data Processing Addendum applies to its Pro and Enterprise plans (see section 4). Confirm that Neon's applies to the shop's database (Neon is now part of Databricks, and its privacy policy now points to the Databricks Privacy Notice; Neon's terms point to its Data Processing Addendum). Keep a copy of each.
- [ ] **No card fees at the counter.** The Terms promise there are no booking fees or other required charges on top of the price. Confirm the shop never adds a card fee or any other extra charge when ringing up a client, including as a custom checkout item. If you ever want one, ask your attorney first and update the Terms and the prices shown.
- [ ] **Age range in both iPhone apps, from January 1, 2027.** California's Digital Age Assurance Act (AB 1043, as amended by AB 1856) requires apps to ask the device for the user's age range when the app is downloaded and launched; any version of the apps available on or after January 1, 2027 must do it, and the Attorney General can seek up to $2,500 per affected child, or $7,500 if it's intentional. *Built:* both apps now ask at launch on iOS 26 or later (only where iOS says a law requires it, from iOS 26.2), keep the answer in memory only, and show someone under 13 a screen asking a parent or guardian to book; the Privacy Policy's "Children" section says so. Still to do: turn on the Declared Age Range capability for both apps (com.izzyclipz.app and com.izzyclipz.business) when they're signed for the App Store, and ask your attorney whether asking everywhere on iOS 26.0 and 26.1, which can't tell where a law applies, is acceptable under AB 1856.
- [ ] **Decide who answers requests**, and who covers when they're away. The documents promise:
  - privacy requests: confirm within 10 business days, answer within 45 days;
  - accessibility problems: a reply within 5 business days, and booking for the client right away by phone (or as soon as you see their email);
  - questions about a fee: a reply within 5 business days;
  - photo takedowns: off the website as soon as possible, out of the app in its next update.
- [ ] **Confirm the decisions in section 2**, or tell your developer what to change.
- [ ] **Make sure every code change in section 3 is done, tested and released together with the documents.** The documents promise them.
- [ ] **Fill in the dates on the day the release goes live.** Replace each "[TO FILL IN: ...]" date at the top of the four documents with that day. For the Accessibility Statement's "Last reviewed", use the day someone checked it against the live website and both apps. Nothing marked "TO FILL IN" may be left in them when they go live.

## 2. Decisions to confirm

| Decision | What the documents say now | Where |
|---|---|---|
| How long clients' details are kept | Name, number, email and note are removed 12 months after the appointment | Privacy Policy |
| How long saved cards are kept | With "Remember me": until the card expires, goes 12 months without a booking, or the client removes it. Without it: until the booking it was saved for can no longer be charged (7 days after the appointment at the latest) | Privacy Policy, Cancellation & No-Show Policy |
| "Remember me" | Starts off on the website and in the iPhone app, unless that phone or computer already remembers the client | Privacy Policy, Cancellation & No-Show Policy |
| The fee amount | What you set in the app: a percentage of the service's price (100% unless you lower it) or a set amount, **never more than the service's price** | Cancellation & No-Show Policy |
| The cutoff for free cancelling | What you set in the app: 1 hour unless you change it (30 minutes to 48 hours) | Cancellation & No-Show Policy |
| Late cancellations | Charged like a no-show, unless you turn late cancellations off in the app | Cancellation & No-Show Policy |
| Changing their mind | Cancelling within 15 minutes of booking is always free, even past the cutoff (for example, a time booked 30 minutes ahead); after that, the usual rules apply | Cancellation & No-Show Policy, Terms |
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

**Keep a written record of how you set the fee.** Each time you turn the fee on, or change the amount or the cutoff, write down, with the date: how many appointments in the last few months were no-shows or late cancellations; how many of those times another booking or a walk-in filled; the average price of those services; what the shop saves when a service isn't done (supplies, card fees, and the barber's pay if barbers are paid per service); and why the amount fits those numbers. Don't copy another shop's fee or a booking app's default. Keep each note for at least 4 years after you stop using that setting. The Cancellation & No-Show Policy says the fee is set from the shop's own records, and if a client ever challenges it, the question is whether it was a reasonable estimate of the shop's loss when you set it (courts reject reasons given afterwards). Long cutoffs at 100% (say, 24 hours or more) are harder to defend than short ones, because a time cancelled a day ahead can often be filled. The 15-minute grace period, and not charging a late-cancellation fee when someone else takes the time, are there for the same reason: in those cases the shop has lost little or nothing.

## 3. Code changes the documents depend on

Your developer has the exact details (research.md §18 lists them). **Ship them all in one release, together with the four documents, and don't publish the documents before.** Add tests that fail if any of them is missing. In plain words:

1. **Put the four documents on the website** (live and demo), with links at the bottom of every page, inside both iPhone apps, and next to the fee notice in the booking steps. Include the new pages in the website's accessibility, phone-size and offline checks, and check that nothing marked "TO FILL IN" is left in them.
2. **Show "By booking, you agree to our Terms of Service and Cancellation & No-Show Policy"**, with links, just above the "Book appointment" button, on the website and in the app.
3. **Never let the fee be more than the price of the service** (today the set-amount option can charge $20 on a $5 service).
4. **Stop fees from being charged more than 7 days after the appointment.**
5. **No-shows only after the end time:** a booking with a card on file can be marked a no-show, and charged, only after its end time; and once it's marked completed, it can't become a no-show.
6. **The 15-minute grace period:** cancelling within 15 minutes of booking is always free, and the booking screens say so when a time is already past the cutoff.
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
17. **Fix the Visit page's accessibility lines:** take the unchecked ones off now, and put back only what you confirm (section 1).
18. **Ask for the user's age range in both apps** before January 1, 2027.
19. **A receipt for every fee.** When a fee is charged to a saved card, Stripe emails a receipt to the email address the client gave on Stripe's card page. Visa's rules require a receipt for every charge to a saved card, and the policies now promise one. (Today the server sends none.)
20. **Who you are, before any card is charged** (Business and Professions Code §17538(d)): the website's footer (every page, in text no smaller than the booking text) and "Review and book" (website and app) show "Izzy Clipz Barbershop is operated by [the LLC's name], 1919 Mission Ave, Ste 105, Oceanside, CA 92058, United States" and "To get this information by email, email us at [the shop's email] and we'll send it within 5 days", with the refund policy linked next to the Cancellation & No-Show Policy. The footer's copyright line uses the LLC's name.
21. **The Visit page's accessibility lines:** "Disabled parking space near the entrance" instead of "Accessible parking near the entrance"; one plain line about the entrance once the owner has checked it (for example "Step-free entrance" or "One step at the entrance"); and the line about getting in also offers relay calls and email: "Call (442) 341-3053 (relay calls welcome: dial 711) or email us at [the shop's email], and we'll help."
22. **The fee notice and the terms stored with each booking**, before no-show protection is turned on: the title is "Late Cancellation & No-Show Fee" whenever late cancellations can be charged (not "Full Service Cancellation & No-Show Fee"), and new bookings show and store, for example: "No payment now. If you cancel less than 1 hour before your appointment, or don't come, Izzy Clipz may charge $40 (100% of the service) to this card within 7 days after your appointment time. Cancelling online is free more than 1 hour before, or within 15 minutes of booking." Then update the Cancellation & No-Show Policy's list of titles and its example.

**Recommended, but not promised by the documents:**

- Say "may be charged" in the fee notice (the agreed terms say "may charge"), and "online" instead of "in the app" in the terms for new bookings.
- Small security improvements: a secret in the rate-limit scrambling, and the same security headers on the live site as on the demo.
- Show a charged fee under My appointments on the website, as the app does, and give staff a ready-made text to tell the client.
- Add accessibility checks to the iPhone apps' tests, and have someone who uses a screen reader try booking.
- A "Remove everything from this iPhone" action in the app, which also removes past appointments and their keys.
- A separate, lower cap for late-cancellation fees when the cutoff is long (or a shorter maximum cutoff), and a warning in Izzy Clipz Business before a late-cancellation fee is charged when another booking took that time (the policy promises not to charge then).
- Turn on axe-core's WCAG 2.2 "target-size" rule in the website's automated checks (it's off by default).
- Stripe's redaction (in public preview) could remove clients' details from the shop's Stripe records after 12 months; the Privacy Policy now says the Stripe records have no set end date.

## 4. Accounts and settings

### Stripe

- [ ] The Stripe account is in the shop's legal name.
- [ ] **Public details:** business name, support phone (442) 341-3053, the shop's email, address, website, and the links to the Terms of Service and Privacy Policy. Stripe's receipts need a support email and a privacy policy link.
- [ ] **Statement descriptor:** something clients will recognize on their card statement, like "IZZY CLIPZ".
- [ ] **Email receipts:** turn on Stripe's email receipts for successful payments, and check that a fee charged to a saved card sends one (section 3, item 19). The policies promise a receipt for every fee.
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
  - **Izzy Clipz Business:** Coarse Location and Product Interaction (Stripe's Tap to Pay software), Photos or Videos (product photos), and Name, Phone Number, Email Address, Other User Content and Purchase History (clients' details, and what they bought at checkout, which staff enter). For Izzy Clipz, consider Purchase History too (appointments and any fee charged, linked to the client's number).
- [ ] Answer the age rating questions, and add a support contact (the shop's email).
- [ ] Make the apps available in the United States only, unless you plan otherwise.
- [ ] **Accessibility Nutrition Labels.** App Store Connect asks which accessibility features each app supports (VoiceOver, Larger Text, Reduced Motion and others) and shows your answers on the App Store. They're optional for now, but Apple says they'll become required. Tick a feature only after someone has done the app's main tasks with it, start to finish: for Izzy Clipz, opening it for the first time, booking (with and without a card), cancelling and the settings; for Izzy Clipz Business, signing in, the schedule, booking a walk-in and checkout. Until then, leave them blank. Never claim more than the Accessibility Statement says (for example, only Izzy Clipz follows Reduce Motion).
- [ ] **Before January 1, 2027:** the age-range change in section 3 is in both apps.

## 5. In the shop

- [ ] **Post the price list and the sign California requires in barbershops** (Civil Code §51.6): a list of your 15 most requested services with every price, including each barber's price where they differ, in at least 14-point bold type; a complete written price list for anyone who asks; and a sign in at least 24-point bold type with these exact words: "CALIFORNIA LAW PROHIBITS ANY BUSINESS ESTABLISHMENT FROM DISCRIMINATING, WITH RESPECT TO THE PRICE CHARGED FOR SERVICES OF SIMILAR OR LIKE KIND, AGAINST A PERSON BECAUSE OF THE PERSON'S GENDER. A COMPLETE PRICE LIST IS AVAILABLE UPON REQUEST."
- [ ] **Keep prices based on the service, the time and the work**, never on gender, hair texture or hairstyle.
- [ ] **Gift cards:** no expiry dates, no fees, and cash back on request when less than $15 is left.
- [ ] **Card payments:** never require a ZIP code, phone number or email to take a card. Offer an email receipt only after the payment has gone through, and only for the receipt.
- [ ] **Barbers:** get each barber's OK to show their name, bio and Instagram, and take them off when they leave.
- [ ] **Get a CASp inspection** of the entrance, the parking, the counter and any restroom clients use (a Certified Access Specialist checks them against the building rules). If you're ever sued over building access, it can pause the case for 90 days, and it lowers the minimum damages if you fix what it found in time. Do it before the Visit page says anything more about getting in.
- [ ] **Service animals are welcome** (the Accessibility Statement says so). Tell everyone at the shop: if it isn't obvious what the animal does, you may ask only two things: is the animal needed because of a disability, and what work or task has it been trained to do? Don't ask for papers, a vest or proof, don't ask about the person's disability, and never charge extra. You can ask for an animal to leave only if it's out of control and the handler doesn't get it under control, or if it isn't housebroken; then offer to serve the client without it. Calls through any relay service (711, video relay, IP relay or a captioned phone) are welcome too: answer them like any other call.
- [ ] **Paying by card for clients who are blind or have low vision.** If Tap to Pay asks for a PIN, tap Accessibility Options on the PIN screen and hand the iPhone over: it reads out how to enter the PIN by tapping or drawing the digits. Practice it once. Read out the amount before the client pays, and offer another way to pay if they'd prefer.

## 6. Running the no-show policy day to day

- **You decide each time** whether to charge. Treat everyone the same way: if you waive the fee for one emergency, waive it for similar ones.
- **Don't mark anyone a no-show before their appointment's end time.** A client who arrives before the end isn't a no-show: fit them in if you can, or move them to another time.
- **Charge within 7 days** of the appointment, or not at all.
- **When you charge a fee, text or call the client** (the Text and Call buttons are on the appointment), and check that Stripe emailed the receipt. The policy promises both.
- **Check the shop's email before you mark anyone a no-show.** A client may cancel by email, and what counts is the time they sent it.
- **If someone else took the time** after a late cancellation (a new booking or a walk-in), don't charge the late-cancellation fee. The policy promises this.
- **If a client missed or cancelled late because of a disability**, waive the fee or work out another fair change with them. The policy promises this.
- **When a client calls before their appointment to cancel, cancel it in the app.** When they call to change it, move it for them (book the new time, then cancel the old one in the app). There's no fee when the shop cancels. Don't leave it and mark it as a no-show.
- **Never change a completed appointment to a no-show.**
- **If a client disagrees with a fee,** listen, check, refund it in Stripe if it was a mistake, and reply within 5 business days.
- **If the card is declined,** text the client that day (or email them, if they gave an email), and give them at least 7 days from then to pay another way, for example at the shop. The policy promises this, and Visa's rules require it.

## 7. Handling requests and problems

### Privacy requests (a copy, a correction or deletion)

1. Write down the date and what was asked.
2. Check it's really them: their name, mobile number and a detail of one of their appointments, then call or text the number on file.
3. Confirm you've received it within 10 business days.
4. Ask your developer to run the privacy tools (find, correct, or delete).
5. Answer within 45 days. If you need more time, tell them why (up to 45 more days).
6. Keep a short note of each request (date, what was asked, what you did) for 2 years. The Privacy Policy says so.

### Messages and emails with clients

Set the shop's iPhones to keep messages for 1 year (Settings, Messages, Keep Messages), and clear clients' emails and call history older than 12 months. The Privacy Policy promises that calls, texts and emails with clients are deleted within 12 months.

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
- **Check the Accessibility Statement against the live website and both apps at least once a year**, and after big changes: run the website's automated checks, book once using only the keyboard and once with VoiceOver on an iPhone, and make sure every line is still true. Then change its "Last reviewed" date, even if nothing else changed.
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
