// Kookout's rules: turn a forecast into rows and mark the good ones.
//
// Shared by the web page (index.html loads it as a module) and the relay (relay/src/index.js),
// so the page, the app and notifications always agree. It doesn't touch the page or any storage:
// everything it needs comes in as arguments.
//
//   analyse(spot, metForecast, waves, { units, waveUnit, zone }) -> rows
//
// spot:        { lat, lon, wind? , surf?, powder? }  with the rules described below
// metForecast: MET's Locationforecast "complete" JSON
// waves:       the relay's /waves answer ({ points: [{ time, height, period }] }), or null
// units:       "ms" or "kn"  (wind is judged on the rounded numbers in this unit, as shown on screen)
// waveUnit:    "m" or "ft"   (likewise for wave heights)
// zone:        the spot's time zone, e.g. "Pacific/Honolulu" (undefined = the computer's own)
// daysOff:     for weekend spots (spot.weekend): the person's days off ("YYYY-MM-DD": weekends and public
//              holidays where they live). Missing: Saturdays and Sundays.
//
// Rules (all wind values in m/s, wave heights in m):
// wind:   good when (mean >= min AND gust >= gust) OR mean >= steady, from one of `dirs`, for `hours` in a
//         row (between sunrise and sunset if `daylight`). sunny: an optional lower {min, gust, steady} for
//         days that are mostly sunny (sea breeze).
// surf:   good when waves are at least minWave (and the period at least minPeriod s, if set), and the wind
//         is at most maxWind, from one of `dirs`, for `hours` in a row (in daylight if `daylight`).
// powder: good on a day when the snow that fell (precipitation in hours below maxTemp °C) over that day and the
//         `days` - 1 before it (default 2: yesterday's snow makes today good) is more than mm, the day stays below
//         maxTemp, the wind stays under maxWind, and (if `sunny`) the day is mostly sunny.
// weekend: spot.weekend = true keeps only the good periods on days off (above).

export const COMPASS = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"];
export const compass = deg => COMPASS[Math.round(deg / 22.5) % 16];

export const KNOTS = 1.94384;
export const FEET = 3.28084;
// Numbers as shown on screen: wind as whole m/s or knots, waves with one decimal in m or whole feet.
export const windShown = (ms, units) => Math.round(units === "kn" ? ms * KNOTS : ms);
export const waveShown = (m, waveUnit) => waveUnit === "ft" ? Math.round(m * FEET) : Math.round(m * 10) / 10;

const WEEK = 7 * 24 * 3600 * 1000;

// Local calendar day ("YYYY-MM-DD") and hour (0–23) in a time zone.
const formatters = {};
const format = (zone, locale, opts) => formatters[zone + locale + JSON.stringify(opts)] ??=
  new Intl.DateTimeFormat(locale, { ...opts, timeZone: zone });
export const dayKey = (d, zone) => format(zone, "en-CA", { year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
export const hourOf = (d, zone) => Number(format(zone, "en-GB", { hour: "numeric", hourCycle: "h23" }).format(d));

export function analyse(spot, data, waves, { units = "ms", waveUnit = "m", zone, daysOff } = {}) {
  const w = ms => windShown(ms, units);
  const wv = m => waveShown(m, waveUnit);
  const rows = toRows(data, zone);
  markDaylight(rows, spot, zone);
  if (spot.surf) { addWaves(rows, waves); judgeSurf(rows, spot.surf, w, wv); }
  if (spot.wind) judgeWind(rows, spot.wind, w, zone);
  if (spot.powder) judgePowder(rows, spot.powder, zone);
  if (spot.weekend) keepDaysOff(rows, daysOff, zone);
  return rows;
}

// Strong enough: e.g. 5 (9), or a steady mean wind of 6+ where gusts don't matter.
// Compares the rounded numbers in the chosen unit, so the rule matches exactly what the list shows.
export function strong(r, lim, units = "ms") {
  const w = ms => windShown(ms, units);
  const mean = w(r.wind), gust = r.gust == null ? null : w(r.gust);
  return mean >= w(lim.steady) || (mean >= w(lim.min) && (gust === null || gust >= w(lim.gust)));
}

function toRows(data, zone) {
  // Hourly steps first (roughly the next 2½ days), then MET's 6-hour steps up to a week ahead.
  const series = data.properties.timeseries;
  const hourly = series.filter(t => t.data.next_1_hours);
  const lastHourly = new Date(hourly.at(-1).time);
  const sixHourly = series.filter(t => {
    const time = new Date(t.time);
    return time > lastHourly && t.data.next_6_hours && time - Date.now() < WEEK;
  });
  const row = (t, hours) => {
    const time = new Date(t.time);
    const now = t.data.instant.details;
    const step = hours === 1 ? t.data.next_1_hours : t.data.next_6_hours;
    return {
      time, hours, day: dayKey(time, zone),
      symbol: step.summary.symbol_code,
      temp: now.air_temperature,
      rain: step.details.precipitation_amount ?? 0,
      wind: now.wind_speed,
      gust: now.wind_speed_of_gust ?? null, // MET only gives gusts in the hourly part
      deg: now.wind_from_direction,
      dir: compass(now.wind_from_direction),
    };
  };
  return [...hourly.map(t => row(t, 1)), ...sixHourly.map(t => row(t, 6))];
}

// Sunrise and sunset for a given day and place (the standard "sunrise equation";
// accurate to a minute or two, which is plenty here). Returns Dates, or null in polar night/midnight sun.
export function sunTimes(date, lat, lon, zone) {
  const rad = Math.PI / 180;
  const [y, m, d] = dayKey(date, zone).split("-").map(Number); // the spot's local date
  const noon = Date.UTC(y, m - 1, d, 12);
  const n = Math.round(noon / 864e5 + 2440587.5 - 2451545);           // days since year 2000
  const Jstar = n - lon / 360;
  const M = (357.5291 + 0.98560028 * Jstar) % 360;                     // sun's mean anomaly
  const C = 1.9148 * Math.sin(M * rad) + 0.02 * Math.sin(2 * M * rad) + 0.0003 * Math.sin(3 * M * rad);
  const L = (M + C + 180 + 102.9372) % 360;                            // ecliptic longitude
  const transit = 2451545 + Jstar + 0.0053 * Math.sin(M * rad) - 0.0069 * Math.sin(2 * L * rad);
  const decl = Math.asin(Math.sin(L * rad) * Math.sin(23.4397 * rad));
  const cosH = (Math.sin(-0.833 * rad) - Math.sin(lat * rad) * Math.sin(decl)) / (Math.cos(lat * rad) * Math.cos(decl));
  if (Math.abs(cosH) > 1) return null;
  const H = Math.acos(cosH) / rad / 360;
  const toDate = jd => new Date((jd - 2440587.5) * 864e5);
  return { rise: toDate(transit - H), set: toDate(transit + H) };
}

// A row counts as daylight if the middle of its time span is between sunrise and sunset.
function markDaylight(rows, spot, zone) {
  const sun = {};
  for (const r of rows) {
    const s = sun[r.day] ??= sunTimes(r.time, spot.lat, spot.lon, zone);
    const mid = new Date(r.time.getTime() + r.hours * 1800e3);
    r.daylight = !s || (mid > s.rise && mid < s.set);
    r.sun = s;
  }
}

// Share of daytime hours (08–18) with a clear or fair symbol, per day.
function sunnyDays(rows, zone) {
  const days = {};
  for (const r of rows) {
    const h = hourOf(r.time, zone);
    if (h < 8 || h >= 18) continue;
    const d = days[r.day] ??= { sun: 0, all: 0 };
    d.all += r.hours;
    if (/^(clearsky|fair)/.test(r.symbol)) d.sun += r.hours;
  }
  return Object.fromEntries(Object.entries(days).map(([k, d]) => [k, d.sun / d.all > 0.5]));
}

function judgeWind(rows, rule, w, zone) {
  const sunny = rule.sunny ? sunnyDays(rows, zone) : {};
  const strongEnough = (r, lim) => {
    const mean = w(r.wind), gust = r.gust == null ? null : w(r.gust);
    return mean >= w(lim.steady) || (mean >= w(lim.min) && (gust === null || gust >= w(lim.gust)));
  };
  const ok = rows.map(r => (!rule.daylight || r.daylight) && rule.dirs.includes(r.dir) &&
    (strongEnough(r, rule) || (sunny[r.day] && strongEnough(r, rule.sunny))));
  markRuns(rows, ok, rule.hours);
}

function judgeSurf(rows, rule, w, wv) {
  const ok = rows.map(r => (!rule.daylight || r.daylight) && rule.dirs.includes(r.dir) &&
    r.wave != null && wv(r.wave) >= wv(rule.minWave) && w(r.wind) <= w(rule.maxWind) &&
    (!rule.minPeriod || (r.period != null && r.period >= rule.minPeriod)));
  markRuns(rows, ok, rule.hours);
}

// Hourly rows count as good when there are `hours` ok rows in a row.
// A 6-hour row already covers several hours, so it counts on its own.
function markRuns(rows, ok, hours) {
  for (let i = 0; i < rows.length; ) {
    if (!ok[i]) { i++; continue; }
    if (rows[i].hours === 6) { if (hours <= 6) rows[i].good = true; i++; continue; }
    let j = i;
    while (j < rows.length && ok[j] && rows[j].hours === 1) j++;
    if (j - i >= hours) for (let k = i; k < j; k++) rows[k].good = true;
    i = j;
  }
}

// Put the wave forecast's height onto each row (the forecast point at, or nearest to, the row's time).
function addWaves(rows, waves) {
  const pts = (waves?.points ?? []).map(pt => ({ t: Date.parse(pt.time), h: pt.height, p: pt.period }));
  for (const r of rows) {
    const t = r.time.getTime() + (r.hours === 6 ? 3 * 3600e3 : 0); // middle of a 6-hour block
    let best = null;
    for (const pt of pts) if (!best || Math.abs(pt.t - t) < Math.abs(best.t - t)) best = pt;
    if (best && Math.abs(best.t - t) <= 3 * 3600e3) { r.wave = best.h; r.period = best.p; }
  }
}

function judgePowder(rows, rule, zone) {
  const days = {};
  for (const r of rows) {
    const d = days[r.day] ??= { snow: 0, maxTemp: -99, maxWind: 0 };
    if (r.temp < rule.maxTemp) d.snow += r.rain; // precipitation in the cold hours falls as snow
    d.maxTemp = Math.max(d.maxTemp, r.temp);
    d.maxWind = Math.max(d.maxWind, r.wind);
  }
  const keys = Object.keys(days).sort();
  const span = Math.max(1, Math.round(rule.days ?? 2));
  const sunny = rule.sunny ? sunnyDays(rows, zone) : null;
  for (const r of rows) {
    if (r.rain > 0 && r.temp < rule.maxTemp) r.snow = true;
    const i = keys.indexOf(r.day), d = days[r.day];
    // The forecast starts today: snow that fell before it isn't known, so the first day counts what's ahead only
    const fresh = keys.slice(Math.max(0, i - span + 1), i + 1).reduce((sum, k) => sum + days[k].snow, 0);
    if (fresh > rule.mm && d.maxTemp < rule.maxTemp && d.maxWind < rule.maxWind && (!sunny || sunny[r.day]))
      r.powderDay = Math.round(fresh * 10) / 10;
  }
}

// Weekend spots: only days off count.
function keepDaysOff(rows, daysOff, zone) {
  const off = daysOff ? new Set(daysOff) : null;
  const isOff = day => off ? off.has(day) : [0, 6].includes(new Date(day + "T12:00:00Z").getUTCDay());
  for (const r of rows) if (!isOff(r.day)) { r.good = false; delete r.powderDay; }
}
