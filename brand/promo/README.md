# Kookout promo: cartoon

A 9:16 social video, about 25 s, for Instagram/Facebook wing foil and surf groups and later the kookout.no landing
page. Cartoon only, with an 80s movie-trailer narrator.

The message: **Kookout is the tap on the shoulder, not another forecast site.** It tells you when and where your
spots are good, so you don't have to remember to check. The details (wind maps, stations, ships, webcams) stay with
the sites riders already use and like, such as Foilmenyen. The video must never make those look bad: the joke is
about *forgetting to check*, never about the tools.

Files here:
1. `README.md`: this plan (script, voice-over, prompts).
2. `../promo.swift`: renders the code-drawn cartoon draft (`kookout-cartoon.mp4`); will assemble the final cut.
3. `generated/`, `*.mp4`, `*.mp3`, `*.wav`: media, kept out of git (see `.gitignore`).

## 1. Script

| # | Time | Picture | Narrator (80s trailer voice) | Sound |
|---|---|---|---|---|
| 1 | 0–3 s | Black, then chrome 80s title "THE WIND" with a lens flare. | "In a world… where the wind waits for no one…" | Low synth hit |
| 2 | 3–8 s | **Gary** at his office desk in a long meeting. Behind him, through the window, wings and surfers fly past on a perfect afternoon. He turns around just as the last one disappears. | "He checked the forecast every morning. The wind came in the afternoon." | Meeting murmur, a seagull |
| 3 | 8–12 s | **Kai**, the chill surfer, asleep in a hammock. The phone on his belly lights up: "Home spot · Tomorrow 2–6 PM good". Swoosh. Kai lifts his sunglasses with one finger, slow grin. | "Kai… just waited for the swoosh." | **Kookout swoosh** |
| 4 | 12–16 s | Kai, now sitting up, swipes through his favourite sites on the phone (generic wind map, station graph, webcam), nods, and puts a pin in tomorrow. | "Kookout taps you on the shoulder. Your favourite forecast sites fill in the details." | Taps |
| 5 | 16–21 s | Kai on the water at Home spot, flying on the foil, sun out. Gary rides past him, also grinning, phone in a waterproof pouch. | "Kookout. It tells you when… and where." | Water, wind |
| 6 | 21–25 s | End card (exists in `promo.swift`): the eyes look left, right, out; KOOKOUT; "Know when your spots are good." / "Free on the App Store · kookout.no" | "Kookout. Now on the App Store." | Swoosh |

On-screen captions follow the narrator line for line, since most people watch muted.

Other ways to say line 4, in order of preference:
1. "Kookout taps you on the shoulder. Your favourite forecast sites fill in the details."
2. "Kookout tells you when to look. Your favourite apps tell you the rest."
3. "Keep using the sites you love. Kookout just tells you when it's time."

## 2. Voice-over

Make it with ElevenLabs (or similar). Use a *generic* "epic movie trailer" voice from the voice library, or create
one with Voice Design: "deep, gravelly male American movie-trailer narrator, 1980s action film, slow and dramatic,
slight reverb". Do **not** use a voice sold as a copy of a real narrator. Check the plan allows commercial use.

Lines (one file each, so they can be timed against the picture; name them `vo-1.mp3` … `vo-6.mp3`):
1. "In a world… where the wind waits for no one…"
2. "He checked the forecast every morning. The wind came in the afternoon."
3. "Kai… just waited for the swoosh."
4. "Kookout taps you on the shoulder. Your favourite forecast sites fill in the details."
5. "Kookout. It tells you when… and where."
6. "Kookout. Now on the App Store."

Music (optional): a short royalty-free 80s synthwave bed, licensed for ads (e.g. Artlist, Epidemic Sound).

## 3. Character and shot prompts

Style line to start every image prompt with, so all shots match:

> Flat 2D cartoon, thick clean dark outlines, soft cel shading, cute rounded proportions, limited palette: navy
> #0E2A3B, sea blue #1C6EA4, buoy orange #FF6B2C, warm sand, white. Vertical 9:16. No text.

Characters (make a sheet of each first, then use it as the reference image for every shot):
1. **Kai**, the chill surfer: early 20s, round friendly face, shaggy sun-bleached hair, sleepy half-closed eyes,
   orange beanie, navy board shorts, relaxed smile, a bit sloth-like. "Character turnaround sheet, front, side,
   three-quarter, neutral pose."
2. **Gary**, the busy rider: 40s, friendly, slightly frazzled, short hair, shirt and tie with a surf-brand hoodie
   over it. Funny and likeable, never a loser: he gets his ride in the end.

Shots (image first, then image-to-video, 3–5 s each):
1. Shot 2: "Gary at a desk in a glass-walled meeting room, bored; behind him through a big window a sunny fjord with
   orange wing-foil wings gliding past." Motion: wings glide past behind him; he turns around too late.
2. Shot 3: "Kai asleep in a hammock between two pines by a sunny beach, sunglasses on, a phone lying on his belly
   with a blank screen." Motion: the hammock sways, the screen lights up, Kai lifts the sunglasses with one finger
   and grins.
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
