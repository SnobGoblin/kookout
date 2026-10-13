# Kookout

A one-page hourly wind forecast for my wing foil spots around the Oslofjord and beyond,
with good sessions highlighted. Live at **https://sternell.com/wind/**.

Forecast data from [yr.no](https://www.yr.no) / MET Norway (CC BY 4.0).

## What it does

- Hourly forecast for ~2½ days, then 6-hour steps up to a week ahead
- Temperature, precipitation, wind with gusts and direction (16-point compass)
- **Good wind** highlighted per spot (green, with a wing foiler badge on the button):
  - 5 m/s with gusts of 9+, or a mean wind of 6+ regardless of gusts
  - from the directions that work at that spot
  - for 2+ hours in a row, between sunrise and sunset
  - Drøbaksundet: on mostly sunny days 4 (8), or a steady 5+, is enough
- **Good surf** highlighted (🏄): total wave height at least X m, wind at most Y m/s from chosen
  (e.g. offshore) directions, for 2+ hours in daylight. Waves come from MET's Oceanforecast in
  Scandinavian waters and NOAA's global WaveWatch III elsewhere (via the relay's `/waves`).
- **Powder** in Hemsedal highlighted (blue): >10 mm in a day, below +2°, wind under 8 m/s

## How it works

The page is `index.html` (plain HTML, CSS and JavaScript, no build step) plus `rules.js`, the rules that turn a
forecast into good hours. `rules.js` is shared with the relay, whose `POST /analyse` gives the app and
notifications exactly the same answers as the page.
The page fetches forecasts straight from MET's
[Locationforecast API](https://api.met.no/weatherapi/locationforecast/2.0/documentation)
in the browser.

## Live wind ("Nå")

Each spot shows the latest reading from a nearby weather station (MET's
[Frost API](https://frost.met.no)), green when it's blowing right now in a way that works there.
Browsers can't call Frost directly, so the page asks a small relay on Cloudflare Workers
([`relay/`](relay/src/index.js)), which asks the sources immediately and passes the answer back:
MET (Frost), Kystverket (Kystvær), NOAA (NWS and buoys) and Holfuy (station list; shown as their widget).

```bash
cd relay
npx wrangler deploy                     # publish the relay
npx wrangler secret put FROST_CLIENT_ID # the Frost client ID, stored as a secret
```

## Settings (⚙︎)

- Add spots by searching or tapping the map ([OpenStreetMap](https://www.openstreetmap.org/copyright)
  / Nominatim), and give them your own name. New spots start with the standard wing rule.
- Edit each spot's name, working directions (tap the compass), wind limits, hours in a row,
  daylight only, and an optional lower limit for sunny days.
- Reorder, hide or delete spots; switch between m/s and knots.
- Settings are saved in the browser (`localStorage`), so each phone keeps its own.
  The starting spots are `DEFAULT_SPOTS` at the top of the script.

## iOS app (`ios/`)

A native SwiftUI app, in progress. The Xcode project is generated from `ios/project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so it isn't kept in git:

```bash
brew install xcodegen
cd ios && xcodegen && open Kookout.xcodeproj
```

Bundle ID `com.sternell.kookout`, iOS 17+, English as the base language.

### Popular spots

`ios/Kookout/Catalogue.json` holds about 70 well-known spots (Oslofjord, Saltstein, Halland, Øresund, Stockholm,
Jæren, Hvide Sande, Montpellier, Biarritz, Fuerteventura, San Francisco, Cape Cod, Hatteras), each with the
wind directions that usually work. A new install starts with a welcome screen: "Spots near me" lists all
of them within 200 km to pick from; the add-spot screen lists the five nearest you don't have yet. "Start over" in Settings removes all
spots and settings and goes back to the welcome screen.

### Notifications

Each spot has notifications on unless switched off (Edit), and Settings has how far ahead to look (default
48 hours). The app sends the relay its push token and the spots with notifications on (`PUT /devices/<id>`,
see `relay/src/notify.js`); the relay keeps them in a Cloudflare D1 database (`relay/schema.sql`). Every hour
it works out those spots with the same rules and pushes through Apple's push service (APNs) when good
conditions come into the window, or change there (moved by 2+ hours, or no longer good). Nothing is sent
between 22 and 07 on the phone's clock; those changes come in the morning. `node relay/test-notify.mjs`
checks the change detection.

Push needs an APNs key from the Apple Developer site (Certificates, Identifiers & Profiles → Keys → +, with
Apple Push Notifications service). Put the key id and team id in `relay/wrangler.toml` (`APNS_KEY_ID`,
`APNS_TEAM_ID`) and the key itself in a secret:

```bash
cd relay && npx wrangler secret put APNS_KEY < AuthKey_XXXXXXXXXX.p8
```

## Run locally

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Deploy

Automatic: every push to `main` that changes `index.html` or `apple-touch-icon.png` runs
[the deploy workflow](.github/workflows/deploy.yml), which uploads the files to Domeneshop with SFTP.
The FTP password is stored as the repository secret `FTP_PASSWORD`.
You can also start it by hand under **Actions → Deploy to sternell.com → Run workflow**.

By hand, from this folder:

```bash
printf 'put index.html www/wind/index.html\nput apple-touch-icon.png www/wind/apple-touch-icon.png\n' | sftp sternell@ftp.domeneshop.no
```
