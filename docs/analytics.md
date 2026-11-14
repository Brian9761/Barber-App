# Analytics: what each number means

The Analytics page in Izzy Clipz Business shows how the shop is doing, for
the whole shop or for one barber, for any day or range of days up to a
year. It updates by itself every 30 seconds, so you can leave it open.

This page explains every number in plain words. The names in parentheses
(like `salesCents`) are what the app's code calls them.

## Using Analytics in the app

- **Whose numbers.** "Whole shop", or a barber's chip. On a barber's page
  the leaderboard and the top barber stay the whole shop's.
- **Which days.** Today, Week (Monday to today), Month (the 1st to today),
  Year (January 1 to today), or **Custom…** for any days you pick, up to
  366 of them. All on the shop's calendar.
- **Live.** "Live · Updated 10:42 AM" with a green dot means the numbers
  are fresh. They update every 30 seconds while Analytics is on screen
  (not while the app is in the background), and when you pull down. If
  the phone can't reach the server, the numbers you had stay on screen,
  with **Try again**.
- **What a number means.** Each tile's ⓘ says it in a sentence or two,
  in the words of this page, and **What these numbers mean** sums this
  page up.
- **Daily sales.** Tap a bar to see that day's numbers. For one day, the
  chart shows each barber's sales that day instead; for more than 62 days,
  it goes by month.

The website's Business area shows the same numbers on a computer.

## Where the numbers come from

- **Checkouts.** When you check out a client, you ring up a **sale**: the
  services, any products, and custom items like a gift card. It's paid by
  **card** (Tap to Pay on the iPhone), in **cash**, or **other** (Zelle,
  Cash App, Squire and so on: you note it down, the app doesn't take that
  money). The sale gives credit to the barber who did the work.
- **Appointments marked Done without a checkout** still count: as the
  booked service, at its booked price. Checking out is better, because it
  records the real price and any products.
- **No-show and late-cancellation fees** count once Stripe has charged the
  client's card.
- **A voided sale doesn't count.**
- **Days are the shop's days**, on Pacific time. A sale rung up at 11:30 PM
  counts on that day, not the next, even on the night the clocks change.

## Sales

| Number | What it means |
| --- | --- |
| **Sales** (`salesCents`) | Everything together: services + products + other + fees. |
| **Services** (`servicesCents`, `servicesCount`) | Services on sales, plus appointments marked Done without a checkout (each counts once, at its booked price). A sale counts on the day it was rung up; an appointment without one counts on its day. |
| **Products** (`productsCents`, `productsCount`) | Products on sales: the money, and how many were sold. |
| **Other** (`otherCents`) | Custom items, like gift cards. |
| **Fees** (`feesCents`) | No-show and late-cancellation fees Stripe charged. They count on the day they were charged (when Stripe says the charge went through, even if that was days after you tried it), for the barber of that appointment. |
| **Checkouts** (`checkouts`) | Sales, plus appointments marked Done without a checkout. |
| **Clients served** (`clientsServed`) | Appointments marked Done, plus sales to walk-ins (sales without an appointment). |
| **Average ticket** (`averageTicketCents`) | (Services + products + other) divided by checkouts. Fees aren't part of it. |
| **Compared with before** (`previous`) | Sales for the same number of days just before, so you can see if you're up or down. For a week, that's the week before. |

## How productive the shop was

| Number | What it means |
| --- | --- |
| **Open hours** (`openMinutes`) | For each barber on the team, the hours the shop is open, minus his time off and the shop's (time that's off twice counts once). Only days up to today count; today counts all of its hours. A day the shop is closed counts nothing. |
| **Booked time** (`bookedMinutes`) | The length of appointments that are booked or Done, starting on days up to today. |
| **Chair time booked** (`chairTimeBooked`) | Booked time divided by open hours. It can go over 100% when barbers work past closing; the app shows at most 100%. |
| **Booked** | Appointments still booked, including ones from earlier that were never marked. |
| **Done** (`completed`) | Appointments marked Done (or checked out). |
| **No-shows** | Appointments marked as no-shows. |
| **Cancelled** | Appointments cancelled by the client or by the shop. |
| **Late cancellations** | Clients who cancelled in the app later than the booking's agreed policy allowed for free (for example, less than 1 hour before), and more than 15 minutes after booking (cancelling within 15 minutes of booking is always free). A booking whose policy had no late-cancellation rule is never late. |
| **Upcoming** | Booked appointments that haven't started yet. |
| **Completion rate** | Done divided by (Done + no-shows). |
| **No-show rate** | No-shows divided by (Done + no-shows). |
| **Sales per hour** (`salesPerHourCents`) | (Services + products + other) divided by open hours. |
| **Product attach rate** | The share of sales that included at least one product. |

Appointments are counted on the day they start.

## Leaderboard and top barber

- The **leaderboard** lists every barber on the team, even with $0, from
  the most sales to the least. Barbers with the same sales are ordered by
  how many services they did, then by name. Barbers with the same sales and
  the same number of services share a place (two at #1, then #3).
- It's always the whole shop's, even on one barber's page, so each barber
  can see where he stands.
- The **top barber** is #1 on the leaderboard, once he has sold anything.

## Top services and products

- **Top services** lists each service with how many were done and the
  money they brought in, highest first. Appointments marked Done without a
  checkout are included at their booked price.
- **Products** lists each product with how many were sold and the money,
  highest first. A product you deleted keeps the name it was sold under.
  Renaming a product shows its new name; changing its price never changes
  past sales.

## Daily sales (the chart)

One bar per day when you look at 62 days or fewer, otherwise one bar per
month. Every day (or month) is there, including the ones with nothing sold.

## One barber's page

Choosing a barber shows only his numbers: sales, services, products, the
chart, his open hours and appointments, and his own "compared with before".
The leaderboard and the top barber stay the whole shop's.

## Good to know

- **Voiding a sale** takes it out of the numbers. The appointment stays
  Done and can be checked out again. If it isn't checked out again, it
  counts like any appointment marked Done without a checkout, at its booked
  price; mark it cancelled if it shouldn't count at all.
- **Rung up twice by mistake** (say, in cash while the client's card was
  going through): both sales count until you void one. If you void the cash
  one, the card payment becomes the appointment's checkout, so the visit
  still counts once, as paid by card.
- **Voiding a card sale doesn't refund the card.** Refunds are made in the
  Stripe Dashboard.
- **A card sale counts when the payment goes through**, normally a few
  seconds after the tap. If the app only confirms it later (say, the next
  morning), it still counts on the day the card went through.
- **A barber who leaves the team** still counts in the shop's numbers for
  the time he worked, but he's no longer on the leaderboard and his open
  hours stop counting.
- **Checked-out appointments** can't be reopened, cancelled or marked a
  no-show until their sale is voided, so the numbers always match what
  happened. One booked with a card on file never becomes a no-show once
  it's been completed, even after that (the Cancellation & No-Show Policy).
- Payments taken by card **without** a checkout (from an older version of
  the app) don't show up here, except as the appointment's booked price
  when it's marked Done.
- **Clients' details are removed after 12 months** (the shop's Privacy
  Policy): the client's name, number, email and note on an appointment, and
  the name on a sale, are deleted 12 months later (a client can also ask
  sooner). The appointments and sales themselves stay, with what was booked,
  the prices, what happened and the fees, so every number here stays the same:
  the analytics never use names, numbers, emails or notes.

For developers: the definitions are in `server/src/analytics.ts`, and
`server/test/analytics.test.ts` checks every one against a week of shop data
worked out by hand.
The owner app's in-memory sample server (the demo version and the UI tests)
works them out the same way in `IzzyClipzBusiness/Fakes/FakeAnalytics.swift`,
from its own appointments and sales plus 8 weeks of sample history
(`FakeSampleHistory.swift`), and `FakeAnalyticsTests` checks each one.
