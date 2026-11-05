# Kookout promo: cartoon

A 9:16 social video, about 43 s (cut to the narration), for Instagram/Facebook wing foil and surf groups and later the kookout.no landing
page. Cartoon only (warm 3D animated-film look), with a very deep, slow, deadpan narrator: calm understatement
against Gary's chaos.

The message: **Kookout is the tap on the shoulder, not another forecast site.** It tells you when and where your
spots are good, so you don't have to remember to check. The details (wind maps, stations, ships, webcams) stay with
the sites riders already use and like, such as Foilmenyen. The video must never make those look bad: the joke is
never about the tools: Gary *loves* his charts and the narrator respects them ("Respect."); his only problem is
that he also has a job. Kookout tells him when it's worth opening them. (All the metrics in his scene are invented.)

**Post only once Kookout 1.1 is in the App Store**: the Lock Screen widget (scene 3b) comes with 1.1.

Files here:
1. `README.md`: this plan (script, voice-over, prompts).
2. `../promo.swift`: renders the code-drawn cartoon draft (`kookout-cartoon.mp4`); will assemble the final cut.
3. `generated/`, `*.mp4`, `*.mp3`, `*.wav`: media, kept out of git (see `.gitignore`).

## 1. Script

| # | Time | Picture | Narrator (deep, slow, deadpan) | Sound |
|---|---|---|---|---|
| 1 | 0–3.2 s | Black, then chrome 80s title "THE WIND" with a lens flare. | "Wind. Doesn't wait, bro." | Low synth hit |
| 2 | 3.2–10.6 s | **Gary** at 06:12 at the kitchen table, buried under pop-up charts of made-up metrics: "Secondary swell median", "Gust-to-lull variance (adj.)", "Seagull drift index: NE-ish", "Moon × tide phase: Waxing-ish", "Wind confidence index 63 %", "Kites on webcam 3: 2 (1 lost)", "Swell period, 4th model". His eyes go round. | "Gary loves his charts. Secondary swell median. Seagull drift index. Respect." | Pop, pop, pop |
| 2b | 10.6–17.4 s | Gary in a long meeting. Behind him, through the window, wings fly past on a perfect afternoon. He turns around just as the last one disappears. | "But Gary also has, like… a job. And the wind came… in the afternoon." | Meeting murmur, a seagull |
| 3 | 17.4–24 s | **Kai** the otter, dozing in a hammock between two pines. The phone on his belly lights up; the notification ("Home spot · Tomorrow 2–6 PM good") pops out of it and floats above his head. Swoosh. He slides his sunglasses down to look, slow grin. | "Kai? Kai just waited for the swoosh. Swoosh means condish." | **Kookout swoosh** |
| 3b | 24–28.2 s | Kai's Lock Screen, close up: under the clock, Kookout's **Lock Screen widget** (rectangular: "Home spot **now**", "The reef 14–18", "Ski hill Sat"; circular: wind icon and a tick), glowing; then the rectangular one pops out large enough to read. Drawn by me, exactly as the 1.1 widget looks. | "No app to open. Just… glance." | Soft chime |
| 4 | 28.2–34.2 s | Kai, now sitting up, swipes through his favourite sites on the phone (generic wind map, station graph, webcam), nods, and puts a pin in tomorrow. | "Kookout taps you on the shoulder when your spots are firing. Your favourite sites do the rest." | Taps |
| 5 | 34.2–39.2 s | Kai on the water at Home spot, flying on the foil, sun out. Gary rides past him, also grinning, phone in a waterproof pouch. | "When… and where. I think." | Water, wind |
| 6 | 39.2–43.2 s | End card (exists in `promo.swift`): the eyes look left, right, out; KOOKOUT; "Know when your spots are good." / "Free on the App Store · kookout.no" | "Kookout. Go get your sesh." | Swoosh |

On-screen captions follow the narrator line for line, since most people watch muted. Everything that matters
stays inside Instagram's Reels safe zone: clear of the top 250 px, the bottom 450 px and the right 140 px (buttons);
`promo.swift` shades those areas red in its check frames.

Other ways to say line 4, in order of preference:
1. "Kookout taps you on the shoulder. Your favourite sites do the rest."
2. "Kookout tells you when to look. Your favourite apps tell you the rest."
3. "Keep using the sites you love. Kookout just tells you when it's time."

## 2. Voice-over

The register: a young Californian surfer, slow and lazy, warm and quietly stoked, and **never quite sure of
anything** (phrases trail off with a half-amused questioning lilt). Light surf slang ("bro", "condish", "sesh"),
at most one per line; never a real person's catchphrases.

The voice is saved in ElevenLabs as **"Kookout narrator 2"** (Voice Design, then remixed at low strength from
"Kookout narrator").
Never clone or imitate a real person; if we ever want a known voice, we hire that person. Write pauses with full
stops and commas, never a stand-alone "…" (ElevenLabs may voice it as a syllable). Slow lines down with Text to
Speech's speed slider rather than by rewriting them.

Lines (one file each, so they can be timed against the picture):
1. `vo-1.mp3`: "Wind. Doesn't wait, bro."
2. `vo-2.mp3`: "This is Gary. Gary loves his charts. Secondary swell median. Gust-to-lull variance. Seagull drift
   index. Respect."
3. `vo-2b.mp3`: "But Gary also has, like, a job. And the wind came. In the afternoon."
4. `vo-3.mp3`: "Kai? Kai just waited for the swoosh. Swoosh means condish."
5. `vo-3b.mp3`: "No app to open. Just. Glance."
6. `vo-4.mp3`: "Kookout taps you on the shoulder when your spots are firing. Your favourite sites do the rest."
7. `vo-5.mp3`: "When, and where. I think."
8. `vo-6.mp3`: "Kookout. Go get your sesh."

The takes are in `vo/` (`vo-1.take-a.mp3` …, out of git); `promo.swift` uses take a of each line except line 5
(take b, the longer pause before "I think"), and the scenes are timed to the words.

Music (optional): a slow, warm lo-fi or ambient bed, licensed for ads (e.g. Artlist, Epidemic Sound), kept low under
the voice. The neon title card can keep a single synth hit.

## 3. Character and shot prompts

Style line to start every image prompt with, so all shots match:

> Warm 3D animated-film look, soft golden-hour light, a Nordic coast (granite boulders, low islands, pines).
> Vertical 9:16. No text, letters, captions, logos or watermarks.

Work in a **new chat** per shot, never mention the app, an ad or a promo, and never "extend" an old clip: Gemini then
burns in titles. Make a still first, check it, then animate that still as the first frame.

Characters (make a sheet of each first, then use it as the reference image for every shot). Both are Norwegian
coast animals; their eyes may be drawn round with the pupil "looking out", like the logo's O's.
1. **Kai**, a chill sea otter: chubby, fluffy brown fur, light cream face with rosy cheeks, whiskers, orange knit
   beanie with a pompom (no label), **silver-framed sunglasses**, relaxed smile. Reference: `generated/kai-master.jpg`
   (use it for every Kai shot).
2. **Gary**, an over-analysing Atlantic puffin: black and white, the striped orange beak, red eye rings, wide
   anxious eyes, light blue shirt and navy tie. Funny and likeable, never a loser: he gets his ride in the end.

Shots (image first, then image-to-video, 3–5 s each):
1. Shot 2: "Gary at a desk in a glass-walled meeting room, bored; behind him through a big window a sunny fjord with
   orange wing-foil wings gliding past." Motion: wings glide past behind him; he turns around too late.
2. Shot 3: from `kai-master.jpg`: "Animate this image. Camera completely still, 4 seconds. 0–1 s he dozes; at 1 s the
   phone screen (facing him) lights up with a plain cyan glow on his face; 1–2 s he slides his sunglasses down his
   nose with one paw to look; 2–4 s a big happy grin." The notification popping out is drawn by me.
3. Shot 4: "Kai sitting in the hammock looking at his phone, relaxed, nodding." Motion: small nods, thumb swipes.
   (The phone screens are drawn by me.)
4. Shot 5: "Kai wing foiling on a sunny fjord, flying above the water on a hydrofoil board, holding an orange wing,
   big smile; Gary riding behind him, also smiling." Motion: they glide left to right, spray from the foil masts.

Tools: Midjourney or Ideogram for the images; Runway, Kling, Veo or Sora for image-to-video (keep the reference
image so the characters stay the same between shots). Check each tool's terms for commercial use. Put the results in
`generated/` named `shot-2.mp4`, `shot-3.mp4`, …

Phone screens (the notification in shot 3, the sites in shot 4) are drawn by me, not generated: AI video garbles
text. The sites in shot 4 stay generic (no real logos or names) unless their makers say yes.

## 4. Assembly

`promo.swift` takes the shots from `generated/` and the voice files, cuts them to the timings above, draws the
title, captions, phone screens and end card in brand style, adds the swoosh, and writes `kookout-promo.mp4`
(1080 × 1920, 30 fps, H.264 + AAC). Missing shots render as the current code-drawn scenes, so the timing can be
checked early. Changing a caption or timing is a re-render.
