# Kookout promo: hybrid cut (cartoon + real footage)

A 9:16 social video, about 26 s, for Instagram/Facebook wing foil and surf groups and later the kookout.no landing
page. Cartoon for the joke, real riding for the payoff, an 80s movie-trailer narrator on top.

The message: **Kookout is the simple first filter.** It tells you when and where your spots are good, so you stop
rechecking. It doesn't replace swell charts, buoys or AIS; for the perfect wave you still use them, and Kookout
tells you when it's worth opening them.

Files here:
1. `README.md`: this plan (script, voice-over, prompts, what's needed).
2. `../promo.swift`: renders the code-drawn cartoon draft (`kookout-cartoon.mp4`); will assemble the final cut.
3. `footage/`, `generated/`, `*.mp4`, `*.mp3`, `*.wav`: media, kept out of git (see `.gitignore`).

## 1. Script

| # | Time | Picture | Narrator (80s trailer voice) | Sound |
|---|---|---|---|---|
| 1 | 0–3 s | Cartoon. Black, then chrome 80s title "THE FORECAST" with a lens flare. | "In a world… where the wind waits for no one…" | Low synth hit |
| 2 | 3–8 s | Cartoon. **Gary**, the hardcore rider, in a dark room lit by six screens: swell period chart, buoy graph, AIS ship map, tide table, four webcams, a wind map. Coffee cups pile up, one eye twitches, the clock spins. | "One rider checked seven apps. Every hour. For three weeks." | Clicks, refresh sounds |
| 3 | 8–12 s | Cartoon. **Kai**, the chill surfer, asleep in a hammock under a palm, sunglasses on. Phone on the belly lights up: "Home spot · Tomorrow 2–6 PM good". Swoosh. Kai lifts the sunglasses with one finger, slow grin. | "The other… waited for the swoosh." | **Kookout swoosh** |
| 4 | 12–13 s | Cartoon to real. Kai's sunglasses reflect the Kookout eyes; the pupils look out and the camera flies through them. | (beat) | Whoosh |
| 5 | 13–19 s | **Real footage**, three clips of about 2 s each: (a) red wing at speed on bright water, (b) POV selfie under the wing, grinning, (c) Insta360 shot of the rider flying on the foil. | "Kookout. It tells you **when**… and **where**." | Water, wind |
| 6 | 19–23 s | Cartoon. Gary, still at the screens, gets the same notification, looks at the charts, shrugs, closes the laptop and grabs his wing. | "Want the perfect wave? Keep your swell charts. Kookout just tells you when to look." | Laptop snap shut |
| 7 | 23–26 s | End card (exists in `promo.swift`): the eyes look left, right, out; KOOKOUT; "Know when your spots are good." / "Free on the App Store · kookout.no" | "Kookout. Now on the App Store." | Swoosh |

On-screen captions follow the narrator line for line, since most people watch muted.

## 2. Voice-over

Make it with ElevenLabs (or similar). Use a *generic* "epic movie trailer" voice from the voice library, or create
one with Voice Design: "deep, gravelly male American movie-trailer narrator, 1980s action film, slow and dramatic,
slight reverb". Do **not** use a voice sold as a copy of a real narrator. Check the plan allows commercial use.

Lines (one file each, so they can be timed against the picture; name them `vo-1.mp3` … `vo-6.mp3`):
1. "In a world… where the wind waits for no one…"
2. "One rider checked seven apps. Every hour. For three weeks."
3. "The other… waited for the swoosh."
4. "Kookout. It tells you when… and where."
5. "Want the perfect wave? Keep your swell charts. Kookout just tells you when to look."
6. "Kookout. Now on the App Store."

Music (optional): a short royalty-free 80s synthwave bed, licensed for ads (e.g. Artlist, Epidemic Sound). Never use
the music from an Instagram reel.

## 3. Character and shot prompts

Style line to start every image prompt with, so all shots match:

> Flat 2D cartoon, thick clean dark outlines, soft cel shading, cute rounded proportions, limited palette: navy
> #0E2A3B, sea blue #1C6EA4, buoy orange #FF6B2C, warm sand, white. Vertical 9:16. No text.

Characters (make a sheet of each first, then use it as the reference image for every shot):
1. **Kai**, the chill surfer: early 20s, round friendly face, shaggy sun-bleached hair, sleepy half-closed eyes,
   orange beanie, navy board shorts, relaxed smile, a bit sloth-like. "Character turnaround sheet, front, side,
   three-quarter, neutral pose."
2. **Gary**, the hardcore rider: 40s, wiry, wild hair, dark circles under bloodshot eyes, headlamp on his forehead,
   stained navy hoodie, coffee mug in each hand. Funny, never mean.

Shots (image first, then image-to-video, 2–5 s each):
1. Shot 2: "Gary in a dark room lit only by six glowing monitors showing wave charts, buoy graphs, a ship-tracking
   map and tide tables; coffee cups everywhere; he leans in, one eye twitching." Motion: slow push-in, screens
   flicker, eye twitch.
2. Shot 3: "Kai asleep in a hammock between two palms on a beach, sunglasses on, a phone lying on his belly."
   Motion: the hammock sways gently, the phone screen lights up, Kai lifts the sunglasses with one finger and grins.
3. Shot 4: "Extreme close-up of Kai's sunglasses reflecting two orange rings with dots, like eyes." Motion: slow
   push into the reflection. (I can also draw this one in code from the logo.)
4. Shot 6: "Gary at his screens sees his phone light up, looks at the charts, shrugs, closes the laptop and grabs
   an orange wing-foil wing from the wall." Motion: the full action, 4 s.

Tools: Midjourney or Ideogram for the images; Runway, Kling, Veo or Sora for image-to-video (keep the reference
image so the characters stay the same between shots). Check each tool's terms for commercial use. Put the results in
`generated/` named `shot-2.mp4`, `shot-3.mp4`, …

The phone notification in shot 3 is better drawn by me (exact text, the real app icon) than generated: AI video
garbles text. Generate the phone with a blank screen; I overlay it.

## 4. Real footage

From Christian's Instagram reels; use the **original files** (Insta360 app or camera roll), not downloads from
Instagram. Put them in `footage/`.

1. Red wing at speed on bright water, with mountains (the reel with ~3,300 views).
2. POV selfie under the wing, smiling, helmet (~3,100 views). Needs the rider's OK.
3. Insta360 shot of the rider on the blue board under the wing, sunny sky (~1,500 views).
4. Optional: the drone shot of the fleet of red wings, only if we own it.

Rules: only clips we shot ourselves, everyone recognisable has said yes, no thermal-wind spots (no Garda-style lakes;
Kookout doesn't do thermals), no music from the reels.

## 5. Assembly

`promo.swift` takes everything from `footage/`, `generated/` and the voice files, cuts it to the timings above,
draws the captions, the notification overlay, the eyes transition and the end card in brand style, adds the swoosh,
and writes `kookout-promo.mp4` (1080 × 1920, 30 fps, H.264 + AAC). Changing a caption or timing is a re-render.
