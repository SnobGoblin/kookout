// Run with: node test-community.mjs  (checks how the community's rules come out of the followers' versions)
import { majorityRule } from "./src/community.js";
const check = (name, got, want) => console.log(JSON.stringify(got) === JSON.stringify(want) ? "ok  " : "FAIL", name, JSON.stringify(got));
const current = { min: 5, gust: 9, steady: 6, hours: 2, daylight: true, dirs: ["S", "SSW", "SW"] };
check("everyone agrees", majorityRule([current, current, current], current), current);
check("3 of 5 add NE", majorityRule([{ ...current, dirs: ["NE", "S", "SSW", "SW"] }, { ...current, dirs: ["NE", "S", "SSW", "SW"] },
  { ...current, dirs: ["NE", "S", "SSW", "SW"] }, current, current], current).dirs, ["NE", "S", "SSW", "SW"]);
check("2 of 5 add NE", majorityRule([{ ...current, dirs: ["NE", "S", "SSW", "SW"] }, { ...current, dirs: ["NE", "S", "SSW", "SW"] },
  current, current, current], current).dirs, ["S", "SSW", "SW"]);
check("one extreme limit", majorityRule([{ ...current, min: 2 }, current, current], current).min, 5);
check("median of limits", majorityRule([{ ...current, min: 4 }, { ...current, min: 4 }, { ...current, min: 7 }], current).min, 4);
check("hours stay whole", majorityRule([{ ...current, hours: 1 }, { ...current, hours: 2 }, { ...current, hours: 3 }, { ...current, hours: 3 }], current).hours, 3);
check("daylight majority", majorityRule([{ ...current, daylight: false }, { ...current, daylight: false }, current], current).daylight, false);
const wind = { min: 5, gust: 9, steady: 6, hours: 2, daylight: true, dirs: ["S"] };
const sunny = { min: 4, gust: 8, steady: 5 };
check("sunny limits: 2 of 3 have them", majorityRule([{ ...wind, sunny }, { ...wind, sunny: { min: 3, gust: 7, steady: 5 } }, wind], wind).sunny, { min: 3.5, gust: 7.5, steady: 5 });
check("sunny limits: 1 of 3", "sunny" in majorityRule([{ ...wind, sunny }, wind, wind], { ...wind, sunny }), false);
const powder = { mm: 10, maxTemp: 2, maxWind: 8 };
check("powder days and sunny, voted in", majorityRule([{ ...powder, days: 3, sunny: true }, { ...powder, days: 3, sunny: true }, powder], powder),
  { mm: 10, maxTemp: 2, maxWind: 8, days: 3, sunny: true });
check("powder sunny, 1 of 3", majorityRule([{ ...powder, sunny: true }, powder, powder], powder).sunny, false);

// The community's wind station: the one most followers chose ("Automatic" counts for the current one); a tie keeps it.
import { majorityStation } from "./src/community.js";
check("station: nobody chose one", majorityStation([null, null, null], null), null);
check("station: 2 of 3 chose X", majorityStation(["X", "X", null], null), "X");
check("station: promoted P, one picks X", majorityStation(["X", "P", "P"], "P"), "P");
check("station: promoted P, all three pick X", majorityStation(["X", "X", "X"], "P"), "X");
check("station: tie keeps the current one", majorityStation(["X", "Y", "P", "P", "X", "Y"].slice(0, 4), "P"), "P");
check("station: X and Y tie, current not among them", majorityStation(["X", "Y"], "P"), "P");

// The community's season: the days more than half have in theirs (null: all year), as one stretch.
import { majoritySeason, inSeason, cleanSeason, defaultSeason } from "./src/season.js";
const N = { from: "03-15", to: "12-24" };
check("season: everyone has the default", majoritySeason([N, N, N], N), N);
check("season: 2 of 3 all year", majoritySeason([null, null, N], N), null);
check("season: median-like ends", majoritySeason([{ from: "04-01", to: "10-31" }, N, { from: "05-01", to: "09-30" }], N), { from: "04-01", to: "10-31" });
check("season: over New Year", majoritySeason([{ from: "11-01", to: "03-31" }, { from: "11-15", to: "03-15" }, { from: "10-15", to: "04-15" }], null),
  { from: "11-01", to: "03-31" });
check("season: 2 of 3 surf all winter too", majoritySeason([null, null, N, N, { from: "01-01", to: "12-31" }], N), null);
check("in season, Oslo 15 Mar", inSeason(N, Date.parse("2026-03-14T23:30:00Z"), "Europe/Oslo"), true);
check("out of season, Oslo 25 Dec", inSeason(N, Date.parse("2026-12-25T10:00:00Z"), "Europe/Oslo"), false);
check("over New Year: 2 Jan", inSeason({ from: "11-01", to: "03-31" }, Date.parse("2027-01-02T10:00:00Z"), "Europe/Oslo"), true);
check("clean: all year is null", cleanSeason({ from: "01-01", to: "12-31" }), null);
check("clean: nonsense", cleanSeason({ from: "13-01", to: "12-31" }), null);
check("default: Oslo wing", defaultSeason(59.9, "wing"), N);
check("default: Fuerteventura", defaultSeason(28.7, "surf"), null);
check("default: Hemsedal powder", defaultSeason(60.8, "powder"), null);
