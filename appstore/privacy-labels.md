# App Privacy answers (App Store Connect → the app → App Privacy)

What Apple asks, and what to answer for Kookout. Based on what the app and relay actually do (see privacy.html).
Update this and privacy.html together whenever the data changes.

Privacy Policy URL: https://kookout.no/privacy.html

## "Do you or your third-party partners collect data from this app?"

**Yes.** ("Collect" means it leaves the phone and is kept longer than it takes to answer the request.)

## Data types to tick, and the three questions for each

For every type below, Apple asks:
- *How is it used?* Tick **App Functionality** only. (Not analytics, advertising, personalisation or "other".)
- *Is it linked to the user's identity?* As listed.
- *Is it used for tracking?* **No** for all. Kookout has no ads and shares nothing with data brokers.

| Apple's category → type | Tick? | Linked to identity? | What it is in Kookout |
|---|---|---|---|
| Contact Info → **Name** | Yes | Yes | The first name from Sign in with Apple, shown on shared spots and edits (only if signed in) |
| Identifiers → **User ID** | Yes | Yes | Apple's id for the account (only if signed in) |
| Identifiers → **Device ID** | Yes | No | The app's random key and the push token, for notifications and following community spots |
| User Content → **Other User Content** | Yes | Yes | Shared spots, fixes to names and positions, reports and their notes |

## Data types NOT to tick

- **Location (precise or coarse): No.** The user's own location never leaves the phone, except a ~1 km rounded map
  centre used to find nearby spots, which isn't stored. Spot positions are things the user made, so they come under
  User Content, not Location.
- **Contact Info → Email: No.** Kookout never asks for the email (Apple's sign-in can share a relay address, but
  the app doesn't request the email scope).
- **Usage Data, Diagnostics, Health, Financial Info, Purchases, Browsing/Search History, Contacts, Sensitive Info,
  Other Data: No.** No analytics, no crash-reporting tool of our own, no purchases yet. (Apple's own crash reports,
  which users opt into, don't count.)

## Result on the App Store page

- *Data Linked to You:* Contact Info, Identifiers, User Content
- *Data Not Linked to You:* Identifiers
- *Data Used to Track You:* none

## Change these when…

- the subscription arrives: add **Purchases → Purchase History** (App Functionality, linked) if the relay stores it;
- any analytics or crash tool is added: add **Usage Data / Diagnostics**.
