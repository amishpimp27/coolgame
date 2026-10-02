# Monster Girl College

A playable visual-novel / walk-around dating sim built in **Godot 4.7**.

You are the only boy at an all-monster-girl college. A clerical mix-up let you in
because the interviewer took one look at your face and stopped reading the form.
Now the girls are working it out, one conversation at a time.

---

## Screenshots

| | |
|---|---|
| ![title](docs/screenshots/01-title.png) | ![hallway](docs/screenshots/02-hallway.png) |
| ![choices](docs/screenshots/03-dialogue-choices.png) | ![journal](docs/screenshots/04-journal.png) |

![all areas](docs/screenshots/05-areas.png)

## Running it

Open `project.godot` in Godot 4.7 and press F5, or from a shell:

```
"C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
  --path "C:/Users/Benji/Documents/shitty-ai-game"
```

## Controls

| Input | Action |
|---|---|
| `W A S D` / arrows | walk around |
| `E` / `Space` / `Enter` / left click | talk, advance dialogue |
| click a girl | talk to her |
| click a choice | pick a topic or reply |
| hold `Ctrl` | fast-forward text |
| `J` / `Tab` | student directory |
| `Esc` | close the directory / advance |
| `F11` / `Alt+Enter` | toggle fullscreen |

## The loop

1. Walk around one of 12 areas. Walking **into** a girl you have never met
   triggers her first-meeting scene — that is the premise of the game, so it is
   proximity-based rather than a menu.
2. Talking opens a topic menu: *Just chat*, *Flirt with her*, *Compliment her*,
   *Ask about herself*, *Leave*. Each option draws from that girl's dialogue pool
   for your current affection tier, so what she says changes as she warms up.
3. **Affection** climbs 0→100 across four tiers — Stranger (0), Friend (30),
   Close (60), Lover (85). Crossing a threshold queues a bespoke **milestone
   event** that plays on your next conversation with her. The 85 event is her
   route ending.
4. **Suspicion** rises when you flirt and never quite goes away. Hit 100 and the
   enrolment form gets read out loud in the staff room: game over.
   It decays a little every night — gossip goes stale.
5. The clock runs Morning → Class → Lunch → Afternoon → Evening. *Pass Time*
   advances it, *Attend Class* costs a period and buys Charm, *Go to Sleep* ends
   the day. Charm gates whether flirting lands or gets you politely rebuffed.
6. Progress autosaves on travel, on first meetings, and on milestones. There is
   also a save/load round trip from the title screen.

## The cast

12 students, ~340 dialogue lines plus 36 milestone events, written per character
with distinct voices:

| Name | Species | Title | Usually found |
|---|---|---|---|
| Vaelira | Succubus | Heart-Thief of Class 2-A | Cafeteria |
| Rach | Arachne | Weaver of the Restricted Stacks | Library |
| Sylith | Lamia | Duchess of the Sunless Bench | Courtyard |
| Mora | Slime Girl | Class 2-C's Warmest Problem | Dormitory |
| Nyx | Vampire | Countess of the Corridor After Curfew | Old Corridor |
| Fenra | Hellhound | Undefeated Champion of the West Track | Gymnasium |
| Rin | Kitsune | Nine-Tailed Troublemaker | Main Hallway |
| Sebille | Harpy | The Loudest Question | Rooftop |
| Tillia | Dryad | The Patient One | Greenhouse |
| Griz | Oni | Two Hundred Kilos of Shy | Gymnasium |
| Willa | Ghost | The Girl in the East Corridor | Old Corridor |
| Cindra | Dragon | Princess of the Council | Student Council Room |

Each has `active_periods`, so the school repopulates as the day goes on.

## Layout

```
data/            cast_a.json, cast_b.json (characters), areas.json (map)
scripts/
  autoload/      game.gd (clock, stats, saves), cast.gd (roster + scheduling)
  world/         world.gd (walk-around), actor.gd (sprite + shadow + bob)
  ui/            dialogue.gd, hud.gd, title.gd, journal.gd
  ui_kit.gd      shared look: panels, buttons, bars, fonts
  main.gd        orchestrator; also hosts --selftest / --playtest
main.tscn        single root node; every other node is built in code
assets/
  sprites/       background-keyed full-body art (overworld + VN)
  busts/         head-and-shoulders crops for the directory
  backgrounds/   12 painted areas at 1280x720
  fonts/         Segoe UI
tools/           asset pipeline + screenshots (ignored by Godot via .gdignore)
```

All UI is constructed in GDScript rather than `.tscn` files, so there is no
hand-authored scene tree to go stale.

## Tests

Two suites, both headless, both exit non-zero on failure:

```
# 296 checks: JSON schema, art presence, tier boundaries, area link symmetry,
# NPC scheduling, affection/suspicion clamping, milestone ordering, save round trip
godot --headless --path . -- --selftest

# 20 checks: drives the real UI - opens scenes, presses the actual choice
# buttons, travels, opens the journal, advances the clock, gets caught
godot --headless --path . -- --playtest
```

Other dev hooks: `--auto=world|new|continue`, `--scene=area:hallway`,
`--scene=meet:vaelira`, `--scene=menu:rin`, `--scene=journal:demo`,
`--scene=ending:cindra`, `--scene=gameover:0`, `--autoplay=1.5`,
`--shot=out.png --shot-delay=3`.

## Regenerating the art

Art is generated locally with NoobAI-XL v1.1 through ComfyUI — no external
services, no moderation layer.

```
python tools/gen_assets.py                  # everything
python tools/gen_assets.py cindra player    # just these two
python tools/rekey.py                       # cut the characters out
python tools/rekey.py rach willa            # just these two
```

### Cutting the characters out

`tools/rekey.py` runs the render through `rembg` with the **`isnet-anime`**
segmentation model — a network trained on anime characters — rather than the
border flood fill this project started with. That flood fill deleted any pale,
low-saturation pixel touching the frame edge, which also described pale skin,
white tights, thin anti-aliased limbs and translucent bodies: it erased Rach's
spider legs, Sylith's tail, Nyx's legs, and dissolved Willa down to her clothes.
It is invisible unless you check the silhouette, which is why it shipped.

Three things make the model's output clean:

1. **Square-padded before inference** — the network resizes its input to a fixed
   1024x1024, so a tall render gets squashed and the mask degrades.
2. **Guided-filtered against the image** — the mask returns at lower resolution
   than the image, leaving stepped edges; the filter snaps the alpha to the
   character's real outline.
3. **Defringed** — every partly-transparent edge pixel is recoloured from its
   nearest fully opaque neighbour, so the white plate stops bleeding into a halo.

Each sprite is then **trimmed to its alpha bounding box**. This is not cosmetic:
the game sizes characters by texture height, so any empty margin baked into the
render became a size error — a girl whose art filled her frame rendered visibly
larger than one drawn with more padding, at an identical target height. Trimming
makes texture height equal character height, which is what the scale maths in
`world.gd` assumes. Portrait crops are generated after trimming.

Dependencies live in their own venv so ComfyUI stays clean:

```
python -m venv C:/Users/Benji/models/bg-removal/venv      # needs Python 3.11;
C:/Users/Benji/models/bg-removal/venv/Scripts/pip install rembg onnxruntime
```

`tools/postprocess_assets.py` is the older keying path and is now only useful for
its background handling and contact sheet.

### Sprite scale

Characters are sized by `world._height_at(y)`:

```
height = NEAR_HEIGHT * area.char_scale * lerp(FAR_RATIO, 1.0, (y - walk_top) / (walk_bottom - walk_top))
```

so a girl at the back of a corridor is genuinely smaller than one beside you, and
everybody is resized as they move. `NEAR_HEIGHT` is the height in pixels at the
front edge of the walkable band; `area.char_scale` (in `data/areas.json`) trims
it for backdrops whose implied perspective differs; a cast member's
`height_scale` in the cast JSON is the on-top personal multiplier. With trimming
in place these numbers mean what they say, so tune them here rather than by
eyeballing sprite sizes.

**After regenerating any image you must re-run the Godot import**, or the editor
will keep serving the cached texture:

```
godot --headless --path . --import
```

> VRAM note: the image model and the local LLM cannot both fit on a 12 GB card.
> Stop `llama-server` before generating, and stop ComfyUI before using the LLM.

## Known rough edges

- Backgrounds are rendered at 1216x832. That is fine windowed, but on a 1440p
  screen maximised they are upscaled about 2x and look soft. Re-rendering at
  1920x1080 (or 1536x864) is a `BG_` size change plus a re-run of
  `gen_assets.py`; it has not been done.
- There is no audio.
- Milestone events are single scenes rather than multi-scene arcs.
- `--scene=`/`--shot=`/`--autoplay`/`--selftest`/`--playtest` hooks are dev
  affordances and are live in the shipped build.
