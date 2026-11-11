"""Build the optical finder's LCD face and antialiased numeral atlas."""
from pathlib import Path

from PIL import Image, ImageDraw


def build(output):
    output.mkdir(parents=True, exist_ok=True)
    plate = Image.new("RGBA", (2048, 128))
    painter = ImageDraw.Draw(plate)
    for y in range(128):
        glow = 1 - abs(y - 60) / 70
        painter.line((0, y, 2047, y), fill=(int(155 + 16*glow), int(169 + 17*glow), int(139 + 13*glow), 255))
    painter.rectangle((0, 0, 2047, 127), outline=(54, 66, 51, 255), width=5)
    painter.line((7, 7, 2040, 7), fill=(205, 212, 180, 255), width=2)
    plate.save(output / "finder-lcd.png", optimize=True)

    cell_w, cell_h, scale = 36, 56, 4
    atlas = Image.new("RGBA", (16*cell_w*scale, cell_h*scale))
    painter = ImageDraw.Draw(atlas)
    segments = {
        "a": [(7,4),(26,4),(30,7),(26,10),(7,10),(3,7)],
        "b": [(26,12),(30,8),(33,12),(33,24),(30,28),(26,24)],
        "c": [(26,33),(30,29),(33,33),(33,45),(30,49),(26,45)],
        "d": [(7,47),(26,47),(30,50),(26,53),(7,53),(3,50)],
        "e": [(0,33),(3,29),(7,33),(7,45),(3,49),(0,45)],
        "f": [(0,12),(3,8),(7,12),(7,24),(3,28),(0,24)],
        "g": [(7,25),(26,25),(30,28),(26,31),(7,31),(3,28)],
    }
    active = {"0":"abcdef","1":"bc","2":"abdeg","3":"abcdg","4":"bcfg",
              "5":"acdfg","6":"acdefg","7":"abc","8":"abcdefg","9":"abcdfg",
              "f":"aefg","-":"g"}
    for index, character in enumerate("0123456789./fs- "):
        def points(vertices):
            return [((index*cell_w+x)*scale,y*scale) for x,y in vertices]
        if character in active:
            for segment in active[character]:
                painter.polygon(points(segments[segment]), fill=(34, 52, 39, 255))
        elif character == ".":
            painter.ellipse(((index*cell_w+3)*scale,47*scale,(index*cell_w+9)*scale,53*scale), fill=(34,52,39,255))
        elif character == "/":
            painter.polygon(points([(1,50),(6,53),(22,7),(17,4)]), fill=(34,52,39,255))
        elif character == "s":
            painter.line(points([(20,28),(7,28),(4,31),(4,37),(18,39),(20,42),(20,49),(17,51),(3,51)]),
                         fill=(34,52,39,255), width=4*scale, joint="curve")
    atlas.resize((16*cell_w,cell_h),Image.Resampling.LANCZOS).save(output / "finder-digits.png", optimize=True)


if __name__ == "__main__":
    build(Path(__file__).resolve().parents[1] / "ue4ss/Mods/VHOLUMEPhotoCamera/Assets/Controls")
