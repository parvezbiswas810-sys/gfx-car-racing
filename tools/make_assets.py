"""Generates every binary asset used by GFX Offline Racing.

Run:  python3 tools/make_assets.py

Outputs:
  assets/models/car_*.glb     low-poly car meshes (6 variants)
  assets/textures/*.png       tileable surface + UI textures
  assets/audio/*.wav          engine, skid, crash, UI and music loops
  assets/fonts/*.ttf          UI font copied from the system

Everything is produced procedurally so the repository stays self-contained
and the pipeline is reproducible on any machine with Pillow installed.
"""

import json
import math
import os
import random
import shutil
import struct
import sys
import wave

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_writer import MeshBuilder, standard_material  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
TEXTURES = os.path.join(ROOT, "assets", "textures")
AUDIO = os.path.join(ROOT, "assets", "audio")
FONTS = os.path.join(ROOT, "assets", "fonts")

SAMPLE_RATE = 22050

# ---------------------------------------------------------------------------
# cars
# ---------------------------------------------------------------------------

# name, body colour, accent colour, wheelbase, track width, length, height
CAR_SPECS = [
    ("car_speedster",  (0.85, 0.10, 0.13), (0.10, 0.10, 0.12), 2.55, 1.72, 4.30, 1.02),
    ("car_phantom",    (0.10, 0.12, 0.42), (0.85, 0.86, 0.90), 2.60, 1.76, 4.45, 1.05),
    ("car_viper",      (0.08, 0.55, 0.20), (0.92, 0.90, 0.15), 2.50, 1.70, 4.20, 1.00),
    ("car_inferno",    (0.95, 0.45, 0.05), (0.12, 0.12, 0.14), 2.58, 1.74, 4.38, 1.04),
    ("car_spectre",    (0.55, 0.10, 0.72), (0.90, 0.90, 0.95), 2.52, 1.70, 4.25, 1.01),
    ("car_titan",      (0.20, 0.22, 0.25), (0.85, 0.20, 0.10), 2.62, 1.80, 4.50, 1.08),
]


def build_wheel():
    """Standalone wheel so the car scene can spin and steer it in code."""
    b = MeshBuilder()
    b.begin("tire")
    b.add_cylinder_x((0.0, 0.0, 0.0), 0.34, 0.13, segments=18)
    b.end()
    b.begin("rim")
    b.add_cylinder_x((0.10, 0.0, 0.0), 0.20, 0.045, segments=14)
    b.add_cylinder_x((-0.10, 0.0, 0.0), 0.20, 0.045, segments=14)
    b.end()
    materials = {
        "tire": standard_material("tire", (0.05, 0.05, 0.06, 1.0), metallic=0.0, roughness=0.92),
        "rim": standard_material("rim", (0.72, 0.74, 0.78, 1.0), metallic=0.90, roughness=0.25),
    }
    data = b.build(materials)
    with open(os.path.join(MODELS, "wheel.glb"), "wb") as fh:
        fh.write(data)
    print("  model   wheel (%d bytes)" % len(data))


def build_car(name, body, accent, wheelbase, track, length, height):
    """Assemble one car mesh from boxes and cylinders (wheels are separate)."""
    b = MeshBuilder()
    half_len = length * 0.5
    half_track = track * 0.5

    # ---- chassis ---------------------------------------------------------
    b.begin("body")
    b.add_box((0.0, 0.42, 0.0), (track, 0.34, length))
    # tapered nose
    b.add_box((0.0, 0.40, half_len * 0.72), (track * 0.94, 0.30, length * 0.30),
              taper=(0.82, 0.75))
    # side skirts
    b.add_box((0.0, 0.26, 0.0), (track * 1.04, 0.14, length * 0.62))
    b.end()

    # ---- cabin -----------------------------------------------------------
    b.begin("glass")
    b.add_box((0.0, 0.74, -0.10), (track * 0.80, 0.34, length * 0.42),
              taper=(0.72, 0.55))
    b.end()

    b.begin("body")
    # roof
    b.add_box((0.0, 0.90, -0.22), (track * 0.62, 0.10, length * 0.28))
    # rear wing
    b.add_box((0.0, 0.86, -half_len * 0.86), (track * 0.92, 0.07, 0.34))
    b.add_box((-half_track * 0.80, 0.68, -half_len * 0.86), (0.09, 0.36, 0.16))
    b.add_box((half_track * 0.80, 0.68, -half_len * 0.86), (0.09, 0.36, 0.16))
    # front splitter
    b.add_box((0.0, 0.24, half_len * 0.94), (track * 0.90, 0.08, 0.26))
    b.end()

    # ---- wheel arches only; the wheels themselves are a separate mesh ----
    b.begin("body")
    b.add_box((-half_track * 0.92, 0.52, wheelbase * 0.5), (0.16, 0.30, 0.72))
    b.add_box((half_track * 0.92, 0.52, wheelbase * 0.5), (0.16, 0.30, 0.72))
    b.add_box((-half_track * 0.92, 0.52, -wheelbase * 0.5), (0.16, 0.30, 0.72))
    b.add_box((half_track * 0.92, 0.52, -wheelbase * 0.5), (0.16, 0.30, 0.72))
    b.end()

    # ---- lights ----------------------------------------------------------
    for sx in (-1, 1):
        b.begin("headlight")
        b.add_box((sx * half_track * 0.52, 0.46, half_len * 0.97), (0.30, 0.12, 0.06))
        b.end()
        b.begin("taillight")
        b.add_box((sx * half_track * 0.52, 0.48, -half_len * 0.99), (0.30, 0.10, 0.05))
        b.end()

    materials = {
        "body": standard_material("body", (*body, 1.0), metallic=0.65, roughness=0.28),
        "glass": standard_material("glass", (0.06, 0.08, 0.12, 0.72), metallic=0.30, roughness=0.08),
        "tire": standard_material("tire", (0.05, 0.05, 0.06, 1.0), metallic=0.0, roughness=0.92),
        "rim": standard_material("rim", (0.72, 0.74, 0.78, 1.0), metallic=0.90, roughness=0.25),
        "headlight": standard_material("headlight", (0.95, 0.95, 0.88, 1.0),
                                       roughness=0.10, emissive=(0.85, 0.85, 0.70)),
        "taillight": standard_material("taillight", (0.70, 0.05, 0.05, 1.0),
                                       roughness=0.20, emissive=(0.60, 0.03, 0.03)),
    }

    data = b.build(materials)
    path = os.path.join(MODELS, name + ".glb")
    with open(path, "wb") as fh:
        fh.write(data)
    print("  model   %s (%d bytes)" % (name, len(data)))
    return {
        "id": name,
        "wheelbase": wheelbase,
        "track": track,
        "length": length,
        "height": height,
        "half_length": length * 0.5,
        "half_track": track * 0.5,
        "wheel_radius": 0.34,
    }


# ---------------------------------------------------------------------------
# textures
# ---------------------------------------------------------------------------

def value_noise(size, cells, seed):
    """Cheap tileable value noise."""
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    img = Image.new("L", (size, size))
    px = img.load()
    step = size / cells
    for y in range(size):
        gy = y / step
        y0 = int(gy) % cells
        y1 = (y0 + 1) % cells
        fy = gy - int(gy)
        fy = fy * fy * (3 - 2 * fy)
        for x in range(size):
            gx = x / step
            x0 = int(gx) % cells
            x1 = (x0 + 1) % cells
            fx = gx - int(gx)
            fx = fx * fx * (3 - 2 * fx)
            v00 = grid[y0][x0]
            v10 = grid[y0][x1]
            v01 = grid[y1][x0]
            v11 = grid[y1][x1]
            top = v00 + (v10 - v00) * fx
            bot = v01 + (v11 - v01) * fx
            px[x, y] = int(255 * (top + (bot - top) * fy))
    return img


def fbm(size, seed, octaves=4):
    acc = Image.new("F", (size, size), 0.0)
    ap = acc.load()
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        cells = 2 ** (o + 2)
        n = value_noise(size, cells, seed + o * 977)
        np_ = n.load()
        for y in range(size):
            for x in range(size):
                ap[x, y] += amp * (np_[x, y] / 255.0)
        total += amp
        amp *= 0.5
    for y in range(size):
        for x in range(size):
            ap[x, y] /= total
    return acc


def tint(noise, low, high):
    """Map a float noise image onto a colour ramp."""
    img = Image.new("RGB", noise.size)
    px = img.load()
    np_ = noise.load()
    for y in range(noise.size[1]):
        for x in range(noise.size[0]):
            t = np_[x, y]
            px[x, y] = tuple(int(255 * (low[i] + (high[i] - low[i]) * t)) for i in range(3))
    return img


def make_surface_textures():
    size = 256
    specs = [
        ("asphalt", (0.055, 0.058, 0.065), (0.20, 0.21, 0.23), 3),
        ("grass", (0.06, 0.20, 0.05), (0.28, 0.52, 0.14), 5),
        ("sand", (0.45, 0.34, 0.17), (0.86, 0.74, 0.48), 4),
        ("snow", (0.62, 0.66, 0.74), (0.99, 1.00, 1.00), 4),
        ("dirt", (0.20, 0.14, 0.09), (0.46, 0.35, 0.24), 5),
    ]
    for name, low, high, seed in specs:
        n = fbm(size, seed, octaves=4)
        img = tint(n, low, high)
        img = img.filter(ImageFilter.GaussianBlur(0.4))
        img.save(os.path.join(TEXTURES, name + ".png"), optimize=True)
        print("  texture %s.png" % name)

    # curb: alternating red / white blocks (tileable, 4 blocks)
    curb = Image.new("RGB", (size, size), (200, 200, 200))
    d = ImageDraw.Draw(curb)
    block = size // 4
    for i in range(4):
        if i % 2 == 0:
            d.rectangle([0, i * block, size, (i + 1) * block], fill=(205, 32, 36))
        else:
            d.rectangle([0, i * block, size, (i + 1) * block], fill=(238, 238, 240))
    curb.save(os.path.join(TEXTURES, "curb.png"), optimize=True)
    print("  texture curb.png")

    # checkered finish line
    fin = Image.new("RGB", (size, size), (20, 20, 22))
    d = ImageDraw.Draw(fin)
    block = size // 8
    for i in range(8):
        for j in range(8):
            if (i + j) % 2 == 0:
                d.rectangle([i * block, j * block, (i + 1) * block, (j + 1) * block],
                            fill=(245, 245, 245))
    fin.save(os.path.join(TEXTURES, "finish_line.png"), optimize=True)
    print("  texture finish_line.png")

    # skid mark decal (alpha)
    skid = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(skid)
    d.rectangle([6, 0, 58, 64], fill=(12, 12, 14, 170))
    skid = skid.filter(ImageFilter.GaussianBlur(5))
    skid.save(os.path.join(TEXTURES, "skid.png"), optimize=True)
    print("  texture skid.png")

    # smoke puff (alpha)
    smoke = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(smoke)
    d.ellipse([4, 4, 60, 60], fill=(215, 215, 220, 150))
    smoke = smoke.filter(ImageFilter.GaussianBlur(6))
    smoke.save(os.path.join(TEXTURES, "smoke.png"), optimize=True)
    print("  texture smoke.png")


def make_ui_textures():
    # vertical sky gradient, also used as the menu backdrop tint
    sky = Image.new("RGB", (16, 256))
    px = sky.load()
    for y in range(256):
        t = y / 255.0
        px_top = (28, 62, 128)
        px_bot = (186, 208, 232)
        col = tuple(int(255 * (px_top[i] + (px_bot[i] - px_top[i]) * t)) for i in range(3))
        for x in range(16):
            px[x, y] = col
    sky.save(os.path.join(TEXTURES, "sky_gradient.png"), optimize=True)
    print("  texture sky_gradient.png")

    # radial glow used for the menu / results vignette
    glow = Image.new("L", (256, 256), 0)
    px = glow.load()
    for y in range(256):
        for x in range(256):
            dx = (x - 128) / 128.0
            dy = (y - 128) / 128.0
            r = min(1.0, math.sqrt(dx * dx + dy * dy))
            px[x, y] = int(255 * (1.0 - r) ** 2)
    glow.save(os.path.join(TEXTURES, "glow.png"), optimize=True)
    print("  texture glow.png")

    # asphalt decal for the minimap panel
    panel = Image.new("RGBA", (32, 32), (12, 16, 24, 205))
    panel.save(os.path.join(TEXTURES, "panel.png"), optimize=True)
    print("  texture panel.png")


# ---------------------------------------------------------------------------
# audio
# ---------------------------------------------------------------------------

def write_wav(path, samples):
    """samples: iterable of floats in [-1, 1]."""
    frames = bytearray()
    for s in samples:
        v = max(-1.0, min(1.0, s))
        frames.extend(struct.pack("<h", int(v * 32000)))
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(SAMPLE_RATE)
        fh.writeframes(bytes(frames))
    print("  audio   %s" % os.path.basename(path))


def engine_loop():
    """Seamlessly loopable engine tone: fundamental + harmonics + roughness."""
    seconds = 1.0
    n = int(SAMPLE_RATE * seconds)
    base = 55.0  # loops exactly because all partials are integer multiples
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        v = 0.0
        v += 0.50 * math.sin(2 * math.pi * base * t)
        v += 0.26 * math.sin(2 * math.pi * base * 2 * t)
        v += 0.16 * math.sin(2 * math.pi * base * 3 * t)
        v += 0.09 * math.sin(2 * math.pi * base * 5 * t)
        v += 0.06 * math.sin(2 * math.pi * base * 7 * t)
        # combustion rattle
        v += 0.10 * math.sin(2 * math.pi * base * 11 * t) * (0.5 + 0.5 * math.sin(2 * math.pi * 7 * t))
        out.append(v * 0.42)
    return out


def tyre_skid():
    seconds = 0.8
    n = int(SAMPLE_RATE * seconds)
    rng = random.Random(7)
    out = []
    lp = 0.0
    for i in range(n):
        white = rng.uniform(-1, 1)
        lp = lp * 0.72 + white * 0.28
        env = 1.0
        # fade the very ends so the loop point is inaudible
        edge = min(i, n - i) / (0.05 * n)
        env = min(1.0, edge)
        tone = math.sin(2 * math.pi * 1180 * (i / SAMPLE_RATE))
        out.append((lp * 1.5 + tone * 0.25) * 0.30 * env)
    return out


def crash_sound():
    seconds = 0.9
    n = int(SAMPLE_RATE * seconds)
    rng = random.Random(21)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / n
        white = rng.uniform(-1, 1)
        lp = lp * 0.55 + white * 0.45
        env = (1.0 - t) ** 2.2
        thud = math.sin(2 * math.pi * 70 * (i / SAMPLE_RATE)) * (1.0 - t) ** 4
        out.append((lp * 1.2 + thud * 0.9) * env * 0.75)
    return out


def beep(freq, seconds, shape="sine", gain=0.5):
    n = int(SAMPLE_RATE * seconds)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        ph = 2 * math.pi * freq * t
        if shape == "square":
            v = 1.0 if math.sin(ph) >= 0 else -1.0
        elif shape == "saw":
            v = 2.0 * ((freq * t) % 1.0) - 1.0
        else:
            v = math.sin(ph)
        env = min(1.0, i / (0.01 * SAMPLE_RATE)) * (1.0 - i / n) ** 0.8
        out.append(v * env * gain)
    return out


def countdown_tone(final=False):
    if final:
        return beep(880.0, 0.75, "square", 0.45)
    return beep(440.0, 0.22, "square", 0.40)


def checkpoint_ping():
    a = beep(1320.0, 0.16, "sine", 0.40)
    b = beep(1760.0, 0.22, "sine", 0.32)
    return a + b


def ui_click():
    return beep(660.0, 0.06, "square", 0.28) + beep(990.0, 0.05, "sine", 0.20)


def ui_back():
    return beep(440.0, 0.07, "square", 0.26) + beep(300.0, 0.09, "sine", 0.20)


def menu_music():
    """Two-bar loop: bass line plus arpeggio, written for low CPU cost."""
    bpm = 132.0
    beat = 60.0 / bpm
    total = beat * 8
    n = int(SAMPLE_RATE * total)
    out = [0.0] * n
    scale = [0, 3, 5, 7, 10, 12, 15]
    root = 110.0

    def add(freq, start, dur, gain, shape="saw"):
        s0 = int(start * SAMPLE_RATE)
        count = int(dur * SAMPLE_RATE)
        for i in range(count):
            idx = s0 + i
            if idx >= n:
                break
            t = i / SAMPLE_RATE
            ph = 2 * math.pi * freq * t
            if shape == "saw":
                v = 2.0 * ((freq * t) % 1.0) - 1.0
            elif shape == "square":
                v = 1.0 if math.sin(ph) >= 0 else -1.0
            else:
                v = math.sin(ph)
            env = min(1.0, i / (0.008 * SAMPLE_RATE))
            env *= (1.0 - i / count) ** 1.6
            out[idx] += v * env * gain

    bass_pattern = [0, 0, 5, 5, 3, 3, 7, 7]
    for k, step in enumerate(bass_pattern):
        add(root * (2 ** (step / 12.0)) * 0.5, k * beat, beat * 0.92, 0.22, "saw")
    arp = [0, 4, 2, 5, 1, 3, 6, 4]
    for k in range(16):
        semi = scale[arp[k % len(arp)] % len(scale)]
        add(root * 4 * (2 ** (semi / 12.0)), k * beat * 0.5, beat * 0.42, 0.10, "square")
    for k in range(8):
        add(root * 8, k * beat, beat * 0.20, 0.05, "sine")

    peak = max(1e-6, max(abs(v) for v in out))
    return [v / peak * 0.55 for v in out]


def victory_jingle():
    notes = [(523.25, 0.16), (659.25, 0.16), (783.99, 0.16), (1046.5, 0.46)]
    out = []
    for f, d in notes:
        out.extend(beep(f, d, "square", 0.34))
    return out


def make_audio():
    write_wav(os.path.join(AUDIO, "engine_loop.wav"), engine_loop())
    write_wav(os.path.join(AUDIO, "skid_loop.wav"), tyre_skid())
    write_wav(os.path.join(AUDIO, "crash.wav"), crash_sound())
    write_wav(os.path.join(AUDIO, "countdown_beep.wav"), countdown_tone(False))
    write_wav(os.path.join(AUDIO, "countdown_go.wav"), countdown_tone(True))
    write_wav(os.path.join(AUDIO, "checkpoint.wav"), checkpoint_ping())
    write_wav(os.path.join(AUDIO, "ui_click.wav"), ui_click())
    write_wav(os.path.join(AUDIO, "ui_back.wav"), ui_back())
    write_wav(os.path.join(AUDIO, "music_menu.wav"), menu_music())
    write_wav(os.path.join(AUDIO, "victory.wav"), victory_jingle())


# ---------------------------------------------------------------------------
# fonts
# ---------------------------------------------------------------------------

def make_fonts():
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for src in candidates:
        if os.path.exists(src):
            dst = os.path.join(FONTS, "UI-Bold.ttf" if "Bold" in src else "UI.ttf")
            shutil.copyfile(src, dst)
            print("  font    %s" % os.path.basename(dst))
    # DejaVu carries Latin only; the HUD needs a symbol fallback for the
    # tachometer needle and gear markers, which we draw as vector shapes instead.


def main():
    for d in (MODELS, TEXTURES, AUDIO, FONTS):
        os.makedirs(d, exist_ok=True)
    print("generating cars")
    build_wheel()
    specs = []
    for spec in CAR_SPECS:
        specs.append(build_car(*spec))
    with open(os.path.join(MODELS, "car_specs.json"), "w") as fh:
        json.dump(specs, fh, indent=2)
    print("  model   car_specs.json")
    print("generating textures")
    make_surface_textures()
    make_ui_textures()
    print("generating audio")
    make_audio()
    print("installing fonts")
    make_fonts()
    print("done")


if __name__ == "__main__":
    main()
