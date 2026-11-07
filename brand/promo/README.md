# Kookout promo: cartoon

A 9:16 social video, 30 s (cut to the narration), for Instagram/Facebook wing foil and surf groups and later the kookout.no landing
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

| # | Time | Picture | Narrator | Sound |
|---|---|---|---|---|
| 1 | 0–2.8 s | A gust line races across the fjord toward a little jetty with a plain red pennant. | "Wind. Doesn't wait, bro." | Wind |
| 2 | 2.8–7.7 s | **Gary** at dawn at the kitchen table, buried under pop-up cards of made-up metrics ("Seagull drift index: NE-ish", "Kites on webcam 3: 2 (1 lost)", …). | "Gary loves his charts. Seagull drift index. Respect." | Pop, pop, pop |
| 2b | 7.7–11.4 s | Gary in a meeting; wings glide past the window behind him; he turns round too late. | "But Gary also has, like, a job." | |
| 3 | 11.4–17 s | **Kai** the otter in his hammock; the notification ("Home spot · Tomorrow 2–6 PM good") pops out of his phone. | "Kai just waited for the swoosh. [swoosh] Swoosh means condish." | **Kookout swoosh** |
| 4 | 17–22.8 s | The **Lock Screen widget** (1.1, drawn by me), then Kai scrolling his favourite sites, the screen floating beside him. | "Kookout taps you on the shoulder when your spots are firing. Your favourite sites do the rest." | |
| 5 | 22.8–26.6 s | Kai and Gary pass each other on the water in opposite directions; Kai waves. | "When, and where. I think." | Water, wind |
| 6 | 26.6–30 s | End card: the eyes look left, right, out; KOOKOUT; "Know when your spots are good." / "Free on the App Store · kookout.no" | "Kookout. Go get your sesh." | Swoosh |

The 43 s version also had "This is Gary.", "Secondary swell median.", "And the wind came. In the afternoon.", "Kai?"
and line 3b "No app to open. Just. Glance."; the 30 s cut drops them (whole sentences from the same takes).

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

Shots (still first, then "animate this image"; a new chat each; save in `generated/`).
0. `shot-1.mp4` (scene 1): no characters; a windy fjord, a gust line racing toward a jetty, a flag snapping. Ask for a
   plain single-colour flag (Gemini likes to add crosses or text) and an empty sky in the upper third for the captions. Gemini ignores lengths, so
ask anyway and I cut what I need. The phone screens, cards and notifications are drawn by me.
1. `shot-2a.mp4` (scene 2, ~8 s), from `gary-master.png`: Gary at the kitchen table at dawn, delighted with his laptop
   and charts, leaning closer and closer, eyes darting between screen and papers. Static camera. Keep the space
   above him empty (the metric cards land there).
2. `gary-meeting.png`, then `shot-2b.mp4` (scene 2b, ~7 s): Gary bored in a glass-walled meeting room, a big window
   behind him onto a windy, sunny fjord; wing foilers with orange wings glide past behind him; at the end he turns
   round, too late.
3. `shot-4.mp4` (scene 4, ~6 s), from `kai-master.jpg`: Kai, relaxed in the hammock, scrolling on his phone with
   one paw, nodding slowly, content. Screen facing him.
4. `riders-passing.png`, then `shot-5.mp4` (scene 5), from `kai-riding.png` and `gary-riding.png`: they ride in
   **opposite directions** (side by side, Gemini mirrors the wings, so the wind blows from two sides), Kai in front
   going right to left and waving, Gary about twenty metres behind going left to right, with **open water between
   them**: wings that overlap in the still get their depth order wrong. Check every overlap before animating.

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
