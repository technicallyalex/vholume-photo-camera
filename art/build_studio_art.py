"""Rasterize flat-shaded turntables from low-poly meshes for the in-game menu."""

from math import cos, sin, sqrt, tau
from pathlib import Path
import sys

from PIL import Image, ImageDraw


W, H, COLS, ROWS = 112, 96, 8, 6
TURN_TABLE_SCALE = 2
ANTIALIAS = 2


def box(x, y, z, w, d, h, color):
    v = [(x + sx * w / 2, y + sy * d / 2, z + sz * h / 2)
         for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    return [(tuple(v[i] for i in ids), color) for ids in
            ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5))]


def cylinder(z, height, radius, color, sides=10, top_radius=None):
    ring = [(cos(i * tau / sides), sin(i * tau / sides)) for i in range(sides)]
    top_radius = radius if top_radius is None else top_radius
    low = [(x * radius, y * radius, z) for x, y in ring]
    high = [(x * top_radius, y * top_radius, z + height) for x, y in ring]
    sides_mesh = [((low[i], low[(i + 1) % sides], high[(i + 1) % sides], high[i]), color) for i in range(sides)]
    return sides_mesh + [(tuple(reversed(low)), color), (tuple(high), color)]


def roll(color, band):
    return (cylinder(-.70, 1.38, .54, color)
            + cylinder(-.71, .14, .57, (46, 52, 48))
            + cylinder(.55, .15, .57, (43, 48, 45))
            + cylinder(.70, .16, .25, (92, 95, 86))
            + cylinder(.04, .27, .551, band)
            + box(.65, -.03, -.24, .57, .025, .61, (88, 66, 53)))


def camera():
    def shell(profile, front, back, color):
        near = tuple((x, front, z) for x, z in profile)
        far = tuple((x, back, z) for x, z in profile)
        sides = []
        for i in range(len(profile)):
            j = (i + 1) % len(profile)
            sides.append(((near[i], far[i], far[j], near[j]), color))
        return sides + [(near, color), (tuple(reversed(far)), color)]

    def barrel(start, depth, radius, color):
        return [(tuple((x, -z, y - .06) for x, y, z in face), tint)
                for face, tint in cylinder(start, depth, radius, color, 10)]

    metal, leather, trim = (157, 170, 151), (68, 81, 71), (192, 148, 86)
    body = [(-1.12, -.55), (-1.02, -.65), (1.02, -.65), (1.12, -.55),
            (1.12, .43), (1.02, .53), (-1.02, .53), (-1.12, .43)]
    prism = [(-.47, .51), (.47, .51), (.29, .87), (-.29, .87)]
    return (shell(body, -.24, .45, metal)
            + shell(prism, -.19, .34, metal)
            + box(0, -.25, -.07, 2.15, .05, .91, leather)
            + box(.83, -.33, -.09, .39, .18, .82, (79, 94, 82))
            + box(0, .45, -.07, 1.91, .05, .91, leather)
            + box(0, .34, .66, .35, .05, .15, (64, 84, 79))
            + box(.74, .09, .56, .34, .25, .09, trim)
            + box(-.69, .08, .56, .32, .23, .10, (84, 98, 85))
            + barrel(.25, .18, .52, (100, 117, 103))
            + barrel(.43, .20, .46, (76, 91, 81))
            + barrel(.63, .06, .47, trim)
            + barrel(.69, .035, .42, (89, 117, 102))
            + barrel(.725, .015, .32, (47, 88, 87))
            + barrel(.74, .012, .22, (79, 134, 125))
            + box(-.08, -.754, .025, .12, .012, .07, (156, 185, 161)))


def prime_lenses():
    shell, rubber, metal = (86, 94, 83), (48, 56, 50), (132, 138, 119)
    gold, pale = (175, 138, 78), (161, 164, 141)
    # Each profile sets the end height, radius, and material of each barrel section.
    profiles = {
        16: ((-.53,.57,shell),(-.34,.68,rubber),(-.15,.87,shell),(.05,.94,rubber)),
        24: ((-.48,.59,shell),(-.22,.69,rubber),(-.12,.72,gold),(.26,.78,shell)),
        35: ((-.49,.58,metal),(-.35,.59,shell),(.04,.64,rubber),(.39,.67,shell)),
        50: ((-.55,.56,shell),(-.45,.63,metal),(-.15,.65,rubber),(.12,.59,shell)),
        85: ((-.43,.58,shell),(.02,.71,rubber),(.13,.71,gold),(.64,.75,shell)),
        135: ((-.42,.52,rubber),(.03,.56,shell),(.31,.60,rubber),(.79,.62,shell)),
        200: ((-.49,.52,shell),(-.04,.58,rubber),(.28,.61,shell),(.39,.68,gold),(.88,.70,rubber)),
        600: ((-.43,.51,pale),(-.10,.57,rubber),(.27,.67,pale),(.46,.74,rubber),(.94,.80,pale)),
    }
    models = {}
    for focal, profile in profiles.items():
        mesh = cylinder(-.86,.12,.46,metal,12)
        start = -.74
        for end, radius, tint in profile:
            mesh += cylinder(start,end-start,radius,tint,12)
            if tint == rubber:
                for groove in range(1,5):
                    at = start + groove*(end-start)/5
                    mesh += cylinder(at,.012,radius+.012,shell,12)
            start = end
        mesh += cylinder(start,.04,radius,metal,12,top_radius=radius*.93)
        mesh += cylinder(start+.04,.016,radius*.80,(39,51,47),12)
        mesh += cylinder(start+.056,.018,radius*.66,(49,90,89),12,top_radius=radius*.61)
        mesh += cylinder(start+.074,.006,radius*.38,(76,117,112),12)
        if focal == 600:
            mesh += box(.57,0,-.31,.24,.20,.32,metal)
            mesh += box(.72,0,-.50,.44,.36,.11,rubber)
        else:
            mesh += box(.37,-.35,-.63,.15,.07,.08,pale)
        models[f"lens{focal}"] = mesh
    return models


def frame(aspect):
    x, z = .90 * min(1, aspect), .90 * min(1, 1 / aspect)
    t = .12
    ink = (196, 169, 116)
    return (box(0, 0, z-t/2, 2*x, .19, t, ink) + box(0, 0, t/2-z, 2*x, .19, t, ink)
            + box(t/2-x, 0, 0, t, .19, 2*(z-t), ink)
            + box(x-t/2, 0, 0, t, .19, 2*(z-t), ink)
            + box(0, .09, 0, 2*x, .07, 2*z, (44, 58, 55))
            + box(0, -.025, 0, 2*(x-t), .10, 2*(z-t), (90, 125, 104)))


def segment(start, end, width, depth, color):
    def normal(v):
        length = sqrt(sum(c*c for c in v))
        return tuple(c/length for c in v)

    direction = tuple(b-a for a,b in zip(start,end))
    z = normal(direction)
    y = normal((0, z[2], -z[1]))
    x = (y[1]*z[2]-y[2]*z[1], y[2]*z[0]-y[0]*z[2], y[0]*z[1]-y[1]*z[0])
    center = tuple((a+b)/2 for a,b in zip(start,end))
    length = sqrt(sum(c*c for c in direction))

    def point(p):
        return tuple(center[i]+p[0]*x[i]+p[1]*y[i]+p[2]*z[i] for i in range(3))

    return [(tuple(point(p) for p in face), tint)
            for face,tint in box(0,0,0,width,depth,length+.03,color)]


def subject(pose):
    # Side-view joint positions for the same five poses offered by the game.
    hip, chest, knees, feet, elbows, hands = (
        ((0,-.03), (0,.49), ((0,-.43),(0,-.43)), ((0,-.84),(0,-.84)), ((0,.12),(0,.12)), ((0,-.19),(0,-.19))),
        ((.15,-.38), (-.14,.07), ((-.31,-.54),(-.25,-.57)), ((.05,-.84),(.18,-.84)), ((-.26,-.18),(.01,-.19)), ((-.45,-.32),(-.22,-.40))),
        ((0,-.05), (-.03,.47), ((-.27,-.39),(.19,-.45)), ((-.39,-.84),(.38,-.79)), ((.12,.07),(-.22,.09)), ((.20,-.20),(-.34,-.15))),
        ((.05,-.08), (-.19,.40), ((-.43,-.40),(.34,-.36)), ((-.44,-.84),(.53,-.61)), ((.13,.15),(-.43,.22)), ((-.10,.16),(-.64,.34))),
        ((.06,-.42), (-.06,.03), ((-.28,-.55),(.13,-.76)), ((-.28,-.84),(.46,-.84)), ((-.14,-.25),(.10,-.26)), ((-.27,-.50),(.07,-.48))),
    )[pose]
    suit, pants, skin = (90,106,97), (56,66,64), (177,146,110)
    cy, cz = chest
    mesh = segment((0,*hip),(0,*chest),.55,.32,suit)
    mesh += box(0,cy-.16,cz-.12,.53,.045,.075,(158,168,152))
    mesh += box(0,cy-.06,cz+.20,.32,.30,.33,skin)
    mesh += box(0,cy-.035,cz+.35,.34,.33,.10,(68,54,43))
    for i, side in enumerate((-1,1)):
        arm, leg = side*.30, side*.15
        mesh += segment((arm,*chest),(arm*1.15,*elbows[i]),.145,.17,suit)
        mesh += segment((arm*1.15,*elbows[i]),(arm*1.17,*hands[i]),.13,.15,(102,121,109))
        mesh += box(arm*1.17,*hands[i],.13,.14,.15,skin)
        mesh += segment((leg,*hip),(leg,*knees[i]),.25,.28,pants)
        mesh += segment((leg,*knees[i]),(leg,*feet[i]),.21,.23,(68,81,74))
        mesh += box(leg,feet[i][0]-.075,feet[i][1]-.045,.225,.37,.14,(124,117,95))
    return mesh


def objects():
    palette = {
        "neutral": ((104, 115, 110), (158, 170, 158)),
        "warm-color-200": ((223, 161, 39), (173, 49, 30)),
        "soft-color-400": ((196, 153, 104), (66, 118, 103)),
        "crisp-bw-400": ((181, 186, 183), (116, 53, 153)),
        "fine-bw-100": ((61, 67, 65), (166, 175, 159)),
        "vivid-slide-50": ((123, 177, 74), (157, 49, 88)),
        "vivid-color-100": ((210, 65, 54), (224, 180, 63)),
        "grainy-bw-400": ((81, 95, 72), (183, 203, 174)),
        "tungsten-800": ((75, 117, 160), (208, 76, 53)),
        "fast-color-1600": ((51, 139, 88), (179, 84, 166)),
    }
    models = {name: roll(*colors) for name, colors in palette.items()}
    models["camera"] = camera()
    models.update(prime_lenses())
    models["instant-color-600"] = (box(0, 0, 0, 1.35, .29, 1.45, (218, 216, 188))
                         + box(0, -.16, .13, 1.03, .05, 1.0, (66, 111, 104))
                         + box(0, -.19, -.50, .91, .04, .12, (183, 113, 58)))
    models["folder"] = (box(0, .14, .05, 1.59, .16, 1.03, (178, 122, 62))
                        + box(-.38, .14, .64, .74, .16, .23, (207, 147, 76))
                        + box(0, -.02, .09, 1.38, .15, .86, (194, 190, 162))
                        + box(0, -.18, -.06, 1.62, .19, .81, (225, 162, 82)))
    for i in range(5):
        models[f"subject{i+1}"] = subject(i)
    for i, aspect in enumerate((3/2, 4/3, 1, 16/9, 5/4), 1):
        models[f"frame{i}"] = frame(aspect)
        if aspect != 1:
            models[f"frame{i}p"] = frame(1/aspect)
    return models


def raster(mesh, index):
    yaw = index * tau / (COLS * ROWS) + .24
    scale = TURN_TABLE_SCALE * ANTIALIAS
    image = Image.new("RGBA", (W * scale, H * scale))
    draw = ImageDraw.Draw(image)

    def transform(point):
        x, y, z = point
        x, y = cos(yaw) * x - sin(yaw) * y, sin(yaw) * x + cos(yaw) * y
        # Y sorts from far to near. Pitch the camera down to show the tops.
        return x, .94 * y - .342 * z, .94 * z + .342 * y

    draw.ellipse(((W/2 - 30)*scale, 78*scale, (W/2 + 30)*scale, 88*scale), fill=(6, 9, 8, 145))
    faces = []
    for verts, color in mesh:
        v = tuple(transform(p) for p in verts)
        a = [v[1][i]-v[0][i] for i in range(3)]
        b = [v[2][i]-v[0][i] for i in range(3)]
        n = [a[(i+1)%3]*b[(i+2)%3]-a[(i+2)%3]*b[(i+1)%3] for i in range(3)]
        length = sqrt(sum(c*c for c in n))
        shade = .63 + .38 * max(0, (-.42*n[0] - .48*n[1] + .76*n[2]) / length)
        rgba = tuple(min(255, round(c*shade)) for c in color) + (255,)
        screen = [((W/2 + x*35)*scale, (46-z*35)*scale) for x, _, z in v]
        faces.append((sum(p[1] for p in v)/len(v), screen, rgba))
    for _, screen, color in sorted(faces, reverse=True):
        draw.polygon(screen, fill=color)
    return image.resize((W * TURN_TABLE_SCALE, H * TURN_TABLE_SCALE), Image.Resampling.LANCZOS)


def icon(output, name, extent, painter):
    # Render silhouettes above the final size so thin diagonals survive scaling.
    size = 96 if name != "reticle-circle" else 384
    scale = size * ANTIALIAS / extent
    image = Image.new("RGBA", (size * ANTIALIAS, size * ANTIALIAS))
    painter(ImageDraw.Draw(image), scale)
    image.resize((size, size), Image.Resampling.LANCZOS).save(output / f"{name}.png", optimize=True)


def interface_art(output):
    gold = (220, 206, 165, 255)
    glyphs = {
        "photos": [[(3,7),(3,5),(12,5),(15,8),(21,8),(21,19),(3,19),(3,7),(21,7)]],
        "film": [[(4,5),(20,5),(20,19),(4,19),(4,5)], [(4,9),(20,9)], [(4,15),(20,15)],
                 [(8,5),(8,9)], [(16,5),(16,9)], [(8,15),(8,19)], [(16,15),(16,19)]],
        "frame": [[(3,5),(21,5),(21,19),(3,19),(3,5)], [(6,15),(10,10),(14,15),(17,12),(19,15)]],
        "subject": [[(5,21),(5,17),(8,14),(16,14),(19,17),(19,21)]],
        "back": [[(10,6),(4,12),(10,18)], [(4,12),(20,12)]],
        "keybinds": [[(2,6),(22,6),(22,18),(2,18),(2,6)], [(8,14),(16,14)],
                     [(6,10),(7,10)], [(11,10),(12,10)], [(16,10),(18,10)]],
        "finder": [[(8,5),(3,5),(3,9)], [(16,5),(21,5),(21,9)],
                   [(3,15),(3,19),(8,19)], [(21,15),(21,19),(16,19)],
                   [(10,12),(14,12)], [(12,10),(12,14)]],
        "exposure": [[(3,3),(21,3),(21,21),(3,21),(3,3)], [(6,8),(12,8)],
                     [(9,5),(9,11)], [(13,16),(19,16)], [(5,19),(19,5)]],
        "rotate": [[(3,11),(3,6),(8,6)], [(21,13),(21,18),(16,18)]],
    }

    def glyph(draw, scale, name):
        def coords(points):
            return [(round(x*scale), round(y*scale)) for x, y in points]

        def ring(bounds):
            draw.ellipse(coords(bounds), outline=gold, width=round(1.6*scale))

        for path in glyphs.get(name, ()):
            draw.line(coords(path), fill=gold, width=round(1.6*scale), joint="curve")
        if name == "subject":
            ring([(8,3),(16,11)])
        elif name == "lens":
            ring([(3,3),(21,21)])
            ring([(8,8),(16,16)])
        elif name == "reticle":
            ring([(5,5),(19,19)])
            for path in ([(12,2),(12,8)], [(12,16),(12,22)], [(2,12),(8,12)], [(16,12),(22,12)]):
                draw.line(coords(path), fill=gold, width=round(1.6*scale))
        elif name == "rotate":
            bounds = coords([(3,3),(21,21)])
            for start, end in ((210,355), (30,175)):
                draw.arc(bounds, start, end, fill=gold, width=round(1.6*scale))

    for name in (*glyphs, "lens", "reticle"):
        icon(output, f"ui-{name}", 24, lambda draw, scale: glyph(draw, scale, name))

    def reticle(draw, scale):
        for radius in (47, 23):
            bounds = tuple(round(v*scale) for v in (64-radius,64-radius,64+radius,64+radius))
            draw.ellipse(bounds, outline=(255,255,255,255), width=round(2*scale))

    icon(output, "reticle-circle", 128, reticle)

    def indicator(draw, scale, name):
        green = (157,250,115,255)
        if name == "aligned":
            draw.ellipse((5*scale,5*scale,27*scale,27*scale), fill=green)
        else:
            points = [(5,16),(27,4),(27,28)] if name == "near" else [(27,16),(5,4),(5,28)]
            draw.polygon([(x*scale,y*scale) for x,y in points], fill=green)

    for name in ("near", "aligned", "far"):
        icon(output, f"focus-{name}", 32, lambda draw, scale: indicator(draw, scale, name))


def build(output):
    output.mkdir(parents=True, exist_ok=True)
    width, height = W * TURN_TABLE_SCALE, H * TURN_TABLE_SCALE
    for name, mesh in objects().items():
        atlas = Image.new("RGBA", (width * COLS, height * ROWS))
        for index in range(COLS * ROWS):
            atlas.paste(raster(mesh, index), (index % COLS * width, index // COLS * height))
        atlas.save(output / f"{name}.png", optimize=True)
    interface_art(output)


if __name__ == "__main__":
    build(Path(sys.argv[1]))
