#!/usr/bin/env python
"""Batch asset generator for Monster Girl College.

Runs against the local ComfyUI server via generate.py (NoobAI-XL v1.1).
Writes raw PNGs into assets/raw/. Idempotent: skips files that already exist.
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = r"C:\Users\Benji\ComfyUI\generate.py"
PY = r"C:\Users\Benji\ComfyUI\venv\Scripts\python.exe"
RAW = os.path.join(HERE, "assets", "raw")
os.makedirs(RAW, exist_ok=True)

# Shared suffix for character sprites: full body, standing, clean white bg so we
# can alpha-key it in post for the overworld sprite + VN portrait crop.
SPRITE_TAIL = ("full body, wide shot, entire body visible, standing straight, legs visible, "
               "feet visible, shoes, from front, from below, solo, facing viewer, "
               "looking at viewer, plain background, blank background, white background, "
               "isolated, no background scenery, school uniform, detailed")
SPRITE_NEG = ("worst quality, old, early, low quality, lowres, signature, username, logo, "
              "bad hands, mutated hands, mammal, anthro, furry, ambiguous form, feral, "
              "semi-anthro, "
              "close-up, portrait, bust, upper body, cowboy shot, cropped legs, "
              "cropped feet, huge head, out of frame, multiple views, text, watermark, "
              "2girls, multiple girls, 2boys, multiple boys, multiple people, extra limbs, "
              "gradient background, background scenery, scenery, floor, ground, clouds, "
              "sky, sparkles, glowing aura, flames, light rays, vignette, glow, "
              "cast shadow, reflection")
BG_NEG = ("worst quality, old, early, low quality, lowres, signature, username, logo, "
          "people, person, 1girl, 1boy, crowd, text, watermark, "
          "blurry, jpeg artifacts")

CHARS = {
    "vaelira": "succubus, demon girl, pale pink skin, long wavy pink hair, curved black horns, "
               "bat wings, demon tail with heart tip, red eyes, heart-shaped pupils, flirty smirk, "
               "blush, black blazer, red plaid skirt, loose necktie, hand on hip, confident pose",
    "rach": "arachne, spider girl, extra arms, six arms, spider legs, large spider abdomen, "
            "long dark purple hair, four eyes, purple eyes, round glasses, shy expression, blush, "
            "holding an open book, black cardigan, pleated skirt, nervous smile",
    "sylith": "lamia, snake girl, long snake tail, green scales, very long dark green hair, "
              "yellow slit-pupil eyes, forked tongue, fangs, smug confident expression, "
              "arms crossed, elegant, school uniform with green necktie, small earrings",
    "mora": "slime girl, goo girl, translucent blue body, glossy wet skin, drippy goo hair, "
            "big cheerful smile, sparkly eyes, blush, see-through, shiny, hands up happily, "
            "blazer and skirt with translucent fabric, sparkling droplets around her",
    "nyx": "vampire girl, pale white skin, very long straight black hair, glowing red eyes, "
           "small fangs, black gothic lolita dress, black bat wings, parasol, smug haughty smile, "
           "frilled collar, red ribbon, elegant",
    "fenra": "hellhound girl, wolf girl, large fluffy wolf ears, bushy wolf tail, messy grey "
             "spiky hair, sharp yellow eyes, fangs, athletic build, red track jersey, "
             "shorts, energetic toothy grin, hands in pockets, wild hair",
    "sebille": "harpy, bird girl, large feathered wings instead of arms, brown and cream "
               "feathers, feather tufts on head, bird legs with talons, "
               "short messy brown hair, big round amber eyes, tilted head, curious, "
               "school uniform with feathered collar",
    "tillia": "dryad, plant girl, long flowing green hair with leaves and vines woven in, "
              "small pink flowers in hair, green vine markings on skin, calm gentle smile, "
              "soft closed eyes, long flowing green dress, petals drifting around her",
    "rin": "kitsune, fox girl, large fox ears with orange fur, nine fluffy fox tails behind her, "
           "blonde-orange hair, golden slit eyes, mischievous grin, whisker marks on cheeks, "
           "white and red kimono, kitsune fox mask pushed up on her head",
    "griz": "oni, ogre girl, single large white horn, long white hair, red skin, tall and "
            "muscular build, small tusks, sharp golden eyes, fierce looking, "
            "blushing shyly, gym uniform, sport jacket, hands clenched at sides",
    "willa": "ghost girl, translucent pale body, faintly glowing, long wispy white hair, "
             "glowing pale blue eyes, faded old school uniform, shy sad gentle smile, "
             "floating slightly off the ground, soft blue glow, mist at her feet",
    "cindra": "dragon girl, large dragon horns, dragon tail with red scales, small dragon wings, "
              "scattered red scales, striking gold slit eyes, long crimson hair, "
              "haughty proud expression, arms crossed, elegant tailored blazer uniform, "
              "student council armband",
}

PLAYER = ("1boy, solo, androgynous male, feminine delicate face, soft features, short brown hair, "
          "gentle brown eyes, school uniform with blazer and slacks, plain necktie, "
          "full body, standing, facing viewer, simple background, white background, hands visible, "
          "detailed, casual relaxed pose")

BACKGROUNDS = {
    "hallway": "no humans, school hallway corridor, rows of grey lockers, tall windows on the "
               "left, sunlight streaming across the floor, wooden floor, perspective, "
               "detailed anime background, indoors, day",
    "classroom": "no humans, empty classroom, rows of wooden desks and chairs, blackboard, "
                 "chalk dust in sunbeams, large windows, evening golden light, "
                 "detailed anime background, indoors",
    "library": "no humans, large school library interior, tall wooden bookshelves, reading tables "
               "with green lamps, warm lighting, ladder, dust motes, "
               "detailed anime background, indoors",
    "cafeteria": "no humans, school cafeteria, long tables and benches, food counter, trays, "
                 "large windows, warm midday light, vending machines, "
                 "detailed anime background, indoors",
    "courtyard": "no humans, school courtyard garden, stone fountain, cherry blossom trees in "
                 "bloom, paved path, wooden benches, clear blue sky, "
                 "detailed anime background, outdoors, day",
    "gym": "no humans, school gymnasium interior, polished wooden floor, basketball hoop, "
           "stacked bleachers, high windows, bright lighting, "
           "detailed anime background, indoors",
    "greenhouse": "no humans, botanical greenhouse interior, glass roof panels, dense tropical "
                  "plants, hanging vines, terraced flower beds, warm dappled sunlight, "
                  "detailed anime background, indoors, day",
    "rooftop": "no humans, school rooftop, chain link fence, water tank, sprawling sunset sky "
               "with orange and purple clouds, city skyline far below, "
               "detailed anime background, outdoors, sunset",
    "corridor_night": "no humans, dark school corridor at night, moonlight through windows, "
                      "long shadows, faint blue light, eerie atmosphere, lockers, "
                      "detailed anime background, indoors, night",
    "dorm": "no humans, cozy student dormitory bedroom, single bed with blanket, wooden desk, "
            "lamp, bookshelf, rug, warm afternoon light through the window, "
            "detailed anime background, indoors, day",
    "gate": "no humans, grand school front gate, tall iron fence, stone pillars, cherry blossom "
            "trees lining a path, blue sky with drifting petals, "
            "detailed anime background, outdoors, day",
    "council": "no humans, elegant student council room, long polished table, ornate chairs, "
               "bookshelves, large arched window, red carpet, "
               "detailed anime background, indoors, day",
}


def run(name, prompt, out, w, h, steps=30, cfg=5.5, neg=None):
    if os.path.exists(out) and os.path.getsize(out) > 20000:
        print("SKIP (exists): %s" % os.path.basename(out))
        return True
    cmd = [PY, GEN, "--model", "noobai", "-p", prompt, "-W", str(w), "-H", str(h),
           "-s", str(steps), "--cfg", str(cfg), "-o", out]
    if neg:
        cmd += ["--negative", neg]
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    ok = os.path.exists(out) and os.path.getsize(out) > 20000
    print("%s %-22s %5.1fs  %s" % ("OK  " if ok else "FAIL", name, time.time() - t0,
                                   "" if ok else (r.stdout[-300:] + r.stderr[-300:])))
    sys.stdout.flush()
    return ok


def main():
    names = [a for a in sys.argv[1:] if not a.startswith("-")]
    fails = []
    # Characters first (portrait crops matter most)
    for name, tags in CHARS.items():
        if names and name not in names:
            continue
        p = "1girl, %s, %s" % (tags, SPRITE_TAIL)
        if not run(name, p, os.path.join(RAW, "char_%s.png" % name), 768, 1344,
                   neg=SPRITE_NEG):
            fails.append(name)
    if not names:
        if not run("player", "%s, %s" % (PLAYER, SPRITE_TAIL),
                   os.path.join(RAW, "char_player.png"), 768, 1344, neg=SPRITE_NEG):
            fails.append("player")
        for name, tags in BACKGROUNDS.items():
            if not run(name, tags, os.path.join(RAW, "bg_%s.png" % name),
                       1216, 832, steps=32, neg=BG_NEG):
                fails.append("bg_" + name)
    elif "player" in names:
        if not run("player", "%s, %s" % (PLAYER, SPRITE_TAIL),
                   os.path.join(RAW, "char_player.png"), 768, 1344, neg=SPRITE_NEG):
            fails.append("player")
    print("\nFAILED: %s" % (fails or "none"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
