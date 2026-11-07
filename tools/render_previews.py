"""Render README preview images for Gebbo's Bottomless Bag.

Recreates the alert panel from UI.lua (same geometry, colours, glow layers and
animation formulas) using the addon's own media/*.tga textures. The pull icons
and the bag badge are original cartoon art drawn here, because in-game those
slots show Blizzard's spell/item icons.

Needs Pillow (pip install pillow). Not part of the addon; WoW never loads it.

usage (from the repo root):
  python tools/render_previews.py                     # everything
  python tools/render_previews.py media images banner # just one: banner | six | stack | gif
"""
import math, os, sys, random
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = sys.argv[1] if len(sys.argv) > 1 else os.path.join(_ROOT, "media")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(_ROOT, "images")
os.makedirs(OUT, exist_ok=True)
# Friz Quadrata (the game's font) isn't redistributable; Georgia Bold is a close-enough stand-in
FONT = next((f for f in ("C:/Windows/Fonts/georgiab.ttf", "/Library/Fonts/Georgia Bold.ttf",
                         "/usr/share/fonts/truetype/msttcorefonts/Georgia_Bold.ttf") if os.path.exists(f)),
            "DejaVuSerif-Bold.ttf")
SS = 2  # supersampling for stills

# ---------------------------------------------------------------- data (Data.lua)
W, H, ICON, CAMEO, GAP, TOTAL_H = 448, 132, 100, 84, 14, 40
MID_L, MID_R = 12 + ICON + 18, 12 + CAMEO + 14
ORDER = ["crit", "haste", "mastery", "vers"]
STAT = {
    "crit":    ("Crit",    (1.00, 0.40, 0.32)),
    "haste":   ("Haste",   (1.00, 0.81, 0.27)),
    "mastery": ("Mastery", (0.74, 0.52, 1.00)),
    "vers":    ("Vers",    (0.36, 0.95, 0.70)),
}
ALL = ORDER
ARTS = {
    "salmon":    dict(name="50-Lb Midnight Salmon",     stats=ALL,         c=(1.00, 0.80, 0.30), title="JACKPOT!",      bgA=(0.40, 0.04, 0.70), bgB=(1.00, 0.45, 0.00), rainbow=True),
    "scroll":    dict(name="Tattered Tortollan Scroll", stats=["mastery"], c=(0.74, 0.52, 1.00), title="MASTERY SURGE", bgA=(0.12, 0.03, 0.38), bgB=(0.52, 0.20, 0.92)),
    "totem":     dict(name="Brittle Torga Totem",       stats=["vers"],    c=(0.36, 0.95, 0.70), title="VERSATILITY",   bgA=(0.01, 0.20, 0.20), bgB=(0.08, 0.66, 0.48), casts=True),
    "gralstone": dict(name="Slick and Slimy Gralstone", stats=["haste"],   c=(1.00, 0.81, 0.27), title="HASTE RUSH",    bgA=(0.36, 0.16, 0.00), bgB=(0.92, 0.66, 0.06)),
    "seashell":  dict(name="Seriously Sharp Seashell",  stats=["crit"],    c=(1.00, 0.40, 0.32), title="CRIT CLIMB",    bgA=(0.36, 0.02, 0.04), bgB=(0.92, 0.32, 0.18)),
    "voidfin":   dict(name="Rotting Voidfin",           stats=ALL,         c=(0.55, 0.85, 0.30), title="EW. VOIDFIN",   bgA=(0.06, 0.02, 0.12), bgB=(0.20, 0.38, 0.05), danger=True),
}


def HSV(h, s, v):
    h = (h % 1) * 6
    i = math.floor(h)
    f = h - i
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i % 6]


def lighten(c, k):
    return tuple(x + (1 - x) * k for x in c)


def rgb255(c):
    return tuple(max(0, min(255, int(round(x * 255)))) for x in c[:3])


# ---------------------------------------------------------------- textures
_tex = {}


def tex(name):
    if name not in _tex:
        _tex[name] = Image.open(os.path.join(MEDIA, name + ".tga")).convert("RGBA")
    return _tex[name]


_fonts = {}


def font(px):
    px = max(6, int(round(px)))
    if px not in _fonts:
        _fonts[px] = ImageFont.truetype(FONT, px)
    return _fonts[px]


def prep(src, w, h, color=(1, 1, 1), alpha=1.0, angle=0.0, desat=False, crop=None):
    im = src
    if crop:
        sw, sh = im.size
        im = im.crop((int(crop[0] * sw), int(crop[1] * sh), int(crop[2] * sw), int(crop[3] * sh)))
    if desat:
        a = im.getchannel("A")
        g = im.convert("L")
        im = Image.merge("RGBA", (g, g, g, a))
    im = im.resize((max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS)
    if angle:
        im = im.rotate(angle, resample=Image.BICUBIC)
    r, g, b, a = im.split()
    cr, cg, cb = [max(0.0, min(1.0, x)) for x in color[:3]]
    al = max(0.0, min(1.0, alpha))
    r = r.point(lambda v: v * cr)
    g = g.point(lambda v: v * cg)
    b = b.point(lambda v: v * cb)
    a = a.point(lambda v: v * al)
    return Image.merge("RGBA", (r, g, b, a))


class Canvas:
    def __init__(self, img):
        self.img = img
        self.draw = ImageDraw.Draw(self.img)

    def _boxes(self, im, x, y, clip):
        x, y = int(round(x)), int(round(y))
        cw, ch = self.img.size
        L, T, Rr, B = 0, 0, cw, ch
        if clip:
            L, T, Rr, B = max(L, int(clip[0])), max(T, int(clip[1])), min(Rr, int(clip[2])), min(B, int(clip[3]))
        x0, y0 = max(x, L), max(y, T)
        x1, y1 = min(x + im.width, Rr), min(y + im.height, B)
        if x1 <= x0 or y1 <= y0:
            return None
        return (x0, y0, x1, y1), (x0 - x, y0 - y, x1 - x, y1 - y)

    def put(self, src, x, y, w, h, color=(1, 1, 1), alpha=1.0, add=False, angle=0.0,
            desat=False, crop=None, clip=None, center=False):
        if alpha <= 0.003:
            return
        if center:
            x, y = x - w / 2, y - h / 2
        im = prep(src, w, h, color, alpha, angle, desat, crop)
        self.blit(im, x, y, add, clip)

    def blit(self, im, x, y, add=False, clip=None):
        bx = self._boxes(im, x, y, clip)
        if not bx:
            return
        dst, srcb = bx
        piece = im.crop(srcb)
        if add:
            a = piece.getchannel("A")
            rgb = ImageChops.multiply(piece.convert("RGB"), Image.merge("RGB", (a, a, a)))
            region = self.img.crop(dst)
            self.img.paste(ImageChops.add(region, rgb), dst)
        else:
            self.img.paste(piece.convert("RGB"), dst, piece.getchannel("A"))

    def rect(self, x0, y0, x1, y1, color, alpha=1.0, add=False):
        w, h = int(round(x1 - x0)), int(round(y1 - y0))
        if w <= 0 or h <= 0:
            return
        im = Image.new("RGBA", (w, h), rgb255(color) + (int(alpha * 255),))
        self.blit(im, x0, y0, add)

    def text(self, x, y, s, px, color, outline=2.0, anchor="mt"):
        self.draw.text((x, y), s, font=font(px), fill=rgb255(color), anchor=anchor,
                       stroke_width=max(1, int(round(outline))), stroke_fill=(0, 0, 0))

    def text_width(self, s, px):
        return self.draw.textlength(s, font=font(px))


def hgrad(w, h, a, b):
    w, h = max(1, int(round(w))), max(1, int(round(h)))
    row = Image.new("RGB", (w, 1))
    for i in range(w):
        f = i / max(1, w - 1)
        row.putpixel((i, 0), rgb255(tuple(a[k] + (b[k] - a[k]) * f for k in range(3))))
    return row.resize((w, h))


# ---------------------------------------------------------------- original cartoon icons
def _ss_canvas(bg_in, bg_out):
    S = 512
    im = Image.new("RGBA", (S, S))
    rad = Image.radial_gradient("L").resize((S, S))  # 0 centre -> 255 edge
    inner = Image.new("RGBA", (S, S), bg_in + (255,))
    outer = Image.new("RGBA", (S, S), bg_out + (255,))
    im = Image.composite(outer, inner, rad)
    return im, ImageDraw.Draw(im)


def _sparkle(d, x, y, r, col=(255, 255, 240, 255)):
    pts = [(x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y), (x + r * 0.22, y + r * 0.22),
           (x, y + r), (x - r * 0.22, y + r * 0.22), (x - r, y), (x - r * 0.22, y - r * 0.22)]
    d.polygon(pts, fill=col)


def _done(im):
    return im.resize((256, 256), Image.LANCZOS)


OL = (28, 14, 20, 255)


def icon_salmon():
    im, d = _ss_canvas((40, 70, 140), (8, 14, 40))
    d.polygon([(60, 256), (10, 150), (10, 362)], fill=(232, 96, 82, 255), outline=OL, width=14)  # tail
    d.polygon([(200, 150), (270, 70), (330, 150)], fill=(232, 96, 82, 255), outline=OL, width=12)  # fin
    d.ellipse((60, 140, 480, 372), fill=(250, 128, 100, 255), outline=OL, width=16)
    d.chord((76, 250, 464, 362), 0, 180, fill=(255, 214, 180, 255))
    d.arc((60, 140, 480, 372), 0, 360, fill=OL, width=16)
    for sx, sy in [(170, 205), (230, 185), (290, 200), (200, 245), (260, 235)]:
        d.ellipse((sx - 9, sy - 9, sx + 9, sy + 9), fill=(170, 60, 60, 255))
    d.arc((330, 170, 420, 340), 110, 250, fill=OL, width=10)  # gill
    d.ellipse((392, 200, 440, 248), fill=(255, 255, 255, 255), outline=OL, width=8)
    d.ellipse((410, 214, 432, 236), fill=(20, 20, 30, 255))
    d.polygon([(470, 270), (440, 262), (442, 286)], fill=OL)
    for x, y, r in [(110, 90, 34), (420, 410, 28), (80, 420, 18), (460, 110, 20)]:
        _sparkle(d, x, y, r, (255, 236, 150, 255))
    return _done(im)


def icon_scroll():
    im, d = _ss_canvas((90, 50, 170), (16, 6, 40))
    d.polygon([(120, 120), (392, 120), (392, 200), (372, 230), (395, 270), (380, 330), (392, 392), (120, 392)],
              fill=(240, 222, 178, 255), outline=OL, width=12)
    for y0 in (90, 362):
        d.rounded_rectangle((80, y0, 432, y0 + 60), 30, fill=(205, 170, 110, 255), outline=OL, width=12)
        d.line((110, y0 + 18, 400, y0 + 18), fill=(250, 232, 190, 255), width=8)
    d.ellipse((186, 186, 326, 326), outline=(150, 80, 240, 255), width=12)
    d.polygon([(256, 200), (300, 290), (212, 290)], outline=(150, 80, 240, 255), width=10)
    for i, y in enumerate((172, 344)):
        d.line((150, y, 360 - i * 40, y), fill=(130, 90, 170, 255), width=8)
    for x, y, r in [(256, 256, 22), (110, 80, 22), (420, 440, 26)]:
        _sparkle(d, x, y, r, (230, 200, 255, 255))
    return _done(im)


def icon_totem():
    im, d = _ss_canvas((20, 120, 100), (4, 30, 30))
    d.polygon([(120, 150), (40, 110), (80, 190)], fill=(60, 180, 140, 255), outline=OL, width=10)
    d.polygon([(392, 150), (472, 110), (432, 190)], fill=(60, 180, 140, 255), outline=OL, width=10)
    blocks = [(150, 90, 362, 210), (130, 210, 382, 330), (110, 330, 402, 460)]
    for i, (x0, y0, x1, y1) in enumerate(blocks):
        d.rounded_rectangle((x0, y0, x1, y1), 18, fill=(70, 200, 150, 255), outline=OL, width=12)
        d.rectangle((x1 - 50, y0 + 10, x1 - 12, y1 - 10), fill=(40, 150, 110, 255))
        cy = (y0 + y1) // 2
        d.rectangle((x0 + 40, cy - 28, x0 + 85, cy - 6), fill=OL)
        d.rectangle((x1 - 110, cy - 28, x1 - 65, cy - 6), fill=OL)
        d.line((x0 + 50, cy + 25, x1 - 75, cy + 25), fill=OL, width=10)
    d.line((300, 100, 280, 150, 310, 190, 290, 230), fill=OL, width=7)
    d.line((170, 360, 200, 400, 180, 440), fill=OL, width=7)
    for x, y, r in [(70, 420, 22), (450, 400, 26), (256, 50, 22)]:
        _sparkle(d, x, y, r, (200, 255, 230, 255))
    return _done(im)


def icon_gralstone():
    im, d = _ss_canvas((170, 110, 20), (40, 18, 0))
    for y in (190, 250, 310):  # speed lines
        d.line((20, y, 120, y), fill=(255, 230, 140, 255), width=12)
    d.polygon([(150, 160), (250, 100), (380, 130), (450, 240), (420, 360), (300, 400), (170, 380), (120, 270)],
              fill=(240, 180, 50, 255), outline=OL, width=14)
    d.polygon([(190, 180), (250, 140), (330, 150), (280, 200)], fill=(255, 236, 150, 255))
    d.ellipse((350, 190, 390, 230), fill=(255, 250, 220, 255))
    for x, y, l in [(200, 375, 70), (280, 395, 100), (360, 375, 55)]:  # slime drips
        d.rounded_rectangle((x - 16, y - 10, x + 16, y + l), 16, fill=(170, 230, 60, 255), outline=OL, width=8)
        d.ellipse((x - 20, y + l - 4, x + 20, y + l + 36), fill=(170, 230, 60, 255), outline=OL, width=8)
    d.chord((150, 330, 430, 410), 0, 180, fill=(170, 230, 60, 255))
    for x, y, r in [(440, 90, 26), (90, 420, 20)]:
        _sparkle(d, x, y, r, (255, 240, 170, 255))
    return _done(im)


def icon_seashell():
    im, d = _ss_canvas((170, 40, 40), (40, 6, 10))
    cx, cy = 256, 330
    box = (cx - 220, cy - 220, cx + 220, cy + 220)
    d.pieslice(box, 195, 345, fill=(240, 96, 76, 255), outline=OL, width=14)
    for k in range(1, 8):
        ang = math.radians(195 + k * 150 / 8)
        d.line((cx, cy, cx + 205 * math.cos(ang), cy + 205 * math.sin(ang)), fill=(170, 40, 40, 255), width=10)
    for k in range(0, 8):
        ang = math.radians(195 + (k + 0.5) * 150 / 8)
        d.line((cx + 70 * math.cos(ang), cy + 70 * math.sin(ang), cx + 190 * math.cos(ang), cy + 190 * math.sin(ang)),
               fill=(255, 160, 130, 255), width=6)
    d.arc(box, 195, 345, fill=OL, width=14)
    d.polygon([(cx - 60, cy - 10), (cx + 60, cy - 10), (cx + 40, cy + 50), (cx - 40, cy + 50)],
              fill=(220, 80, 64, 255), outline=OL, width=12)
    _sparkle(d, 140, 140, 40, (255, 255, 255, 255))
    d.ellipse((400, 420, 440, 470), fill=(220, 20, 30, 255), outline=OL, width=6)
    d.polygon([(420, 395), (402, 430), (438, 430)], fill=(220, 20, 30, 255))
    _sparkle(d, 430, 120, 22, (255, 220, 200, 255))
    return _done(im)


def icon_voidfin():
    im, d = _ss_canvas((50, 80, 30), (8, 12, 6))
    fish = tex("voidfin").resize((470, 470), Image.LANCZOS)
    im.alpha_composite(fish, (21, 30))
    return _done(im)


def icon_bag():
    im, d = _ss_canvas((40, 150, 150), (20, 20, 70))
    d.polygon([(300, 130), (350, 40), (395, 70), (335, 150)], fill=(250, 128, 100, 255), outline=OL, width=10)  # fish tail
    d.ellipse((190, 60, 250, 120), fill=(255, 210, 70, 255), outline=OL, width=8)  # coin
    d.polygon([(130, 110), (170, 140), (205, 100), (256, 135), (305, 100), (342, 140), (382, 110), (350, 200), (162, 200)],
              fill=(185, 125, 70, 255), outline=OL, width=14)  # ruffled opening
    d.polygon([(190, 190), (322, 190), (300, 240), (212, 240)], fill=(150, 95, 50, 255), outline=OL, width=14)  # neck
    d.ellipse((76, 215, 436, 480), fill=(150, 95, 50, 255), outline=OL, width=16)  # body
    d.chord((92, 330, 420, 466), 10, 170, fill=(118, 70, 34, 255))
    d.ellipse((120, 270, 190, 360), fill=(185, 125, 70, 255))
    d.rounded_rectangle((176, 205, 336, 240), 16, fill=(250, 200, 70, 255), outline=OL, width=10)  # rope tie
    d.line((300, 238, 330, 300), fill=(250, 200, 70, 255), width=12)
    d.ellipse((250, 330, 330, 380), fill=(95, 55, 28, 255))  # patch
    for x, y, r in [(80, 90, 30), (450, 180, 24), (440, 430, 20)]:
        _sparkle(d, x, y, r, (255, 240, 170, 255))
    return _done(im)


ICONS = {}


def pull_icon(key):
    if key not in ICONS:
        ICONS[key] = {"salmon": icon_salmon, "scroll": icon_scroll, "totem": icon_totem,
                      "gralstone": icon_gralstone, "seashell": icon_seashell,
                      "voidfin": icon_voidfin, "bag": icon_bag}[key]()
    return ICONS[key]


_badge_icon = None


def badge_icon():
    global _badge_icon
    if _badge_icon is None:
        ic = pull_icon("bag").crop((20, 20, 236, 236)).resize((256, 256), Image.LANCZOS)  # texcoord 0.08-0.92
        mask = tex("badge_mask").getchannel("A")
        ic.putalpha(ImageChops.multiply(ic.getchannel("A"), mask))
        _badge_icon = ic
    return _badge_icon


# ---------------------------------------------------------------- ants (stand-in for IconAlertAnts)
_ants = {}


def ants_tex(frame):
    if frame in _ants:
        return _ants[frame]
    S = 288
    core = Image.new("L", (S, S))
    d = ImageDraw.Draw(core)
    n, half = 6.0, S * 0.355
    pts = []
    for i in range(2400):
        a = i / 2400 * math.tau
        c, s = math.cos(a), math.sin(a)
        r = half / (abs(c) ** n + abs(s) ** n) ** (1 / n)
        pts.append((S / 2 + r * c, S / 2 + r * s))
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + math.dist(pts[i], pts[i - 1]))
    per = acc[-1] / 22
    ph = frame / 22
    for p, l in zip(pts, acc):
        if (l / per + ph) % 1 < 0.55:
            d.ellipse((p[0] - 3.2, p[1] - 3.2, p[0] + 3.2, p[1] + 3.2), fill=255)
    glow = core.filter(ImageFilter.GaussianBlur(7)).point(lambda v: min(255, v * 2.4))
    a = ImageChops.lighter(glow, core)
    white = Image.new("L", (S, S), 255)
    im = Image.merge("RGBA", (white, white, white, a))
    _ants[frame] = im
    return im


# ---------------------------------------------------------------- the alert panel (UI.lua BuildAlert + UI_Tick)
def gem_row(C, ox, oy, s, lit_values):
    """lit_values: stat -> text (None = unlit)."""
    for i, st in enumerate(ORDER):
        label, col = STAT[st]
        x = ox + (MID_L + i * 52) * s
        cy = oy + (H - 26 - 11) * s
        gx = x + 9 * s
        v = lit_values.get(st)
        if v is not None:
            C.put(tex("glow_outer"), gx, cy, 30 * s, 30 * s, col, 0.9, add=True, center=True)
            C.put(tex("gem_white"), gx, cy, 18 * s, 18 * s, col, 1.0, center=True)
            C.text(gx, cy, label[0], 9 * s, (1, 1, 1), 1.3 * s, anchor="mm")
            C.text(x + 20 * s, cy, v, 11 * s, lighten(col, 0.35), 1.0 * s, anchor="lm")
        else:
            C.put(tex("gem_white"), gx, cy, 18 * s, 18 * s, col, 0.28, desat=True, center=True)
            C.text(gx, cy, label[0], 9 * s, (0.45, 0.45, 0.45), 1.0 * s, anchor="mm")


def fmt_amt(v):
    n = int(math.floor(abs(v) + 0.5))
    return ("-" if v < 0 else "+") + f"{n:,}"


def fmt_chip(v):
    n = int(math.floor(abs(v) + 0.5))
    return ("-" if v < 0 else "") + f"{n:,}"


def draw_panel(C, key, cx, cy, s, t, state):
    """Draw one alert centred at (cx, cy) px. s = px per UI unit. t = seconds since the pull landed.
    state: remain, duration, amount, casts_left, casts_total"""
    art = ARTS[key]
    rainbow, danger = art.get("rainbow", False), art.get("danger", False)
    cr, cg, cb = art["c"]
    # entrance pop and Voidfin wobble
    if t < 0.25:
        s = s * (1.35 - 1.4 * t)
    if danger and t < 0.5:
        rnd = random.Random(int(t * 60))
        cx += rnd.randint(-5, 5) * s
        cy += rnd.randint(-5, 5) * s
    ox, oy = cx - W * s / 2, cy - H * s / 2
    X = lambda u: ox + u * s
    Y = lambda u: oy + u * s

    if rainbow:
        r, g, b = HSV(t * 0.45, 0.85, 1)
        r2, g2, b2 = HSV(t * 0.45 + 0.5, 0.75, 1)
    else:
        r, g, b = cr, cg, cb
        r2, g2, b2 = lighten((cr, cg, cb), 0.3)
    beat = abs(math.sin(t * 7)) if danger else 0.5 + 0.5 * math.sin(t * 4)

    # outer glow (A.outer)
    if rainbow:
        oc, oa, ic, ia = (r, g, b), 0.55 + 0.15 * math.sin(t * 5), (r2, g2, b2), 0.35 + 0.15 * math.sin(t * 4)
    elif danger:
        oc, oa, ic, ia = (0.45, 1, 0.15), 0.4 + 0.5 * beat, (0.4, 1, 0.1), 0.3 + 0.5 * beat
    else:
        oc, oa, ic, ia = (r, g, b), 0.45 + 0.3 * beat, (r2, g2, b2), 0.3 + 0.15 * math.sin(t * 4)
    for _ in range(2):  # ADD glow, doubled to approximate the game's brighter additive bloom
        C.put(tex("glow_outer"), X(-36), Y(-36), (W + 72) * s, (H + 72) * s, oc, oa, add=True)

    # panel body: gradient at 0.92 alpha, inner glow, bubbles, edges
    grad = hgrad(W * s, H * s, art["bgA"], art["bgB"]).convert("RGBA")
    grad.putalpha(int(0.92 * 255))
    C.blit(grad, X(0), Y(0))
    C.put(tex("glow_inner"), X(0), Y(0), W * s, H * s, ic, ia, add=True)
    clip = (X(0), Y(0), X(W), Y(H))
    for i in range(1, 10):
        bs = 9 + (i * 7) % 12
        d = 2.3 + (i % 3) * 0.55
        delay = i * 0.37
        lt = (t + 6.0) % (d + delay) - delay
        if lt < 0:
            continue
        p = (lt / d) ** 2  # smooth IN
        bx = MID_L - 20 + ((i * 53) % (W - MID_L - MID_R + 60)) + (10 if i % 2 == 0 else -10) * p
        by = H + 14 - (H + 28) * p
        if rainbow:
            bc = HSV(i / 9, 0.45, 1)
        elif danger:
            bc = (0.6, 1, 0.35)
        else:
            bc = lighten((r, g, b), 0.55)
        C.put(tex("bubble"), X(bx - bs / 2), Y(by - bs), bs * s, bs * s, bc, 0.9 * (1 - p), clip=clip)
    for i, (x0, y0, x1, y1) in enumerate([(0, 0, W, 2), (0, H - 2, W, H), (0, 0, 2, H), (W - 2, 0, W, H)], 1):
        if rainbow:
            ec, ea = HSV(t * 0.6 + i * 0.25, 0.9, 1), 0.9
        elif danger:
            ec, ea = (0.5, 1, 0.2), 0.5 + 0.5 * beat
        else:
            ec, ea = (r2, g2, b2), 0.85
        C.rect(X(x0), Y(y0), X(x1), Y(y1), ec, ea, add=True)

    # title / name
    if rainbow:
        tc = HSV(t * 0.8, 0.35, 1)
    elif danger:
        tc = (0.55 + 0.45 * beat, 1, 0.3)
    else:
        tc = lighten((cr, cg, cb), 0.55)
    mid = X((MID_L + W - MID_R) / 2)
    C.text(mid, Y(12), art["title"], 20 * s, tc, 2.0 * s)
    C.text(mid, Y(37), art["name"], 11 * s, (1, 0.9, 0.6), 1.0 * s)

    # bar
    rem, dur = state.get("remain"), state.get("duration")
    C.rect(X(MID_L), Y(H - 21), X(W - MID_R), Y(H - 12), (0, 0, 0), 0.6)
    if state.get("casts_total"):
        frac = state["casts_left"] / state["casts_total"]
    else:
        frac = rem / dur
    C.rect(X(MID_L), Y(H - 21), X(MID_L + (W - MID_L - MID_R) * frac), Y(H - 12), (r, g, b) if rainbow else (cr, cg, cb), 1.0)

    # amount (counts up for 0.45s) + gem row
    k = min(1, t / 0.45)
    ease = 1 - (1 - k) ** 3
    v = state["amount"] * ease
    word = "ALL STATS" if len(art["stats"]) > 1 else STAT[art["stats"][0]][0].upper()
    C.text(mid, Y(52), fmt_amt(v) + " " + word, 24 * s, (0.7, 1, 0.4) if v < 0 else (1, 1, 1), 2.0 * s)
    gem_row(C, ox, oy, s, {st: fmt_chip(v) for st in art["stats"]})

    # cameo: cartoon bag badge, or the rotten fish for the Voidfin
    bcx, bcy = X(W - 12 - CAMEO / 2), Y(H / 2)
    if danger:
        C.put(tex("glow_outer"), bcx, bcy, (CAMEO + 36) * s, (CAMEO + 36) * s, (r2, g2, b2), 0.4 + 0.5 * beat, add=True, center=True)
        C.put(tex("glow_outer"), bcx, bcy, (CAMEO + 36) * s, (CAMEO + 36) * s, (r2, g2, b2), 0.4 + 0.5 * beat, add=True, center=True)
        hs = 1 + 0.05 * math.sin(t * 3)
        C.put(tex("voidfin"), bcx, bcy, CAMEO * hs * s, CAMEO * hs * s, center=True)
    else:
        # squash-and-stretch hop, 2.04s cycle
        ht = t % 2.04
        steps = [(1, 1, 1.08, 0.92, 0.16), (1.08, 0.92, 0.95, 1.07, 0.18), (0.95, 1.07, 1, 1, 0.2)]
        sx = sy = 1.0
        acc = 0
        for a0, b0, a1, b1, dd in steps:
            if ht < acc + dd:
                f = (ht - acc) / dd
                f = f * f * (3 - 2 * f)
                sx, sy = a0 + (a1 - a0) * f, b0 + (b1 - b0) * f
                break
            acc += dd
        bw, bh = CAMEO * s * sx, CAMEO * s * sy
        ring_c = (r2, g2, b2)
        for _ in range(2):
            C.put(tex("glow_outer"), bcx, bcy, bw + 40 * s, bh + 40 * s, ring_c, 0.85 if rainbow else 0.75, add=True, center=True)
        rot = 360 * t / 3.5
        if rainbow:
            C.put(tex("ring"), bcx, bcy, bw * 1.12, bh * 1.12, angle=rot, center=True)
        else:
            C.put(tex("ring"), bcx, bcy, bw * 1.12, bh * 1.12, lighten((cr, cg, cb), 0.3), 0.6, angle=rot, center=True)
        C.put(tex("badge_rim"), bcx, bcy, bw, bh, (1, 0.82, 0.3) if rainbow else lighten((cr, cg, cb), 0.15), center=True)
        C.put(badge_icon(), bcx, bcy, bw, bh, center=True)
        C.put(tex("badge_shine"), bcx, bcy, bw, bh, center=True)

    # ===== the star: the pull's icon =====
    isc = 1 + 0.04 * math.sin(t * 5)
    icx, icy = X(12 + ICON / 2), Y(H / 2)
    I = ICON * s * isc
    if rainbow:
        f_c = HSV(t * 1.1, 1, 1)
        g2c, g2a = (0.45, 0.02, 0.95), 0.75 + 0.25 * math.sin(t * 2.5)
    else:
        f_c = (r, g, b)
        g2c, g2a = (cr * 0.6, cg * 0.6, cb * 0.6), 0.65 + 0.25 * math.sin(t * 2.5)
    for _ in range(2):
        C.put(tex("glow_outer"), icx, icy, I + 88 * s * isc, I + 88 * s * isc, g2c, g2a, add=True, center=True)
        C.put(tex("glow_outer"), icx, icy, I + 60 * s * isc, I + 60 * s * isc, f_c, 0.85 + 0.15 * math.sin(t * 7), add=True, center=True)
    C.put(tex("rays_white"), icx, icy, I * 1.6, I * 1.6, lighten((r, g, b), 0.2), 0.6, angle=-360 * t / 12, center=True)
    off = (t * 0.35) % 1
    border = tex("metal_rainbow")
    bw2 = border.width
    tiled = Image.new("RGBA", (bw2 * 2, bw2 * 2))
    for tx in (0, bw2):
        for ty in (0, bw2):
            tiled.paste(border, (tx, ty))
    ox2, oy2 = int(off * bw2), int((off * 0.5 % 1) * bw2)
    tile = tiled.crop((ox2, oy2, ox2 + bw2, oy2 + bw2))
    if rainbow:
        C.put(tile, icx, icy, I + 10 * s, I + 10 * s, center=True)
    else:
        C.put(tile, icx, icy, I + 10 * s, I + 10 * s, lighten((cr, cg, cb), 0.25), desat=True, center=True)
    if danger:
        C.put(pull_icon(key), icx, icy, I, I, (0.65, 1, 0.5), desat=True, crop=(0.07, 0.07, 0.93, 0.93), center=True)
    else:
        C.put(pull_icon(key), icx, icy, I, I, crop=(0.07, 0.07, 0.93, 0.93), center=True)
    pulse = 0.5 + 0.5 * math.sin(t * 3)
    C.put(tex("glow_inner"), icx, icy, I, I, lighten(f_c, 0.3 * pulse), 0.35 + 0.25 * math.sin(t * 6), add=True, center=True)
    ant_c = HSV(t * 1.6 + 0.5, 0.9, 1) if rainbow else (r2, g2, b2)
    C.put(ants_tex(int(t * 30) % 22), icx, icy, I + 44 * s, I + 44 * s, ant_c, 1.0, add=True, center=True)

    # cooldown sweep (reverse) + edge, then the big timer
    if dur:
        elapsed = 1 - rem / dur
        n = int(round(I))
        m = Image.new("L", (n, n))
        dm = ImageDraw.Draw(m)
        dm.pieslice((-n, -n, 2 * n, 2 * n), -90, -90 + 360 * elapsed, fill=int(0.6 * 255))
        black = Image.new("RGBA", (n, n), (0, 0, 0, 255))
        black.putalpha(m)
        C.blit(black, icx - n / 2, icy - n / 2)
        ang = math.radians(-90 + 360 * elapsed)
        ln = (n / 2) / max(abs(math.cos(ang)), abs(math.sin(ang)), 1e-6)
        C.draw.line((icx, icy, icx + math.cos(ang) * ln, icy + math.sin(ang) * ln),
                    fill=(255, 255, 230), width=max(1, int(1.5 * s)))
        txt = f"{int(rem)}" if rem >= 10 else f"{rem:.1f}"
        C.text(icx, icy - 2 * s, txt, 36 * s, (1, 0.4, 0.3) if rem < 3 else (1, 1, 1), 3.0 * s, anchor="mm")
    elif state.get("casts_total"):
        C.text(icx, icy - 2 * s, str(state["casts_left"]), 36 * s, (1, 1, 1), 3.0 * s, anchor="mm")
        C.text(icx, icy + 20 * s, "casts", 10 * s, (1, 1, 1), 1.0 * s)

    # sparks flying out of the icon (not for Voidfin)
    if not danger:
        for i in range(10):
            angr = i * (math.tau / 10) + 0.3
            dist = ICON * (0.72 + (i % 3) * 0.12)
            period = 0.9 + 0.13 * i
            lt = (t + 3.0) % period - i * 0.13
            if lt < 0:
                continue
            p = lt / 0.9
            pe = 1 - (1 - p) ** 2
            sc = 1.2 + (0.4 - 1.2) * p
            spc = HSV(i / 10, 0.55, 1) if rainbow else lighten((r, g, b), 0.25 + (i % 3) * 0.2)
            C.put(tex("spark"), icx + math.cos(angr) * dist * pe * s, icy - math.sin(angr) * dist * pe * s,
                  ICON * 0.28 * sc * s, ICON * 0.28 * sc * s, spc, 1 - p, center=True)


def draw_total(C, cx, cy, s, t, sums):
    ox, oy = cx - W * s / 2, cy - TOTAL_H * s / 2
    hr = HSV(t * 0.45, 0.7, 1)
    for _ in range(2):
        C.put(tex("glow_outer"), ox - 22 * s, oy - 22 * s, (W + 44) * s, (TOTAL_H + 44) * s, hr, 0.45 + 0.15 * math.sin(t * 4), add=True)
    grad = hgrad(W * s, TOTAL_H * s, (0.10, 0.02, 0.18), (0.30, 0.06, 0.40)).convert("RGBA")
    grad.putalpha(int(0.92 * 255))
    C.blit(grad, ox, oy)
    for i, (x0, y0, x1, y1) in enumerate([(0, 0, W, 2), (0, TOTAL_H - 2, W, TOTAL_H), (0, 0, 2, TOTAL_H), (W - 2, 0, W, TOTAL_H)], 1):
        C.rect(ox + x0 * s, oy + y0 * s, ox + x1 * s, oy + y1 * s, HSV(t * 0.6 + i * 0.25, 0.8, 1), 1.0, add=True)
    C.text(ox + 16 * s, cy, "TOTAL", 16 * s, (1, 0.95, 0.8), 2.0 * s, anchor="lm")
    for i, st in enumerate(ORDER):
        label, col = STAT[st]
        gx = ox + (100 + i * 86 + 12) * s
        C.put(tex("gem_white"), gx, cy, 24 * s, 24 * s, col, center=True)
        C.text(gx, cy, label[0], 11 * s, (1, 1, 1), 1.5 * s, anchor="mm")
        C.text(gx + 16 * s, cy, fmt_amt(sums[st]), 15 * s, lighten(col, 0.35), 2.0 * s, anchor="lm")


# ---------------------------------------------------------------- scene backdrop
def backdrop(w, h, seed=7, tint=(0.0, 0.0, 0.0)):
    top, bot = (9, 10, 26), (26, 12, 42)
    col = Image.new("RGB", (1, h))
    for y in range(h):
        f = y / max(1, h - 1)
        col.putpixel((0, y), tuple(int(top[k] + (bot[k] - top[k]) * f) for k in range(3)))
    img = col.resize((w, h))
    bok = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bok)
    rnd = random.Random(seed)
    palette = [(120, 60, 200), (40, 160, 170), (200, 140, 40), (180, 50, 120), (60, 90, 200)]
    for _ in range(int(w * h / 9000)):
        x, y, r = rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(w * 0.006, w * 0.03)
        c = rnd.choice(palette)
        k = rnd.uniform(0.12, 0.35)
        d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(v * k) for v in c))
    bok = bok.filter(ImageFilter.GaussianBlur(w / 220))
    img = ImageChops.add(img, bok)
    for _ in range(int(w * h / 6000)):  # faint specks
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        v = rnd.randint(40, 110)
        rr = rnd.uniform(0.6, 1.6) * w / 1280
        ImageDraw.Draw(img).ellipse((x - rr, y - rr, x + rr, y + rr), fill=(v, v, int(v * 1.1)))
    vig = Image.radial_gradient("L").resize((w, h)).point(lambda v: int(255 - min(255, v * 0.75)))
    img = ImageChops.multiply(img, Image.merge("RGB", (vig, vig, vig)))
    return img


def glow_text(C, x, y, s, px, color, glow_color, anchor="mm", outline=None, blur=None):
    w, h = C.img.size
    m = Image.new("L", (w, h))
    ImageDraw.Draw(m).text((x, y), s, font=font(px), fill=255, anchor=anchor, stroke_width=int(px * 0.06))
    g = m.filter(ImageFilter.GaussianBlur(blur or px * 0.35))
    g = g.point(lambda v: min(255, int(v * 1.6)))
    layer = Image.new("RGBA", (w, h), rgb255(glow_color) + (255,))
    layer.putalpha(g)
    C.blit(layer, 0, 0, add=True)
    C.text(x, y, s, px, color, outline if outline is not None else px * 0.07, anchor=anchor)


def finish(img, size, path):
    img = img.resize(size, Image.LANCZOS)
    img.save(path, optimize=True)
    print("wrote", path, os.path.getsize(path) // 1024, "KB")


# ---------------------------------------------------------------- the pull states shown in the stills
SF = 0.71  # the post-hotfix scale factor from Data.lua (NERF) at the base item level
STILLS = {
    "salmon":    (1.30, dict(remain=8.4, duration=12, amount=157)),
    "scroll":    (2.05, dict(remain=6.8, duration=12, amount=463)),
    "totem":     (1.60, dict(casts_left=10, casts_total=14, amount=359)),
    "gralstone": (0.95, dict(remain=9.1, duration=12, amount=249)),
    "seashell":  (1.75, dict(remain=7.0, duration=12, amount=251)),
    "voidfin":   (1.15, dict(remain=10.4, duration=12, amount=-31)),
}


def banner():
    w, h = 1280 * SS, 720 * SS
    C = Canvas(backdrop(w, h, seed=3))
    px = 78 * SS
    w1, w2 = C.text_width("Gebbo's ", px), C.text_width("Bottomless Bag", px)
    x0 = w * 0.5 - (w1 + w2) / 2
    glow_text(C, x0, 130 * SS, "Gebbo's", px, (0.37, 0.89, 0.82), (0.10, 0.45, 0.42), anchor="lm")
    glow_text(C, x0 + w1, 130 * SS, "Bottomless Bag", px, (1, 0.82, 0.5), (0.5, 0.30, 0.05), anchor="lm")
    C.text(w * 0.5, 215 * SS, "Know exactly what the bag just handed you.", 30 * SS, (0.92, 0.88, 1.0), 1.5 * SS)
    t, st = STILLS["salmon"]
    draw_panel(C, "salmon", w * 0.5, 430 * SS, 1.95 * SS, t, st)
    C.text(w * 0.5, 655 * SS, "A World of Warcraft: Midnight addon   ·   /gbag test salmon", 22 * SS, (0.78, 0.74, 0.92), 1.2 * SS)
    finish(C.img, (1280, 720), os.path.join(OUT, "Gebbo_banner_1280x720.png"))


def six_pulls():
    w, h = 1280 * SS, 720 * SS
    C = Canvas(backdrop(w, h, seed=11))
    glow_text(C, w * 0.5, 52 * SS, "Six pulls, six looks", 44 * SS, (1, 0.9, 0.7), (0.45, 0.20, 0.55))
    s = 1.16 * SS
    keys = ["salmon", "scroll", "totem", "gralstone", "seashell", "voidfin"]
    colx = [w * 0.5 - 296 * SS, w * 0.5 + 296 * SS]
    rowy = [196 * SS, 392 * SS, 588 * SS]
    for i, k in enumerate(keys):
        t, st = STILLS[k]
        draw_panel(C, k, colx[i % 2], rowy[i // 2], s, t, st)
    finish(C.img, (1280, 720), os.path.join(OUT, "Gebbo_six_pulls_1280x720.png"))


def stacked():
    w, h = 1280 * SS, 720 * SS
    C = Canvas(backdrop(w, h, seed=21))
    s = 1.5 * SS
    cx = w - (W * s) / 2 - 90 * SS
    y1 = 150 * SS
    y2 = y1 + (H + GAP) * s
    yt = y2 + (H / 2 + GAP + TOTAL_H / 2) * s
    draw_panel(C, "salmon", cx, y1, s, 1.9, dict(remain=7.8, duration=12, amount=157))
    draw_panel(C, "scroll", cx, y2, s, 2.6, dict(remain=9.4, duration=12, amount=463))
    draw_total(C, cx, yt, s, 1.9, {"crit": 157, "haste": 157, "mastery": 620, "vers": 157})
    lx = 70 * SS
    glow_text(C, lx, 130 * SS, "Two pulls at once?", 42 * SS, (1, 0.9, 0.7), (0.45, 0.20, 0.55), anchor="lm")
    lines = [
        ("Each pull gets its own panel,", (0.92, 0.88, 1.0)),
        ("stacked in a fixed order with", (0.92, 0.88, 1.0)),
        ("the Jackpot always on top.", (0.92, 0.88, 1.0)),
        ("", None),
        ("The TOTAL strip adds up", (1, 0.82, 0.5)),
        ("Crit, Haste, Mastery and Vers", (1, 0.82, 0.5)),
        ("across everything that's up.", (1, 0.82, 0.5)),
    ]
    y = 215 * SS
    for txt, col in lines:
        if txt:
            C.text(lx, y, txt, 25 * SS, col, 1.2 * SS, anchor="lm")
        y += 38 * SS
    C.text(lx, 560 * SS, "/gbag grow up   flips the stack", 21 * SS, (0.70, 0.66, 0.85), 1.0 * SS, anchor="lm")
    finish(C.img, (1280, 720), os.path.join(OUT, "Gebbo_stacked_total_1280x720.png"))


def animated(key, fname, seconds, fps, scale, amount, flash):
    s = scale
    pad_x, pad_y = 70, 62
    w, h = int(W * s + 2 * pad_x), int(H * s + 2 * pad_y)
    base = backdrop(w * 2, h * 2, seed=5).resize((w, h), Image.LANCZOS)
    frames = []
    n = int(seconds * fps)
    for f in range(n):
        t = f / fps
        C = Canvas(base.copy())
        draw_panel(C, key, w / 2, h / 2, s, t, dict(remain=max(0, 12 - t), duration=12, amount=amount))
        if flash == "jackpot" and t < 1.1:
            p = t / 1.1
            fl = Image.radial_gradient("L").resize((w, h)).point(lambda v: min(255, int(v * 1.3)))
            layer = Image.new("RGBA", (w, h), rgb255(HSV(t * 1.5, 0.8, 1)) + (255,))
            layer.putalpha(fl.point(lambda v: int(v * (1 - p) ** 1.5 * 0.85)))
            C.blit(layer, 0, 0, add=True)
        elif flash == "bad" and t < 0.8:
            p = t / 0.8
            fl = Image.radial_gradient("L").resize((w, h)).point(lambda v: min(255, int(v * 1.3)))
            layer = Image.new("RGBA", (w, h), rgb255((0.45, 1, 0.2)) + (255,))
            layer.putalpha(fl.point(lambda v: int(v * (1 - p) ** 1.5 * 0.75)))
            C.blit(layer, 0, 0, add=True)
        frames.append(C.img.quantize(colors=160, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    path = os.path.join(OUT, fname)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0,
                   optimize=True, disposal=1)
    print("wrote", path, os.path.getsize(path) // 1024, "KB,", n, "frames")


if __name__ == "__main__":
    which = sys.argv[3:] or ["banner", "six", "stack", "gif"]
    if "banner" in which: banner()
    if "six" in which: six_pulls()
    if "stack" in which: stacked()
    if "gif" in which:
        animated("salmon", "Gebbo_jackpot.gif", 4.0, 15, 1.25, 157, "jackpot")
        animated("voidfin", "Gebbo_voidfin.gif", 3.0, 15, 1.25, -31, "bad")
