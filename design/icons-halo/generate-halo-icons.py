#!/usr/bin/env python3
"""Generate the GMapHUD alert icon set (112 PNG, same file names as the tweak).

Two families share one 256 px artboard:
  * Road signs that exist in QCVN 41:2024/BGTVT keep the face the regulation gives them
    (shape, colours, pictogram), drawn here from scratch so the icon reads like the sign
    the driver passes: prohibition P (white disc, red ring, red slash), end of restriction
    DP (white disc, thin blue ring, black stripes), mandatory R (blue disc, white arrows),
    warning W (yellow triangle, rounded red border, black pictogram), guide I/IE and R.420.
    Speed limits are P.127 with Saira Condensed numerals.
  * Reports that only exist in the apps (cameras, police, incidents, hazards, weather)
    stay Halo tokens: surface disc r123 Ink 900, category ring r102, white line glyph.
    Cameras reuse the Halo mark: an Ice ring open at the top right with a type badge there.

Usage: python3 generate-halo-icons.py [out_dir]   (needs rsvg-convert for PNG output)
"""
import io
import math
import os
import subprocess
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out")
FONT = TTFont(os.path.join(HERE, "fonts", "SairaCondensed-Bold.ttf"))
GLYPHS, CMAP = FONT.getGlyphSet(), FONT.getBestCmap()
UPM, CAP = FONT["head"].unitsPerEm, FONT["OS/2"].sCapHeight

INK, RIM, WHITE, MUTED, SOFT = "#0D1117", "#2A3340", "#F2F5F9", "#7C8797", "#B7C0CC"
RED, AMBER, BLUE, SIGNAL, BADGE_RED = "#F0484E", "#FFB938", "#5B93F5", "#FF4D4F", "#E2231A"
XL, L, M = 16, 12, 9
C = 128


# ---------------------------------------------------------------- primitives
def line(d, color=WHITE, w=XL, cap="round"):
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" '
            f'stroke-linecap="{cap}" stroke-linejoin="round"/>')


def fill(d, color=WHITE):
    return f'<path d="{d}" fill="{color}"/>'


def circle(cx, cy, r, fill_color="none", stroke=None, w=0, dash=None):
    s = f' stroke="{stroke}" stroke-width="{w}"' if stroke else ""
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{fill_color}"{s}{d}/>'


def text(s, cx, cy, cap_px, color):
    """Saira Condensed Bold outlines, optically centred on cap height at (cx, cy)."""
    scale = cap_px / CAP
    width = sum(GLYPHS[CMAP[ord(ch)]].width for ch in s) * scale
    x = cx - width / 2
    baseline = cy + cap_px / 2
    out = []
    for ch in s:
        name = CMAP[ord(ch)]
        pen = SVGPathPen(GLYPHS)
        GLYPHS[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        if pen.getCommands():
            out.append(fill(pen.getCommands(), color))
        x += GLYPHS[name].width * scale
    return "".join(out)


def mirror(body):
    return f'<g transform="matrix(-1 0 0 1 256 0)">{body}</g>'


def group(body, x=0, y=0, s=1.0):
    return f'<g transform="translate({x:g} {y:g}) scale({s:g})">{body}</g>'


_INK = {}


def ink_rows(body):
    """Horizontal ink extent of each row of a fragment, in artboard units, from a 2x render."""
    if body not in _INK:
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">{body}</svg>'
        png = subprocess.run(["rsvg-convert", "-w", "512", "-h", "512"], input=svg.encode("utf-8"),
                             capture_output=True, check=True).stdout
        alpha = Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A").point(lambda a: 255 if a > 40 else 0)
        rows = {}
        for y in range(512):
            box = alpha.crop((0, y, 512, y + 1)).getbbox()
            if box:
                rows[y / 2 + 0.25] = (box[0] / 2, box[2] / 2)
        _INK[body] = rows
    return _INK[body]


def in_circle(radius):
    def inside(y, left, right):
        h = radius * radius - (y - C) ** 2
        return h >= 0 and left >= C - math.sqrt(h) and right <= C + math.sqrt(h)
    return inside


def centered(picto, cy, inside, lowest=None):
    """Centre a pictogram's ink vertically on cy, shrinking it only as far as `inside` requires.

    With `lowest`, a pictogram too wide for the narrow top of a triangle may sit lower, down to
    that centre line, when that keeps it larger; the highest placement wins ties.
    """
    rows = ink_rows(picto)
    if not rows:
        return picto
    mid = (min(rows) + max(rows)) / 2
    cx = (min(l for l, _ in rows.values()) + max(r for _, r in rows.values())) / 2

    def largest(y0):
        s = 1.0
        while s > 0.6 and not all(inside(y0 + s * (y - mid), cx + s * (l - cx), cx + s * (r - cx))
                                  for y, (l, r) in rows.items()):
            s -= 0.01
        return round(s, 2)

    best_s, best_y = largest(cy), cy
    for y0 in range(int(cy) + 1, int(lowest or cy) + 1):
        if best_s >= 1:
            break
        s = largest(y0)
        if s > best_s + 0.02:
            best_s, best_y = s, y0
    return f'<g transform="translate({cx - best_s * cx:.2f} {best_y - best_s * mid:.2f}) scale({best_s:.2f})">{picto}</g>'


# ---------------------------------------------------------------- token frames
SURFACE = circle(C, C, 123, INK, RIM, 9.6)
SLASH = line("M62 62L194 194", RED, XL)


def ring(color, dash=None):
    return circle(C, C, 102, "none", color, 16.6 if not dash else 14, dash)


GLYPH_AREA = in_circle(84)


def token(color, glyph, dash=None):
    return SURFACE + ring(color, dash) + centered(glyph, C, GLYPH_AREA)


# ---------------------------------------------------------------- glyph components


def paw(color=WHITE):
    return (fill("M128 122C102 122 88 148 92 166C96 182 112 184 128 178C144 184 160 182 164 166"
                 "C168 148 154 122 128 122Z", color) +
            circle(88, 112, 13, color) + circle(112, 88, 13, color) +
            circle(144, 88, 13, color) + circle(168, 112, 13, color))


def road(color=WHITE):
    return line("M86 190L112 66M170 190L144 66", color, L)


def car_front(color=WHITE):
    return (line("M76 156V128L94 94H162L180 128V156Z", color, L) +
            line("M90 156V172M166 156V172", color, L) +
            circle(100, 138, 7, color) + circle(156, 138, 7, color))


def burst(cx, cy, r=22, color=WHITE):
    pts = []
    for i in range(16):
        a = math.pi * 2 * i / 16
        rr = r if i % 2 == 0 else r * 0.48
        pts.append(f"{cx + rr * math.cos(a):.1f} {cy + rr * math.sin(a):.1f}")
    return fill("M" + "L".join(pts) + "Z", color)


def bang():
    return line("M128 72V146") + circle(128, 180, 11, WHITE)


def small_bang(cx, cy, s=0.5):
    return group(bang(), cx - 128 * s, cy - 128 * s, s)


def triangle_bang():
    return line("M128 70L190 178H66Z", WHITE, M) + line("M128 104V144", WHITE, L) + circle(128, 162, 7, WHITE)


def cone():
    return (line("M88 184H168", WHITE, L) + line("M98 184L120 82H136L158 184", WHITE, L) +
            line("M108 148H148M114 116H142", WHITE, M))


def barrier():
    return (line("M70 106H186V146H70Z", WHITE, L) + line("M98 106L78 146M134 106L114 146M170 106L150 146", WHITE, M) +
            line("M90 146V184M166 146V184", WHITE, L))


def cloud():
    return line("M90 136A26 26 0 0 1 100 86A34 34 0 0 1 164 92A26 26 0 0 1 166 136Z", WHITE, L)


def waves(y):
    return line(f"M64 {y}Q80 {y - 14} 96 {y}T128 {y}T160 {y}T192 {y}", WHITE, L)


def snowflake(cx=128, cy=128, r=54, w=L):
    out = ""
    for i in range(3):
        a = math.pi * i / 3
        dx, dy = r * math.cos(a), r * math.sin(a)
        out += line(f"M{cx - dx:.1f} {cy - dy:.1f}L{cx + dx:.1f} {cy + dy:.1f}", WHITE, w)
    for i in range(6):
        a = math.pi * i / 3
        bx, by = cx + r * 0.62 * math.cos(a), cy + r * 0.62 * math.sin(a)
        for side in (-1, 1):
            b = a + side * math.pi / 4
            out += line(f"M{bx:.1f} {by:.1f}L{bx + 18 * math.cos(b):.1f} {by + 18 * math.sin(b):.1f}", WHITE, M)
    return out


def traffic_light(lamp=SIGNAL):
    return (f'<rect x="102" y="66" width="52" height="124" rx="18" fill="none" stroke="{WHITE}" stroke-width="{L}"/>' +
            circle(128, 96, 13, lamp) + circle(128, 128, 13, MUTED) + circle(128, 160, 13, MUTED))


def camera(color=WHITE):
    """Wall-mounted surveillance camera: solid housing under a sun hood, tilted toward the road, with
    the lens as a white eye at the front so it stays legible at bubble size."""
    head = (f'<g transform="rotate(18 140 112)">'
            f'<rect x="92" y="90" width="104" height="46" rx="12" fill="{color}"/>'
            f'<rect x="84" y="78" width="132" height="16" rx="8" fill="{color}"/>'
            + circle(174, 113, 13, "#FFFFFF") + circle(174, 113, 5.5, color) + '</g>')
    mount = line("M64 100V178", color, 14) + line("M64 150H116V130", color, 12)
    return head + mount


# ---------------------------------------------------------------- camera badges (at the ring gap)
BX, BY = 200, 56


def badge_disc(inner, fill_color=WHITE):
    return circle(BX, BY, 31, fill_color, INK, 8) + inner


def badge_text(s, fill_color=WHITE, ink=INK):
    w = 30 + 22 * len(s)
    return (f'<rect x="{BX - w / 2:g}" y="{BY - 27}" width="{w:g}" height="54" rx="18" fill="{fill_color}" '
            f'stroke="{INK}" stroke-width="8"/>' + text(s, BX, BY, 26, ink))


BADGES = {
    "limit": lambda: circle(BX, BY, 35, INK) + circle(BX, BY, 25, "#FFFFFF", BADGE_RED, 10),
    "red": lambda: circle(BX, BY, 29, SIGNAL, INK, 10),
    "redlimit": lambda: circle(BX, BY, 30, SIGNAL, "#FFFFFF", 9) + circle(BX, BY, 38, "none", INK, 6),
    "bang": lambda: badge_disc(line(f"M{BX} {BY - 16}V{BY + 3}", INK, 9) + circle(BX, BY + 15, 5, INK)),
    "phone": lambda: badge_disc(f'<rect x="{BX - 10}" y="{BY - 18}" width="20" height="36" rx="5" fill="none" '
                                f'stroke="{INK}" stroke-width="6"/>'),
    "belt": lambda: badge_disc(line(f"M{BX - 18} {BY - 16}L{BX + 16} {BY + 18}", INK, 8) +
                               f'<rect x="{BX - 7}" y="{BY - 7}" width="14" height="14" rx="3" fill="{INK}"/>'),
    "stop": lambda: (f'<path d="M{BX - 13} {BY - 31}L{BX + 13} {BY - 31}L{BX + 31} {BY - 13}L{BX + 31} {BY + 13}'
                     f'L{BX + 13} {BY + 31}L{BX - 13} {BY + 31}L{BX - 31} {BY + 13}L{BX - 31} {BY - 13}Z" '
                     f'fill="{RED}" stroke="{INK}" stroke-width="8" stroke-linejoin="round"/>' +
                     line(f"M{BX - 14} {BY}H{BX + 14}", WHITE, 8)),
    "noise": lambda: badge_disc(fill(f"M{BX - 18} {BY - 8}H{BX - 9}L{BX + 2} {BY - 18}V{BY + 18}L{BX - 9} {BY + 8}"
                                     f"H{BX - 18}Z", INK) +
                                line(f"M{BX + 10} {BY - 10}Q{BX + 18} {BY} {BX + 10} {BY + 10}", INK, 5)),
    "distance": lambda: badge_disc(line(f"M{BX - 18} {BY}H{BX + 18}M{BX - 8} {BY - 10}L{BX - 18} {BY}"
                                        f"L{BX - 8} {BY + 10}M{BX + 8} {BY - 10}L{BX + 18} {BY}L{BX + 8} {BY + 10}", INK, 6)),
    "radar": lambda: badge_disc(circle(BX - 10, BY + 10, 6, INK) +
                                line(f"M{BX - 6} {BY - 10}A16 16 0 0 1 {BX + 10} {BY + 6}", INK, 5) +
                                line(f"M{BX - 4} {BY - 22}A28 28 0 0 1 {BX + 22} {BY + 4}", INK, 5)),
    "star": lambda: badge_disc(fill(f"M{BX} {BY - 19}L{BX + 6} {BY - 6}L{BX + 19} {BY - 6}L{BX + 8} {BY + 3}"
                                    f"L{BX + 12} {BY + 17}L{BX} {BY + 9}L{BX - 12} {BY + 17}L{BX - 8} {BY + 3}"
                                    f"L{BX - 19} {BY - 6}L{BX - 6} {BY - 6}Z", INK)),
    "cross": lambda: circle(BX, BY, 28, MUTED, INK, 8) + line(f"M{BX - 11} {BY - 11}L{BX + 11} {BY + 11}"
                                                             f"M{BX + 11} {BY - 11}L{BX - 11} {BY + 11}", INK, 7),
}


def badge_svg(badge):
    return BADGES[badge]() if badge in BADGES else badge_text(badge)


def camera_token(glyph=None, dashed=False):
    """Camera and traffic-police alerts: a white disc with the thick red ring of a speed-limit sign
    and the pictogram in black. A dummy camera gets a dashed grey ring. The badge naming the camera
    type is added by sticker(), on top of the shading."""
    if dashed:
        face, ink = circle(C, C, P_OUT - BORDER / 2, Q_WHITE, MUTED, BORDER * 0.7, "22 16"), MUTED
    else:
        face, ink = circle(C, C, P_OUT - BORDER / 2, Q_WHITE, Q_RED, BORDER), Q_BLACK
    return face + centered(glyph(ink) if glyph else camera(ink), C, in_circle(P_IN - 12))


def police(color=WHITE):
    return line("M128 74L176 92V124C176 156 156 176 128 188C100 176 80 156 80 124V92Z", color, L) + \
        fill("M128 104L135 122H154L139 133L145 151L128 140L111 151L117 133L102 122H121Z", color)


# ---------------------------------------------------------------- QCVN 41:2024 sign faces
Q_RED, Q_YELLOW, Q_BLUE, Q_GREEN, Q_BLACK, Q_WHITE = "#E2231A", "#FFD200", "#005BAA", "#00843D", "#1A1A1A", "#FFFFFF"

# Sign standard shared by every road-sign face on the 256 artboard, so borders and strokes read
# alike across the five groups (prohibition, warning, mandatory, guide, supplementary).
EDGE = 4                    # margin between every sign and the artboard edge
BORDER = 24                 # thick border: prohibition ring, warning border
RIM = 8                     # thin rim: mandatory, end of restriction, guide and supplementary panels
BAR = 18                    # red bar: prohibition slash, end-of-zone diagonal
ARROW = 20                  # arrow shafts in prohibition and mandatory pictograms
ARROW_HEAD = (40, 56)       # arrowhead length and width
ROAD, ROAD_MAJOR = 14, 18   # road lines in warning pictograms; the priority road in W.207
DETAIL = 6                  # small strokes: wheels, frames, tracks, hoses
STRIPE = 4                  # end-of-restriction stripes and the finest marks
CORNER = 16                 # outer corner radius of triangles and panels
PANEL = (EDGE, 46, 256 - 2 * EDGE, 164)  # rectangular panels: x, y, width, height
PANEL_INSET = 6             # coloured margin outside the rim of rectangular panels


def stroke(d, color, w, join="round", cap="butt"):
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w:g}" '
            f'stroke-linecap="{cap}" stroke-linejoin="{join}"/>')


def rect(x, y, w, h, color, rx=0):
    return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{rx:g}" fill="{color}"/>'


def poly(points, color):
    return fill("M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in points) + "Z", color)


def rounded(points, r):
    """Closed path through `points` (clockwise on screen) with every corner rounded by r."""
    d = ""
    for i, (px, py) in enumerate(points):
        (ax, ay), (bx, by) = points[i - 1], points[(i + 1) % len(points)]
        ux, uy, vx, vy = ax - px, ay - py, bx - px, by - py
        lu, lv = math.hypot(ux, uy), math.hypot(vx, vy)
        ux, uy, vx, vy = ux / lu, uy / lu, vx / lv, vy / lv
        t = r / math.tan(math.acos(max(-1.0, min(1.0, ux * vx + uy * vy))) / 2)
        d += f"{'M' if i == 0 else 'L'}{px + ux * t:.2f} {py + uy * t:.2f}"
        d += f"A{r:g} {r:g} 0 0 1 {px + vx * t:.2f} {py + vy * t:.2f}"
    return d + "Z"


def head(tip, direction, color, length, width):
    """Filled arrowhead with its point at `tip`, pointing along the unit vector `direction`."""
    (tx, ty), (dx, dy) = tip, direction
    bx, by = tx - dx * length, ty - dy * length
    nx, ny = -dy * width / 2, dx * width / 2
    return poly([(tx, ty), (bx + nx, by + ny), (bx - nx, by - ny)], color)


def label(s, cx, cy, cap_px, color, max_w):
    width = sum(GLYPHS[CMAP[ord(ch)]].width for ch in s) * cap_px / CAP
    return text(s, cx, cy, min(cap_px, cap_px * max_w / width), color)


# Circular signs: outer diameter 248. The slash runs top left to bottom right over the pictogram.
P_OUT = C - EDGE
P_IN = P_OUT - BORDER


def prohibition(picto, slash=True):
    s = P_IN * math.sqrt(0.5)
    bar = stroke(f"M{C - s:.2f} {C - s:.2f}L{C + s:.2f} {C + s:.2f}", Q_RED, BAR) if slash else ""
    return circle(C, C, P_OUT - BORDER / 2, Q_WHITE, Q_RED, BORDER) + centered(picto, C, in_circle(P_IN - 8)) + bar


def end_of_restriction(picto):
    inner, out = P_OUT - RIM, ""
    for k in range(-2, 3):
        o = k * 10 * math.sqrt(0.5)
        h = math.sqrt(inner ** 2 - (k * 10) ** 2) * math.sqrt(0.5)
        out += stroke(f"M{C + o + h:.2f} {C + o - h:.2f}L{C + o - h:.2f} {C + o + h:.2f}", Q_BLACK, STRIPE)
    return circle(C, C, P_OUT - RIM / 2, Q_WHITE, Q_BLUE, RIM) + centered(picto, C, in_circle(P_OUT - RIM - 10)) + out


def mandatory(picto):
    return circle(C, C, P_OUT, Q_WHITE) + circle(C, C, P_OUT - RIM, Q_BLUE) + centered(picto, C, in_circle(P_OUT - RIM - 10))


# Warning triangle: equilateral, outer corner radius CORNER, red BORDER, fills 4..252 x 18..238.
_SIDE = 271.4
_HEIGHT = _SIDE * math.sqrt(3) / 2
TRIANGLE = [(C, 2.48), (C + _SIDE / 2, 2.48 + _HEIGHT), (C - _SIDE / 2, 2.48 + _HEIGHT)]
CENTROID_Y = 2.48 + _HEIGHT * 2 / 3


_K = (_HEIGHT / 3 - BORDER) / (_HEIGHT / 3)
INNER_TRIANGLE = [(C + _K * (x - C), CENTROID_Y + _K * (y - CENTROID_Y)) for x, y in TRIANGLE]
WARNING_CENTER_Y = 148


def in_warning(margin=10):
    (_, apex), (right, base), _ = INNER_TRIANGLE
    half = right - C

    def inside(y, left, right_edge):
        if y < apex + 2 * margin or y > base - margin:
            return False
        h = (y - apex) / (base - apex) * half - margin / math.sin(math.pi / 3)
        return left >= C - h and right_edge <= C + h
    return inside


def warning(picto):
    return (fill(rounded(TRIANGLE, CORNER), Q_RED) + fill(rounded(INNER_TRIANGLE, 5), Q_YELLOW) +
            centered(picto, WARNING_CENTER_Y, in_warning(), lowest=WARNING_CENTER_Y + 10))


# Rectangular signs sit landscape in the square artboard; the tweak draws artwork aspect-fit.
def panel(ground, rim, body):
    x, y, w, h = PANEL
    o = PANEL_INSET + RIM / 2
    return (rect(x, y, w, h, ground, CORNER) +
            f'<rect x="{x + o:g}" y="{y + o:g}" width="{w - 2 * o:g}" height="{h - 2 * o:g}" rx="{CORNER - o:g}" '
            f'fill="none" stroke="{rim}" stroke-width="{RIM}"/>' + body)


def blue_panel(body):
    return panel(Q_BLUE, Q_WHITE, body)


def yellow_panel(body):
    return panel(Q_YELLOW, Q_BLACK, body)


def supplementary(body):
    return panel(Q_WHITE, Q_BLACK, body)


def speed_limit(value):
    cap = 76 if value >= 100 else 96
    return prohibition(text(str(value), C, C, cap, Q_BLACK), slash=False)


# ---------------------------------------------------------------- QCVN pictograms
def arrow(d, end, direction, color, join="round"):
    """Arrow whose shaft path `d` ends at `end`; the standard head overlaps it by 2."""
    length, width = ARROW_HEAD
    tip = (end[0] + direction[0] * (length - 2), end[1] + direction[1] * (length - 2))
    return stroke(d, color, ARROW, join=join) + head(tip, direction, color, length, width)


def p_arrow(d, end, direction):
    return arrow(d, end, direction, Q_BLACK)


P_STRAIGHT = p_arrow("M128 202V96", (128, 96), (0, -1))
P_LEFT = p_arrow("M162 200V124Q162 104 142 104H114", (114, 104), (-1, 0))
P_LEFT_RIGHT = (p_arrow("M128 200V136Q128 116 108 116H96", (96, 116), (-1, 0)) +
                p_arrow("M128 136Q128 116 148 116H160", (160, 116), (1, 0)))
P_STRAIGHT_LEFT = (p_arrow("M150 202V96", (150, 96), (0, -1)) +
                   p_arrow("M150 172Q150 144 122 144H104", (104, 144), (-1, 0)))
P_UTURN = p_arrow("M166 194V116A30 30 0 0 0 106 116V142", (106, 142), (0, 1))
P_RIGHT_UTURN = (p_arrow("M140 200V100Q140 82 158 82H160", (160, 82), (1, 0)) +
                 p_arrow("M140 176V156A24 24 0 0 0 92 156V162", (92, 162), (0, 1)))
P_LEFT_UTURN = (p_arrow("M168 200V100Q168 80 148 80H124", (124, 80), (-1, 0)) +
                p_arrow("M168 178V150A30 30 0 0 0 108 150V160", (108, 160), (0, 1)))


def r_arrow(d, end, direction):
    return arrow(d, end, direction, Q_WHITE, join="miter")


R_STRAIGHT = r_arrow("M128 206V96", (128, 96), (0, -1))
R_RIGHT = r_arrow("M90 196V100H138", (138, 100), (1, 0))
R_STRAIGHT_RIGHT = r_arrow("M100 206V96", (100, 96), (0, -1)) + r_arrow("M100 160H148", (148, 160), (1, 0))
R_LEFT_RIGHT = (stroke("M128 206V124", Q_WHITE, ARROW) +
                r_arrow("M128 124H84", (84, 124), (-1, 0)) + r_arrow("M128 124H172", (172, 124), (1, 0)))


def car_front_solid(cx, color, glass=Q_WHITE, w=76):
    """Car seen from the front, about 1.3 times wider than tall as on P.125."""
    return (fill(rounded([(cx - w * 0.30, 122), (cx + w * 0.30, 122), (cx + w * 0.42, 146), (cx - w * 0.42, 146)], 7), color) +
            rect(cx - w / 2, 142, w, 28, color, 9) +
            rect(cx - w / 2 + 4, 166, 15, 14, color, 3) + rect(cx + w / 2 - 19, 166, 15, 14, color, 3) +
            poly([(cx - w * 0.21, 128), (cx + w * 0.21, 128), (cx + w * 0.30, 142), (cx - w * 0.30, 142)], glass) +
            circle(cx - w * 0.32, 155, 5.5, glass) + circle(cx + w * 0.32, 155, 5.5, glass))


def skyline():
    town = poly([(30, 186), (30, 140), (52, 118), (74, 140), (74, 100), (100, 100), (100, 124), (112, 124),
                 (112, 84), (122, 70), (132, 84), (132, 124), (146, 124), (146, 108), (174, 108), (174, 136),
                 (198, 114), (222, 136), (222, 186)], Q_WHITE)
    windows = "".join(rect(x, y, 6, 8, Q_BLUE, 1) for x in (80, 90) for y in (110, 126, 142, 158))
    windows += "".join(rect(x, y, 6, 8, Q_BLUE, 1) for x in (152, 164) for y in (118, 134, 150))
    return town + windows + rect(46, 160, 12, 26, Q_BLUE, 1) + rect(192, 160, 12, 26, Q_BLUE, 1)


def about(body, s, cx=C, cy=160):
    """Scale a pictogram about (cx, cy)."""
    return group(body, cx - s * cx, cy - s * cy, s)


def walker(x, y, s, color=Q_BLACK, head=10):
    body = (circle(4, -90 - (head - 10) * 0.75, head, color) +
            stroke("M2 -76L-4 -42", color, 15, cap="round") +
            stroke("M-4 -42L-16 -20L-26 0", color, 12, cap="round") +
            stroke("M-4 -42L12 -22L16 0", color, 12, cap="round") +
            stroke("M0 -70L-14 -52", color, 9, cap="round") +
            stroke("M2 -70L16 -54", color, 9, cap="round"))
    return group(body, x, y, s)


W_CURVES = (stroke("M118 210V198C118 180 98 178 98 160C98 140 138 142 138 124V120", Q_BLACK, ROAD) +
            head((138, 90), (0, -1), Q_BLACK, 32, 40))
W_CROSSROADS = rect(C - ROAD / 2, 106, ROAD, 104, Q_BLACK) + rect(78, 158 - ROAD / 2, 100, ROAD, Q_BLACK)
W_FORK = stroke("M128 210V172", Q_BLACK, ROAD) + stroke("M96 128L128 174L160 128", Q_BLACK, ROAD, join="miter")
W_SIDE_ROAD = rect(132, 104, ROAD_MAJOR, 106, Q_BLACK) + stroke("M90 210Q90 170 134 152", Q_BLACK, ROAD)
W_BRIDGE = (stroke("M92 124L106 138V192L92 206", Q_BLACK, ROAD, join="miter") +
            stroke("M164 124L150 138V192L164 206", Q_BLACK, ROAD, join="miter"))
W_NARROW_BOTH = (stroke("M88 210V180L108 150V108", Q_BLACK, ROAD, join="miter") +
                 stroke("M168 210V180L148 150V108", Q_BLACK, ROAD, join="miter"))
W_NARROW_LEFT = (stroke("M92 210V180L114 150V114", Q_BLACK, ROAD, join="miter") +
                 stroke("M156 210V114", Q_BLACK, ROAD))
W_PEDESTRIAN = walker(126, 190, 1.0) + "".join(rect(82 + i * 22, 194, 14, 12, Q_BLACK) for i in range(5))
W_CHILDREN = (walker(146, 204, 1.0, head=14) + walker(104, 204, 0.72, head=14) +
              stroke("M132 152L115.5 165.1", Q_BLACK, DETAIL, cap="round"))
W_BUMP = rect(70, 190, 116, 12, Q_BLACK) + fill("M88 191Q128 128 168 191Z", Q_BLACK)
W_BUMPS = (rect(66, 190, 124, 12, Q_BLACK) + fill("M74 191Q101 146 128 191Z", Q_BLACK) +
           fill("M128 191Q155 146 182 191Z", Q_BLACK))
W_LOCOMOTIVE = (rect(90, 150, 52, 30, Q_BLACK, 6) + rect(138, 128, 28, 52, Q_BLACK) +
                rect(134, 122, 36, 8, Q_BLACK, 2) + rect(146, 136, 14, 14, Q_YELLOW, 2) +
                poly([(98, 150), (98, 136), (94, 130), (112, 130), (108, 136), (108, 150)], Q_BLACK) +
                circle(126, 150, 7, Q_BLACK) + rect(84, 178, 90, 8, Q_BLACK) +
                poly([(90, 172), (80, 194), (94, 194)], Q_BLACK) +
                circle(104, 194, 9, Q_BLACK) + circle(124, 194, 9, Q_BLACK) + circle(154, 192, 12, Q_BLACK) +
                circle(104, 120, 5, Q_BLACK) + circle(96, 108, 7, Q_BLACK) + circle(108, 94, 8, Q_BLACK))
W_TUNNEL = (f'<path d="M78 210V166A50 50 0 0 1 178 166V210ZM102 210V170A26 26 0 0 1 154 170V210Z" '
            f'fill="{Q_BLACK}" fill-rule="evenodd"/>' +
            stroke("M120 210L125 182M136 210L131 182", Q_BLACK, DETAIL))
W_EXCLAMATION = fill("M119 108H137L132 178H124Z", Q_BLACK) + circle(128, 196, 10, Q_BLACK)
W_SLOW = text("ĐI", C, 140, 30, Q_BLACK) + text("CHẬM", C, 184, 30, Q_BLACK)
W_CYCLIST = about(circle(96, 188, 18, "none", Q_BLACK, 6) + circle(160, 188, 18, "none", Q_BLACK, 6) +
             stroke("M96 188L116 160H150L160 188M116 160L128 188L150 160", Q_BLACK, DETAIL) +
             stroke("M150 160L146 146H156", Q_BLACK, DETAIL) + stroke("M108 156H124", Q_BLACK, DETAIL) +
             circle(138, 116, 9, Q_BLACK) + stroke("M134 128L120 156", Q_BLACK, 13, cap="round") +
             stroke("M120 156L140 164L128 186", Q_BLACK, 9, cap="round") +
             stroke("M132 134L150 146", Q_BLACK, 8, cap="round"), 1.12, cy=156)
W_CATTLE = (rect(106, 140, 60, 36, Q_BLACK, 12) +
            fill("M110 146L94 140C88 140 84 145 84 151L83 164C83 169 88 171 93 169L108 162Z", Q_BLACK) +
            stroke("M92 141L88 129", Q_BLACK, DETAIL, cap="round") + stroke("M100 143L103 131", Q_BLACK, DETAIL, cap="round") +
            "".join(rect(x, 172, 8, 32, Q_BLACK, 2) for x in (111, 123, 149, 160)) +
            stroke("M166 146Q177 154 173 176", Q_BLACK, STRIPE, cap="round") + circle(173, 178, 4, Q_BLACK) +
            '<ellipse cx="127" cy="152" rx="9" ry="6" fill="#FFFFFF"/><ellipse cx="150" cy="162" rx="6" ry="5" fill="#FFFFFF"/>' +
            circle(91, 151, 3.5, Q_WHITE))
W_SLIPPERY = about(fill(rounded([(102, 112), (154, 112), (168, 134), (88, 134)], 6), Q_BLACK) +
              rect(78, 132, 100, 26, Q_BLACK, 9) +
              rect(82, 154, 16, 12, Q_BLACK, 3) + rect(158, 154, 16, 12, Q_BLACK, 3) +
              fill(rounded([(108, 118), (148, 118), (158, 132), (98, 132)], 3), Q_YELLOW) +
              rect(84, 138, 16, 8, Q_YELLOW, 2) + rect(156, 138, 16, 8, Q_YELLOW, 2) +
              stroke("M92 174C80 184 106 194 92 208", Q_BLACK, DETAIL, cap="round") +
              stroke("M164 174C152 184 178 194 164 208", Q_BLACK, DETAIL, cap="round"), 1.06, cy=170)

I_REST_AREA = (rect(24, 64, 208, 96, Q_WHITE, 8) +
               rect(70, 80, 34, 62, Q_BLACK, 4) + rect(64, 140, 46, 8, Q_BLACK, 2) +
               rect(76, 88, 22, 16, Q_WHITE, 2) +
               stroke("M104 96H112Q116 96 116 100V130Q116 136 121 136Q126 136 126 130V92L118 84",
                      Q_BLACK, DETAIL, cap="round") +
               stroke("M150 80V98M158 80V98M166 80V98", Q_BLACK, STRIPE, cap="round") +
               stroke("M150 96Q150 108 158 108Q166 108 166 96", Q_BLACK, DETAIL) +
               stroke("M158 106V144", Q_BLACK, DETAIL, cap="round") +
               fill("M182 80Q196 88 194 116H189V144H182Z", Q_BLACK) +
               label("TRẠM DỪNG NGHỈ", C, 182, 20, Q_WHITE, 196))
I_EMERGENCY_LANE = (stroke("M40 196L104 66", Q_WHITE, DETAIL) + stroke("M160 196L140 66", Q_WHITE, DETAIL) +
                    stroke("M222 196L158 66", Q_WHITE, DETAIL) +
                    f'<path d="M100 196L122 66" stroke="{Q_WHITE}" stroke-width="{DETAIL}" stroke-dasharray="16 14" '
                    f'fill="none"/>' +
                    fill(rounded([(171, 138), (193, 138), (199, 154), (165, 154)], 4), Q_WHITE) +
                    poly([(175, 142), (189, 142), (192, 151), (172, 151)], Q_BLUE) +
                    rect(162, 152, 40, 20, Q_WHITE, 5) + rect(165, 170, 9, 9, Q_WHITE, 2) +
                    rect(190, 170, 9, 9, Q_WHITE, 2) + rect(166, 158, 8, 5, Q_BLUE, 1) + rect(190, 158, 8, 5, Q_BLUE, 1))
IE_TOLL = label("THU PHÍ", C, 108, 54, Q_BLACK, 200) + label("PAY TOLL", C, 162, 28, Q_BLACK, 180)
IE_TOLL_ETC = label("KHÔNG DỪNG", C, 104, 40, Q_GREEN, 204) + label("ETC", C, 160, 50, Q_GREEN, 180)


# ---------------------------------------------------------------- the 112 icons
ICONS = {}


BADGE_OF = {}
CAMERA_SIGNS = set()


def add(name, svg, label):
    ICONS[name] = (svg, label)


def add_camera(name, badge, label, glyph=None, dashed=False):
    BADGE_OF[name] = badge
    CAMERA_SIGNS.add(name)
    add(name, camera_token(glyph, dashed), label)


HZ = lambda g: token(AMBER, g)

for v in (5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 110, 120):
    add(f"speed_limit_{v}", speed_limit(v), f"P.127 Tốc độ tối đa {v} km/h")
add("limit_80", speed_limit(80), "P.127 Tốc độ tối đa 80 km/h")
add("retrict_unknown", token(MUTED, text("?", C, C, 92, WHITE), "18 14"), "Hạn chế chưa xác định")

add("noEntry", prohibition(P_STRAIGHT), "P.136 Cấm đi thẳng")
add("noEntryNoLeftTurn", prohibition(P_STRAIGHT_LEFT), "P.138 Cấm đi thẳng và rẽ trái")
add("noEntryNoRightTurn", prohibition(mirror(P_STRAIGHT_LEFT)), "P.139 Cấm đi thẳng và rẽ phải")
add("noLeftTurn", prohibition(P_LEFT), "P.123a Cấm rẽ trái")
add("noRightTurn", prohibition(mirror(P_LEFT)), "P.123b Cấm rẽ phải")
add("noLeftTurnNoRightTurn", prohibition(P_LEFT_RIGHT), "P.137 Cấm rẽ trái và rẽ phải")
add("noUTurnLeft", prohibition(P_UTURN), "P.124a Cấm quay đầu xe")
add("noUTurnRight", prohibition(mirror(P_UTURN)), "P.124a lật gương: cấm quay đầu xe")
add("noLeftTurnUTurn", prohibition(P_LEFT_UTURN), "P.124c Cấm rẽ trái và quay đầu xe")
add("noRightTurnUTurn", prohibition(P_RIGHT_UTURN), "P.124d Cấm rẽ phải và quay đầu xe")
add("no_passing_in", prohibition(car_front_solid(87, Q_RED) + car_front_solid(169, Q_BLACK), slash=False),
    "P.125 Cấm vượt")
add("no_passing_out", end_of_restriction(car_front_solid(87, Q_BLACK) + car_front_solid(169, Q_BLACK)),
    "DP.133 Hết cấm vượt")
add("closure", token(RED, barrier()), "Đường bị chặn")
add("blocked-lane", token(RED, road() + group(barrier(), 64, 70, 0.5)), "Làn bị chắn")
add("closed-lane-crash", token(RED, road() + burst(128, 128, 30)), "Đóng làn do tai nạn")
add("closed-lane-construction", token(RED, road() + group(cone(), 64, 64, 0.5)), "Đóng làn do thi công")

add("straightAheadOnly", mandatory(R_STRAIGHT), "R.301a Hướng đi phải theo: đi thẳng")
add("rightTurnOnly", mandatory(R_RIGHT), "R.301d Hướng đi phải theo: rẽ phải")
add("leftTurnOnly", mandatory(mirror(R_RIGHT)), "R.301e Hướng đi phải theo: rẽ trái")
add("straightAndRightTurnOnly", mandatory(R_STRAIGHT_RIGHT), "R.301f Hướng đi phải theo: đi thẳng và rẽ phải")
add("straightAndLeftTurnOnly", mandatory(mirror(R_STRAIGHT_RIGHT)), "R.301g Hướng đi phải theo: đi thẳng và rẽ trái")
add("leftAndRightTurnOnly", mandatory(R_LEFT_RIGHT), "R.301h Hướng đi phải theo: rẽ trái và rẽ phải")
add("khu_dan_cu", blue_panel(skyline()), "R.420 Bắt đầu khu đông dân cư")
add("residential_area_in", blue_panel(skyline()), "R.420 Bắt đầu khu đông dân cư")
add("residential_area_out", blue_panel(skyline() + stroke("M232 64L24 192", Q_RED, BAR)), "R.421 Hết khu đông dân cư")
add("highway_rest_area", blue_panel(I_REST_AREA), "I.431 Trạm dừng nghỉ")
add("stop_lane", blue_panel(I_EMERGENCY_LANE), "I.448 Làn dừng khẩn cấp")
add("toll", yellow_panel(IE_TOLL), "IE.472e Trạm thu phí")
add("toll_etc", yellow_panel(IE_TOLL_ETC), "IE.472c Thu phí không dừng")

add("dangerous-curves", warning(W_CURVES), "W.202a Nhiều chỗ ngoặt nguy hiểm liên tiếp")
add("intersection", warning(W_CROSSROADS), "W.205a Đường giao nhau")
add("dangerous-intersection", warning(W_CROSSROADS), "W.205a Đường giao nhau")
add("fork", warning(W_FORK), "W.205 Ngã ba hình chữ Y")
add("merge", warning(W_SIDE_ROAD), "W.207 Giao với đường nhánh nhập vào")
add("lanes-merging", warning(W_SIDE_ROAD), "W.207 Giao với đường nhánh nhập vào")
add("narrow-bridge", warning(W_BRIDGE), "W.212 Cầu hẹp")
add("both-shoulders-ending", warning(W_NARROW_BOTH), "W.203a Đường bị hẹp cả hai bên")
add("left-shoulder-ending", warning(W_NARROW_LEFT), "W.203b Đường bị hẹp về phía trái")
add("left-lane-ending", warning(W_NARROW_LEFT), "W.203b Đường bị hẹp về phía trái")
add("right-shoulder-ending", warning(mirror(W_NARROW_LEFT)), "W.203c Đường bị hẹp về phía phải")
add("right-lane-ending", warning(mirror(W_NARROW_LEFT)), "W.203c Đường bị hẹp về phía phải")
add("highway-crosswalk", warning(W_PEDESTRIAN), "W.224 Đường người đi bộ cắt ngang")
add("raised-crosswalk", warning(W_PEDESTRIAN), "W.224 Đường người đi bộ cắt ngang")
add("school-zone", warning(W_CHILDREN), "W.225 Trẻ em")
add("speed-bumps", warning(W_BUMP), "W.221b Đường có gồ giảm tốc")
add("topes", warning(W_BUMPS), "W.221b Gồ giảm tốc liên tiếp")
add("railway", warning(W_LOCOMOTIVE), "W.211a Giao nhau với đường sắt không có rào chắn")
add("tunnel", warning(W_TUNNEL), "W.240 Đường hầm")
add("dangerous-zone", warning(W_EXCLAMATION), "W.233 Nguy hiểm khác")
add("slow_down", warning(W_SLOW), "W.245a Đi chậm")
add("cyclist", warning(W_CYCLIST), "W.226 Đường người đi xe đạp cắt ngang")
add("animal", warning(W_CATTLE), "W.230 Gia súc")
add("slippery-road", warning(W_SLIPPERY), "W.222a Đường trơn")

add("accident-minor", HZ(car_front() + burst(178, 86, 18)), "Va chạm nhẹ")
add("accident", HZ(car_front() + burst(128, 84, 30)), "Tai nạn")
add("hazard-stopped", HZ(car_front() + group(triangle_bang(), 140, 40, 0.42)), "Xe dừng trên đường")
add("emergency-vehicle", HZ(line("M94 156A34 34 0 0 1 162 156Z", WHITE, L) + line("M80 156H176V174H80Z", WHITE, L) +
                           line("M128 72V92M84 96L96 108M172 96L160 108", WHITE, M)), "Xe ưu tiên")
add("assistance", HZ(text("SOS", C, C, 46, WHITE)), "Cần hỗ trợ")
add("hazard", HZ(triangle_bang()), "Nguy hiểm")
add("hazardonroad", HZ(road() + small_bang(128, 140, 0.5)), "Nguy hiểm trên đường")
add("hazard-object-on-road", HZ(road() + '<rect x="110" y="132" width="36" height="36" rx="6" fill="#F2F5F9"/>'), "Vật cản trên đường")
add("hazard-on-shoulder", HZ(road() + small_bang(184, 140, 0.42)), "Nguy hiểm ở lề")
add("hazard-pothole", HZ(road() + '<ellipse cx="128" cy="150" rx="26" ry="11" fill="#F2F5F9"/>'), "Ổ gà")
add("hazard-roadkill", HZ(road(MUTED) + group(paw(), 64, 64, 0.5)), "Động vật chết trên đường")
add("hazard-construction", HZ(cone()), "Công trình trên đường")
add("hazard-broken-light", HZ(traffic_light(MUTED) + line("M168 82L184 100L172 108L188 124", WHITE, M)), "Đèn tín hiệu hỏng")
add("hazard-animals", HZ(paw()), "Động vật trên đường")
add("missing-sign", HZ(circle(128, 104, 38, "none", WHITE, M, "12 10") + text("?", 128, 104, 34, WHITE) +
                      line("M128 142V190", WHITE, L)), "Mất biển báo")
add("oil-spill", HZ(line("M128 70C128 70 98 108 98 128A30 30 0 0 0 158 128C158 108 128 70 128 70Z", WHITE, L) +
                   line("M80 184Q128 168 176 184", WHITE, M)), "Tràn dầu")
add("bad-weather", HZ(cloud() + line("M132 142L118 166H138L124 190", WHITE, M)), "Thời tiết xấu")
add("rain", HZ(cloud() + line("M104 152L96 172M128 152L120 172M152 152L144 172", WHITE, M)), "Mưa")
add("hazard-weather-flood", HZ(waves(122) + waves(152) + waves(182)), "Ngập nước")
add("hazard-weather-fog", HZ(group(cloud(), 0, -16) + line("M76 152H180M88 176H168", WHITE, M)), "Sương mù")
add("hazard-weather-hail", HZ(cloud() + circle(104, 162, 8, WHITE) + circle(128, 176, 8, WHITE) + circle(152, 162, 8, WHITE)), "Mưa đá")
add("hazard-weather-ice", HZ(snowflake(128, 112, 40, M) + line("M74 178H182", WHITE, L)), "Đường đóng băng")
add("hazard-weather-snow", HZ(snowflake()), "Tuyết")
add("unplowed-road", HZ(road() + fill("M90 170Q110 140 128 156Q146 136 166 170Z", WHITE)), "Đường chưa dọn tuyết")

add_camera("police", "star", "Cảnh sát giao thông", police)
add_camera("traffic_camera", None, "Camera giao thông")
add_camera("police-mobile-camera", "radar", "Camera tốc độ di động")
add_camera("penalty_camera", "bang", "Camera phạt nguội")
add_camera("speed_limit_camera", "limit", "Camera tốc độ")
add_camera("average-speed-enforcement", "TB", "Đo tốc độ trung bình")
add_camera("red-light-and-speed-camera", "redlimit", "Camera đèn đỏ và tốc độ")
add_camera("camera_ai", "AI", "Camera AI")
add_camera("bus-lane-cam", "BUS", "Camera làn xe buýt")
add_camera("distance-between-vehicles-camera", "distance", "Camera khoảng cách xe")
add_camera("phone-camera", "phone", "Camera dùng điện thoại")
add_camera("seatbelt-camera", "belt", "Camera dây an toàn")
add_camera("stop-sign-camera", "stop", "Camera biển dừng")
add_camera("noise-camera", "noise", "Camera tiếng ồn")
add_camera("hov-camera", "HOV", "Camera làn HOV")
add_camera("dummy-camera", "cross", "Camera giả", dashed=True)


# ---------------------------------------------------------------- sticker rendering
# Every icon is drawn flat above, then rendered in flat cartoon colour: a flat shade crescent on the
# lower right and a hard drop shadow, like report icons on Waze maps.
STICKER_SCALE, STICKER_CENTER_Y = 0.86, 122   # room for the shadow on the artboard
SHADE_SHIFT, SHADE_OPACITY = 14, 0.2
SHADOW_DROP, SHADOW_OPACITY = 12, 0.45
BADGE_EDGE = {"limit": 35, "red": 34, "redlimit": 41, "stop": 38, "cross": 32}  # outer radius; badge discs 35
BADGE_BASE = 6   # white base around a corner badge, drawn above the shading


def shape_of(name):
    code = ICONS[name][1].split(" ")[0]
    if code.startswith("W."):
        return "triangle"
    if code.startswith(("I.", "IE.", "S.", "R.420", "R.421")):
        return "panel"
    return "circle" if code[:2] in ("P.", "R.", "DP") or name in CAMERA_SIGNS else "token"


def silhouette(name, attrs):
    shape = shape_of(name)
    if shape == "triangle":
        return f'<path d="{rounded(TRIANGLE, CORNER)}" {attrs}/>'
    if shape == "panel":
        x, y, w, h = PANEL
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{CORNER}" {attrs}/>'
    out = f'<circle cx="{C}" cy="{C}" r="{128 if shape == "token" else P_OUT}" {attrs}/>'
    return out + badge_base(name, attrs)


def badge_base(name, attrs):
    badge = BADGE_OF.get(name)
    if not badge:
        return ""
    if badge in BADGES:
        return f'<circle cx="{BX}" cy="{BY}" r="{BADGE_EDGE.get(badge, 35) + BADGE_BASE}" {attrs}/>'
    w, h = 30 + 22 * len(badge) + 8 + 2 * BADGE_BASE, 62 + 2 * BADGE_BASE
    return f'<rect x="{BX - w / 2:g}" y="{BY - h / 2:g}" width="{w:g}" height="{h:g}" rx="{h / 2 - 9:g}" {attrs}/>'


def sticker(name, uid=None):
    uid = uid or name
    body = ICONS[name][0].replace(Q_BLACK, INK).replace('stroke-linecap="butt"', 'stroke-linecap="round"')
    mask = (f'<defs><mask id="shade-{uid}" maskUnits="userSpaceOnUse" x="0" y="0" width="256" height="256">'
            + silhouette(name, 'fill="#FFFFFF"') +
            f'<g transform="translate({-SHADE_SHIFT} {-SHADE_SHIFT})">' + silhouette(name, 'fill="#000000"') +
            '</g></mask></defs>')
    layers = (f'<g transform="translate(0 {SHADOW_DROP})" opacity="{SHADOW_OPACITY}">' +
              silhouette(name, f'fill="{INK}"') + '</g>' +
              body + f'<g mask="url(#shade-{uid})">' + silhouette(name, f'fill="{INK}" opacity="{SHADE_OPACITY}"') + '</g>')
    if BADGE_OF.get(name):
        layers += badge_base(name, 'fill="#FFFFFF"') + badge_svg(BADGE_OF[name])
    s = STICKER_SCALE
    return mask + f'<g transform="translate({C - s * C:g} {STICKER_CENTER_Y - s * C:g}) scale({s})">{layers}</g>'


# ---------------------------------------------------------------- output
def svg_doc(body, label, w=256, h=256):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f'<title>{label}</title>{body}</svg>')


def main():
    os.makedirs(os.path.join(OUT, "svg"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "png"), exist_ok=True)
    for name, (body, label) in sorted(ICONS.items()):
        svg_path = os.path.join(OUT, "svg", name + ".svg")
        with open(svg_path, "w", encoding="utf-8") as handle:
            handle.write(svg_doc(sticker(name), label))
        subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", "-o",
                        os.path.join(OUT, "png", name + ".png"), svg_path], check=True)
    # Contact sheet on the bubble surface colour, for review only.
    cols, cell = 12, 150
    rows = (len(ICONS) + cols - 1) // cols
    sheet = f'<rect width="{cols * cell}" height="{rows * cell + 20}" fill="#07090C"/>'
    for i, (name, (body, label)) in enumerate(sorted(ICONS.items())):
        x, y = (i % cols) * cell, (i // cols) * cell
        sheet += group(sticker(name, "sheet-" + name), x + 27, y + 10, 96 / 256)
        sheet += (f'<text x="{x + cell / 2:g}" y="{y + 128}" font-family="Helvetica" font-size="10" '
                  f'fill="#B7C0CC" text-anchor="middle">{name[:24]}</text>')
    sheet_path = os.path.join(OUT, "contact-sheet.svg")
    with open(sheet_path, "w", encoding="utf-8") as handle:
        handle.write(svg_doc(sheet, "GMapHUD Halo icons", cols * cell, rows * cell + 20))
    subprocess.run(["rsvg-convert", "-o", os.path.join(OUT, "contact-sheet.png"), sheet_path], check=True)
    print(len(ICONS), "icons ->", OUT)


if __name__ == "__main__":
    main()
