"""Synthesize VHOLUME camera cues as stereo AAC in MP4."""

from argparse import ArgumentParser
from array import array
from io import BytesIO
from math import exp, pi, sin
from pathlib import Path
from random import Random
import subprocess
import sys
import wave


RATE = 48000
# Resonance frequency, amplitude, and decay time for each part of the camera.
BODY = ((190, .28, .017), (421, .34, .013), (967, .38, .009), (2417, .23, .005))
STEEL = ((708, .17, .008), (1663, .29, .006), (2981, .35, .004), (5189, .23, .0027))
DETENT = ((378, .17, .007), (1139, .29, .006), (2651, .31, .0037), (4231, .19, .0028))
MIRROR = ((222, .31, .016), (579, .36, .010), (1369, .31, .007), (3091, .26, .004))


def write_mp4(path, pcm):
    if sys.byteorder == "big":
        pcm.byteswap()
    source = BytesIO()
    with wave.open(source, "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(pcm.tobytes())
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-f", "wav", "-i", "pipe:0", "-ac", "2", "-c:a", "aac",
         "-b:a", "128k", "-movflags", "+faststart", str(path)],
        input=source.getvalue(),
        check=True,
    )


class Cue:
    def __init__(self, seconds, seed):
        self.samples = [0.0] * round(seconds * RATE)
        self.random = Random(seed)

    def layer(self, at, seconds, sample, attack=.0003):
        start = round(at * RATE)
        count = min(round(seconds * RATE), len(self.samples) - start)
        for index in range(count):
            t = index / RATE
            edge = min(1, t / attack, (count - index - 1) / 96)
            self.samples[start + index] += sample(t) * edge

    def strike(self, at, level, resonances, pitch=1, damping=1):
        modes = [(2 * pi * hz * pitch, gain, decay * damping) for hz, gain, decay in resonances]
        low = bright = 0.0

        def sample(t):
            nonlocal low, bright
            noise = self.random.uniform(-1, 1)
            low += .09 * (noise - low)
            bright += .67 * (noise - bright)
            contact = (bright - low) * exp(-t / (.0028 * damping))
            ring = sum(gain * sin(phase * t) * exp(-t / decay) for phase, gain, decay in modes)
            return level * (.75 * contact + ring)

        self.layer(at, .09, sample)

    def slide(self, at, seconds, level, roughness):
        low = fast = 0.0

        def sample(t):
            nonlocal low, fast
            noise = self.random.uniform(-1, 1)
            low += .018 * (noise - low)
            fast += roughness * (noise - fast)
            envelope = sin(pi * t / seconds) ** 1.6
            return level * envelope * (fast - low)

        self.layer(at, seconds, sample, attack=.003)

    def write(self, path, peak_level=None):
        peak = max(abs(sample) for sample in self.samples)
        gain = min(1, .80 / peak) if peak_level is None else peak_level / peak
        pcm = array("h", (round(sample * gain * 32767) for sample in self.samples))
        write_mp4(path, pcm)


def build(output):
    output.mkdir(parents=True, exist_ok=True)

    cue = Cue(.235, 121)
    cue.slide(.004, .149, .27, .14)
    cue.strike(.057, .16, DETENT, .84)
    cue.strike(.128, .39, BODY, .82)
    cue.strike(.154, .14, STEEL, .96, .7)
    cue.write(output / "equip.mp4")

    cue = Cue(.225, 122)
    cue.strike(.009, .23, DETENT, .84)
    cue.slide(.017, .123, .30, .12)
    cue.strike(.123, .32, BODY, .74, .90)
    cue.write(output / "stow.mp4")

    cue = Cue(.195, 123)
    cue.slide(.004, .104, .20, .16)
    cue.strike(.065, .13, DETENT, 1.05, .75)
    cue.strike(.089, .32, BODY, 1.03, .75)
    cue.write(output / "raise.mp4")

    cue = Cue(.187, 124)
    cue.strike(.008, .24, BODY, .88, .82)
    cue.slide(.021, .108, .19, .14)
    cue.strike(.115, .22, DETENT, .78, .71)
    cue.write(output / "lower.mp4")

    cue = Cue(.235, 125)
    cue.strike(.005, .28, DETENT, .98)
    cue.slide(.019, .108, .34, .26)
    cue.strike(.047, .15, STEEL, .74, .63)
    cue.strike(.090, .19, STEEL, .79, .70)
    cue.strike(.132, .42, BODY, .97)
    cue.strike(.139, .27, DETENT, 1.15)
    cue.write(output / "lens.mp4")

    # The mod's autofocus borrows the sounds of a lens ring and its stop.
    cue = Cue(.192, 126)
    cue.slide(.009, .090, .26, .25)
    cue.strike(.066, .12, DETENT, .83, .65)
    cue.strike(.106, .36, DETENT, 1.23, .79)
    cue.strike(.115, .13, BODY, 1.06, .65)
    cue.write(output / "af_lock.mp4")

    cue = Cue(.172, 127)
    cue.slide(.006, .070, .24, .21)
    cue.strike(.061, .15, DETENT, .75, .73)
    cue.slide(.071, .050, .12, .19)
    cue.strike(.106, .18, BODY, .80, .63)
    cue.write(output / "af_miss.mp4")

    # Mirror lift, curtain travel, and the heavier mirror return.
    cue = Cue(.162, 228)
    cue.strike(.004, .48, MIRROR, 1.05, .70)
    cue.slide(.011, .037, .22, .57)
    cue.strike(.019, .39, STEEL, .87, .70)
    cue.strike(.029, .29, STEEL, 1.11, .56)
    cue.strike(.047, .67, MIRROR, .92, .90)
    cue.strike(.049, .41, STEEL, .93, .76)
    cue.strike(.061, .13, DETENT, .86, .70)
    cue.write(output / "shutter.mp4", peak_level=.69)

    # The film-advance lever engages successive teeth, hits the stop and springs back.
    cue = Cue(.362, 229)
    cue.slide(.003, .232, .20, .18)
    for at, level, pitch in (
        (.020, .15, .91), (.056, .19, .97), (.087, .17, 1.03),
        (.114, .23, .96), (.138, .20, 1.08), (.160, .22, 1.02),
        (.184, .18, 1.12), (.210, .15, .99),
    ):
        cue.strike(at, level, DETENT, pitch, .58)
    cue.strike(.243, .34, BODY, 1.04, .72)
    cue.strike(.246, .26, STEEL, .94, .62)
    cue.slide(.256, .074, .16, .24)
    cue.strike(.322, .19, DETENT, .87, .72)
    cue.write(output / "saved.mp4", peak_level=.45)

    cue = Cue(.120, 130)
    cue.slide(.004, .046, .12, .22)
    cue.strike(.021, .32, DETENT, 1.25, .73)
    cue.strike(.029, .13, STEEL, 1.13, .58)
    cue.write(output / "aperture.mp4")

    cue = Cue(.112, 131)
    cue.slide(.004, .067, .28, .22)
    cue.strike(.035, .17, DETENT, .76, .63)
    cue.write(output / "focus.mp4")

    cue = Cue(.171, 132)
    cue.slide(.005, .093, .19, .14)
    cue.strike(.044, .24, BODY, .91, .78)
    cue.strike(.100, .19, DETENT, .92, .79)
    cue.write(output / "frame.mp4")

    cue = Cue(.147, 133)
    cue.strike(.010, .26, BODY, .75, .85)
    cue.slide(.022, .068, .19, .15)
    cue.strike(.069, .17, DETENT, .78, .68)
    cue.write(output / "walk.mp4")

    cue = Cue(.153, 134)
    cue.strike(.007, .24, DETENT, 1.14, .72)
    cue.slide(.014, .058, .20, .25)
    cue.strike(.057, .27, STEEL, 1.02, .78)
    cue.write(output / "dof.mp4")

    cue = Cue(.143, 135)
    cue.slide(.009, .047, .15, .19)
    cue.strike(.016, .17, DETENT, 1.14, .68)
    cue.strike(.054, .29, DETENT, .96, .79)
    cue.write(output / "mode.mp4")


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.output)
