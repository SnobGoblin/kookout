# Wingfoil alert

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
- **Powder** in Hemsedal highlighted (blue): >10 mm in a day, below +2°, wind under 8 m/s

## How it works

Everything lives in `index.html`: plain HTML, CSS and JavaScript, no build step.
The page fetches forecasts straight from MET's
[Locationforecast API](https://api.met.no/weatherapi/locationforecast/2.0/documentation)
in the browser. Spots and their rules are in the `PLACES` list at the top of the script.

## Run locally

```bash
python3 -m http.server 8000
```

Then open http://localhost:8000.

## Deploy

```bash
printf 'put index.html www/wind/index.html\nput apple-touch-icon.png www/wind/apple-touch-icon.png\n' | sftp sternell@ftp.domeneshop.no
```
