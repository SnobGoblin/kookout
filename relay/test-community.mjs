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
