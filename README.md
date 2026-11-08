# Free Reel Effects — a Claude skill by GALTech School of Technology

Created by **GALTech School of Technology** · [www.galtechlearning.com](https://www.galtechlearning.com)

Add 11 Instagram-reel style effects to any vertical (9:16) talking-head video. You don't need After Effects or any paid tool. Everything runs on your own computer with Python and ffmpeg.

A free, open-source AI model (`u2net_human_seg`) cuts the person out of every frame. That is what makes effects like *text behind the person* and *spotlight* possible.

| # | Effect (`--effects` name) | What it looks like |
|---|---|---|
| 1 | `glass` | Frosted-glass cards: title card, live audio bars driven by the real audio, stat counter |
| 2 | `orbit` | Mini preview cards of the other effects circle around the person |
| 3 | `spot` | Room goes dark, the person stays lit |
| 4 | `behind` | Huge glowing word placed **behind** the person's head |
| 5 | `title` | Yellow background + big "10 EDITS" style title |
| 6 | `todo` | Dark checklist ticking off items one by one |
| 7 | `news` | Newspaper front page with masthead, highlighted headline and the video inset |
| 8 | `brief` | Orange magazine-poster layout with two video tiles |
| 9 | `timeline` | Editing-timeline panel with moving playhead above the video |
| 10 | `toggles` | iPhone-style switches flip on one by one |
| 11 | `match` | Video dissolves into orange halftone dots and back |

## Install (one command)

The installer checks everything and installs what's missing: Python 3.9+, ffmpeg, curl, the Python packages, and the free AI model and fonts.

**Mac / Linux**

```bash
git clone https://github.com/seokochin/galtech-video-effects-skill.git
cd galtech-video-effects-skill
bash install.sh
```

**Windows (PowerShell)**

```powershell
git clone https://github.com/seokochin/galtech-video-effects-skill.git
cd galtech-video-effects-skill
powershell -ExecutionPolicy Bypass -File install.ps1
```

It ends with `All set!` once the skill is ready. The model and fonts (about 180 MB) are cached in `~/.free_reel_fx`.

<details><summary>Manual install instead</summary>

1. Install Python 3.9+ and ffmpeg (Mac: `brew install python ffmpeg` · Windows: `winget install Python.Python.3.12 Gyan.FFmpeg` · Ubuntu: `sudo apt install python3 python3-pip ffmpeg curl`)
2. `python3 -m pip install numpy opencv-python-headless pillow onnxruntime`
3. `python3 free-reel-effects/fx.py setup`
</details>

## Add it to Claude

Zip the `free-reel-effects` folder and upload it as a skill in your Claude app's Skills settings. Then ask Claude: *"Add reel effects to my video"*. Claude asks for your on-screen texts, runs every stage and checks the result.

## Use it without Claude

```bash
python3 free-reel-effects/fx.py all --input my_clip.mp4 --output my_reel.mp4 \
  --title "My Shop" --subtitle "New arrivals" --word "SALE" \
  --brand "The Shop Daily" --headline "This week only: 20% off every phone" --highlight "20%" \
  --toggles "Free delivery,Cash on delivery,7-day returns"
```

- Pick only some effects: `--effects glass,spot,behind,news`
- Keep the first or last seconds clean: `--intro 2 --outro 3`
- See which effect lands where: `python3 free-reel-effects/fx.py plan --work ~/reel_fx_work --effects ...`

## Tips

- Works best with one person, framed waist-up, head in the upper third.
- Each effect needs about 3.5 s to play fully. For clips under ~40 s, choose 4–6 effects instead of all 11.
- On-screen text uses Latin fonts (Montserrat, Playfair Display). For Malayalam/Arabic text, swap in a Noto font inside `font()`.
- Stats such as "Views 12.4K" are placeholders. Use real numbers or drop the `glass` stat card before posting.
- The cut-out runs at roughly 0.5 s per frame on a 4-core laptop, so a 60 s clip takes several minutes.

---

Created by **GALTech School of Technology** · [www.galtechlearning.com](https://www.galtechlearning.com) · Malayalam AI and tech tutorials on YouTube: [GALTech Learning Hub](https://www.youtube.com/@galtechlearninghub)
