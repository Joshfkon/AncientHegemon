# Paid expansions: App Store Connect setup

For the first update after 1.0 (DESIGN.md, "Paid expansions"). Nothing here has been created in
App Store Connect yet. Josh does each step himself, or confirms before Claude does it.

## Before any in-app purchase can go live

1. **Paid Apps agreement**: App Store Connect → Business (Agreements, Tax, and Banking). The
   Free Apps agreement covers 1.0; selling anything needs the Paid Apps agreement, accepted by
   the Account Holder.
2. **Banking**: add a bank account for payouts.
3. **Tax**: complete the US tax form (W-9 for a US person) and any other countries' forms
   it asks for.
4. Until the agreement shows **Active**, products can be created and tested in the Simulator
   with `AncientHegemon.storekit`, but they won't load from the App Store (TestFlight or
   sandbox) and can't be submitted.

## The product to create

App Store Connect → the app → Monetization → In-App Purchases → +.

| Field | Value |
|---|---|
| Type | Non-Consumable |
| Reference name | Empire: The Hittites |
| Product ID | `com.joshuakonstantinos.ancienthegemon.empire.hittites` (must match `Expansion.all` in `AncientHegemon/Sources/Store.swift` and the `.storekit` file; it can never be reused once created) |
| Price | USD 1.99 (Tier 2 equivalent); other storefronts at Apple's equivalents |
| Availability | All countries and regions where the app is sold |
| Family Sharing | On (the `.storekit` file says the same; turning it on can't be undone) |
| Display name (en-US, 30 chars max) | The Hittites |
| Description (en-US, 45 chars max) | A fifth empire: the Great Kings of Hatti |
| Review screenshot | `docs/appstore/review-store.png` (the Store sheet on an iPhone 17 Simulator, 2622 × 1206, saved by `StoreTests.testScreenshots`) |
| Review notes | "Unlocks the Hittite empire on the title screen. Tap Store (top right) or the locked Hatti banner. Restore Purchases is on the Store screen." |

The in-app purchase has to be **submitted with an app version** the first time: on the update's
version page, under "In-App Purchases and Subscriptions", add it before Submit for Review.

## Planned later (not to create yet)

- More empire packs at the same price, one product each (`…empire.<id>`).
- A bundle of every empire (`…empire.all`) once there are three or more. A bundle is its own
  non-consumable; `Store.refreshEntitlements` would treat it as owning every expansion.
- Scenario packs, possibly, after the empires (DESIGN.md says why they come second).

## What changes for the update's listing and review

- **Privacy**: `website/privacy/index.html` now says purchases are made through Apple and that the
  app talks only to the App Store. Deploy the site before the update goes to review. The App
  Privacy answers stay **Data Not Collected**: StoreKit purchases handled only by Apple don't
  count as collection by the developer.
- **Description**: add a line such as "Free to play. Optional expansions add new empires,
  starting with the Hittites." The listing must not suggest the base game is limited.
- **Review notes**: replace "No sign-in, purchases or network access" in `listing.md` with
  "No sign-in. One optional in-app purchase (The Hittites); the base game is complete without it.
  The app uses the network only for the App Store."
- **App Store screenshots** may show the Hittites, but at least one set should show the free game.
- Sandbox testing on a device: App Store Connect → Users and Access → Sandbox → Test Accounts,
  then sign in under Settings → Developer → Sandbox Apple Account on the iPhone. TestFlight
  builds buy from the sandbox for free.
