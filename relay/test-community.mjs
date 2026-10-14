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
