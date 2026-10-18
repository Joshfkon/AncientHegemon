#!/usr/bin/env python3
"""Territory outlines traced by hand from Josh's photo of the painted board.

Coordinates are pixels in that photo (both halves side by side, 2000×924; the left half spans
x 105–1003, the right half 1010–1900). Neighbors share border points, so the outlines tile.
Writes AncientHegemon/Resources/map_shapes.json and checks that territories drawn as touching
are exactly those linked in map.json, listing any disagreement between painting and rules.

Usage: python3 tools/board_shapes.py
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "HegemonCore/Sources/HegemonCore/Resources/map.json"
OUT = ROOT / "AncientHegemon/Resources/map_shapes.json"
SIZE = (2000, 924)

SHAPES = {
    # Islands of the north.
    "hibernia": [(328, 210), (335, 170), (352, 125), (380, 90), (410, 65), (432, 58), (440, 85),
                 (430, 130), (415, 170), (390, 200), (360, 215)],
    "caledonia": [(447, 20), (470, 12), (530, 12), (528, 35), (505, 55), (475, 70), (452, 68), (445, 45)],
    "britain": [(452, 68), (475, 70), (505, 55), (528, 35), (545, 75), (560, 120), (558, 160),
                (538, 178), (500, 182), (465, 176), (447, 150), (450, 110)],
    "sitones": [(650, 12), (805, 12), (805, 40), (797, 100), (782, 140), (770, 158), (758, 140),
                (748, 90), (728, 48), (660, 42)],
    # Western Europe.
    "saxone": [(603, 200), (606, 185), (630, 172), (655, 165), (655, 85), (672, 62), (700, 60),
               (708, 100), (705, 165), (730, 170), (782, 172), (778, 230), (735, 225), (700, 218), (645, 212)],
    "suebi": [(782, 172), (800, 158), (830, 125), (860, 95), (890, 85), (900, 150), (930, 230),
              (960, 262), (900, 245), (870, 240), (820, 238), (778, 230)],
    "venedi": [(890, 85), (905, 12), (1003, 12), (1003, 268), (960, 262), (930, 230), (900, 150)],
    "gaul": [(432, 302), (405, 270), (390, 245), (385, 225), (405, 208), (450, 205), (520, 200),
             (603, 200), (645, 212), (620, 240), (590, 280), (565, 318), (550, 318), (500, 310), (470, 305)],
    "hispania": [(205, 282), (260, 276), (330, 276), (390, 290), (415, 305), (420, 380), (370, 390),
                 (330, 396), (260, 410), (190, 416), (186, 370), (195, 320)],
    "pyrenees": [(415, 305), (432, 302), (470, 305), (500, 310), (550, 318), (555, 345), (550, 362),
                 (480, 378), (420, 380)],
    "baetica": [(190, 416), (260, 410), (330, 396), (370, 390), (420, 380), (480, 378), (550, 362),
                (545, 395), (510, 430), (480, 470), (440, 500), (380, 522), (300, 530), (230, 528),
                (205, 515), (182, 470)],
    "alps": [(645, 212), (700, 218), (735, 225), (778, 230), (820, 238), (818, 270), (812, 292),
             (800, 298), (760, 310), (705, 328), (650, 340), (610, 350), (588, 345), (565, 318),
             (590, 280), (620, 240)],
    "italia": [(705, 328), (760, 310), (800, 298), (815, 330), (840, 370), (865, 405), (875, 435),
               (858, 455), (845, 480), (838, 510), (815, 522), (808, 495), (818, 470), (798, 440),
               (768, 420), (742, 390), (722, 360)],
    "sardinia": [(650, 428), (665, 425), (670, 450), (668, 480), (660, 500), (650, 495), (645, 465)],
    "sicilia": [(725, 555), (748, 518), (778, 522), (792, 560), (770, 580), (740, 575)],
    "macedonia": [(820, 238), (870, 240), (900, 245), (960, 262), (1003, 268), (1003, 405), (975, 410),
                  (950, 385), (915, 380), (880, 372), (855, 345), (835, 318), (812, 292), (818, 270)],
    "greece": [(880, 372), (915, 380), (950, 385), (975, 410), (1003, 405), (990, 440), (978, 470),
               (965, 500), (955, 525), (940, 495), (925, 460), (905, 440), (890, 405)],
    "crete": [(950, 575), (1000, 560), (1060, 563), (1090, 580), (1060, 595), (1000, 592), (960, 590)],
    # North Africa.
    "mauretania": [(110, 575), (200, 555), (300, 548), (405, 550), (400, 610), (395, 675), (300, 690),
                   (200, 700), (110, 710)],
    "numidia": [(405, 550), (500, 548), (600, 545), (695, 540), (692, 600), (665, 640), (645, 655),
                (600, 648), (520, 655), (395, 675), (400, 610)],
    "sahara": [(110, 710), (200, 700), (300, 690), (395, 675), (520, 655), (600, 648), (645, 655),
               (560, 760), (500, 850), (450, 915), (110, 915)],
    "cyrenaica": [(645, 655), (700, 652), (780, 658), (860, 665), (855, 740), (865, 830), (870, 915),
                  (450, 915), (500, 850), (560, 760)],
    "libya": [(860, 665), (930, 635), (1003, 615), (1080, 625), (1160, 660), (1170, 760), (1200, 850),
              (1225, 915), (870, 915), (865, 830), (855, 740)],
    "egypt": [(1160, 660), (1220, 668), (1290, 655), (1330, 690), (1380, 730), (1450, 778), (1490, 850),
              (1530, 915), (1225, 915), (1200, 850), (1170, 760)],
    "petraea": [(1290, 655), (1310, 640), (1345, 640), (1380, 645), (1385, 670), (1410, 710), (1440, 745),
                (1450, 778), (1380, 730), (1330, 690)],
    "arabia": [(1380, 600), (1500, 592), (1650, 585), (1800, 580), (1900, 580), (1900, 915), (1650, 915),
               (1560, 820), (1490, 740), (1420, 670), (1380, 640), (1345, 640)],
    # The Balkans and the steppe.
    "dacia": [(1005, 12), (1200, 12), (1215, 90), (1235, 165), (1200, 195), (1165, 250), (1160, 300),
              (1100, 300), (1005, 298), (1005, 268)],
    "thrace": [(1005, 298), (1100, 300), (1160, 300), (1150, 330), (1140, 378), (1100, 402),
               (1050, 412), (1005, 405)],
    "scythe": [(1200, 12), (1330, 12), (1325, 80), (1318, 160), (1300, 200), (1250, 200), (1235, 165),
               (1215, 90)],
    "sarmatia": [(1330, 12), (1560, 12), (1545, 60), (1500, 90), (1450, 120), (1440, 200), (1380, 205),
                 (1318, 200), (1318, 160), (1325, 80)],
    "daha": [(1560, 12), (1900, 12), (1900, 180), (1820, 160), (1700, 170), (1600, 195), (1580, 150),
             (1545, 60)],
    "caucasus": [(1318, 200), (1380, 205), (1440, 200), (1450, 240), (1450, 300), (1420, 300),
                 (1340, 300), (1300, 280), (1300, 230)],
    # Anatolia and the east.
    "armenia": [(1185, 372), (1200, 320), (1260, 305), (1340, 300), (1420, 300), (1450, 300),
                (1460, 335), (1520, 362), (1480, 378), (1430, 370), (1400, 385), (1300, 375), (1200, 372)],
    "taurus": [(1200, 372), (1300, 375), (1400, 385), (1395, 405), (1370, 450), (1372, 500), (1338, 500),
               (1345, 450), (1350, 410), (1280, 397), (1200, 397)],
    "anatolia": [(1140, 430), (1170, 392), (1185, 372), (1200, 372), (1200, 397), (1280, 397), (1350, 410),
                 (1345, 450), (1335, 500), (1310, 515), (1285, 530), (1250, 530), (1210, 515),
                 (1160, 500), (1138, 470)],
    "cyprus": [(1205, 600), (1240, 585), (1275, 585), (1280, 605), (1245, 615), (1210, 615)],
    "syria": [(1338, 506), (1365, 500), (1380, 500), (1420, 520), (1470, 560), (1530, 575), (1500, 592),
              (1380, 600), (1345, 640), (1310, 640), (1315, 600), (1335, 558)],
    "mesopotamia": [(1400, 385), (1430, 370), (1480, 378), (1560, 400), (1600, 470), (1680, 520),
                    (1760, 565), (1700, 575), (1600, 580), (1530, 575), (1470, 560), (1420, 520),
                    (1380, 500), (1365, 500), (1370, 450), (1395, 405)],
    "media": [(1480, 378), (1520, 362), (1560, 400), (1600, 330), (1700, 330), (1800, 340), (1900, 330),
              (1900, 180), (1820, 160), (1700, 170), (1600, 195), (1580, 280), (1545, 345)],
    "persia": [(1560, 400), (1600, 330), (1700, 330), (1800, 340), (1900, 330), (1900, 440), (1840, 500),
               (1760, 565), (1680, 520), (1600, 470)],
}

# Names as lettered on the board: position and angle (degrees, clockwise), where they differ
# from the middle of the territory.
LABELS = {
    "hibernia": ((385, 140), -62), "caledonia": ((490, 32), 0), "britain": ((505, 125), 15),
    "sitones": ((725, 26), 0), "saxone": ((690, 190), 12), "suebi": ((845, 195), -8),
    "venedi": ((955, 125), 75), "dacia": ((1095, 135), 0), "scythe": ((1263, 105), 78),
    "sarmatia": ((1430, 92), 0), "daha": ((1690, 90), 0), "caucasus": ((1375, 225), 0),
    "gaul": ((480, 255), 0), "hispania": ((295, 355), 8), "pyrenees": ((485, 345), 0),
    "baetica": ((330, 455), -14), "alps": ((690, 270), -10), "italia": ((790, 390), 58),
    "macedonia": ((900, 320), 20), "greece": ((945, 450), 72), "thrace": ((1075, 360), 0),
    "armenia": ((1320, 335), -4), "taurus": ((1290, 386), 0), "anatolia": ((1240, 460), 8),
    "mesopotamia": ((1555, 495), 22), "media": ((1720, 265), 0), "persia": ((1700, 420), 8),
    "syria": ((1420, 560), -10), "petraea": ((1368, 700), 48), "arabia": ((1690, 710), 0),
    "egypt": ((1280, 840), 0), "libya": ((1000, 790), 0), "cyrenaica": ((690, 790), 0),
    "sahara": ((300, 775), 0), "numidia": ((520, 610), 0), "mauretania": ((260, 640), 0),
    "sicilia": ((757, 555), 0), "sardinia": ((657, 462), 80), "crete": ((1020, 578), 0),
    "cyprus": ((1243, 600), -10),
}

# Where each sea's name is painted, in open water.
SEA_LABELS = {
    "atlantic": (150, 470), "north_sea": (595, 135), "baltic": (855, 45), "western_med": (565, 480),
    "tyrrhenian": (715, 470), "ionian": (880, 585), "aegean": (1060, 475), "eastern_med": (1150, 580),
    "black_sea": (1235, 255), "caspian": (1510, 230), "red_sea": (1540, 840), "persian_gulf": (1840, 556),
}

# Rivers as painted (decoration; crossings in the rules come from map.json).
RIVERS = [
    [(606, 200), (700, 218), (790, 232), (900, 245), (960, 262), (1003, 293)],
    [(1005, 298), (1100, 300), (1160, 300)],
    [(190, 416), (260, 410), (330, 396), (420, 380)],
    [(1205, 12), (1218, 90), (1237, 165)],
    [(1333, 12), (1327, 80), (1320, 160), (1318, 200)],
    [(1430, 280), (1400, 330), (1395, 405), (1372, 450), (1380, 500), (1420, 520), (1470, 560), (1530, 575)],
    [(1450, 410), (1520, 440), (1600, 475), (1680, 520), (1760, 565)],
    [(1185, 670), (1240, 740), (1290, 810), (1330, 880), (1345, 915)],
]

# The painted mountain ranges, for the little peaks drawn on top.
PEAKS = {"alps": [(640, 300), (700, 280), (760, 265)], "pyrenees": [(450, 340), (500, 345)],
         "caucasus": [(1360, 260), (1410, 270)], "taurus": [(1240, 385), (1300, 388), (1360, 395)]}


def samples(poly, step=5):
    pts = []
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
        n = max(1, int(math.dist((x1, y1), (x2, y2)) // step))
        pts += [(x1 + (x2 - x1) * k / n, y1 + (y2 - y1) * k / n) for k in range(n)]
    return pts


def seg_dist(p, a, b):
    (px, py), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.dist(p, (ax + t * dx, ay + t * dy))


def touching(a, b, tolerance=9, min_length=25):
    """Two outlines touch if they run within `tolerance` px of each other for `min_length` px."""
    near = [p for p in samples(a) if any(seg_dist(p, b[i], b[(i + 1) % len(b)]) <= tolerance
                                         for i in range(len(b)))]
    return len(near) * 5 >= min_length


def centroid(poly):
    area = cx = cy = 0.0
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
        c = x1 * y2 - x2 * y1
        area += c
        cx += (x1 + x2) * c
        cy += (y1 + y2) * c
    area /= 2
    return (cx / (6 * area), cy / (6 * area))


def main():
    data = json.loads(MAP.read_text())
    ids = [t["id"] for t in data["territories"]]
    missing = [t for t in ids if t not in SHAPES]
    if missing:
        print("no outline for", missing)
        return 1

    drawn = set()
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            if touching(SHAPES[a], SHAPES[b]):
                drawn.add(frozenset((a, b)))
    rules = {frozenset(l[:2]) for l in data["landLinks"] if not (len(l) > 2 and l[2] == "strait")}
    straits = {frozenset(l[:2]) for l in data["landLinks"] if len(l) > 2 and l[2] == "strait"}

    problems = []
    for pair in sorted(rules - drawn, key=sorted):
        problems.append("in the rules but not touching on the painting: " + " – ".join(sorted(pair)))
    for pair in sorted(drawn - rules, key=sorted):
        kind = "strait drawn as a land border" if pair in straits else "touching on the painting but not in the rules"
        problems.append(f"{kind}: " + " – ".join(sorted(pair)))

    out = {
        "size": SIZE,
        "territories": {t: {"polygon": [list(p) for p in SHAPES[t]],
                            "label": list(LABELS[t][0]) if t in LABELS else [round(c) for c in centroid(SHAPES[t])],
                            "angle": LABELS[t][1] if t in LABELS else 0} for t in ids},
        "seas": {s: list(p) for s, p in SEA_LABELS.items()},
        "rivers": [[list(p) for p in r] for r in RIVERS],
        "peaks": {t: [list(p) for p in ps] for t, ps in PEAKS.items()},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, separators=(",", ":")))

    print(f"{len(ids)} outlines, {len(drawn)} borders drawn, {len(rules)} land links in the rules")
    for p in problems:
        print("  " + p)
    print("OK" if not problems else f"{len(problems)} disagreements")
    return 0


if __name__ == "__main__":
    sys.exit(main())
