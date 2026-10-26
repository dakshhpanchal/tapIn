"""Builds every tapIn icon asset from the hand-and-ripples art.

The art (tools/icons/source/tapin_hand_ripples.png) is a flat picture with its
rounded corners baked in. This cuts the hand, coral ring and sparks out of it
with a soft mask, redraws the concentric circles, and lays them out the way
Android builds an adaptive icon:

  background layer  navy with the concentric circles
  foreground layer  the hand, ring and sparks, with a soft shadow
  themed layer      the hand, ring and sparks as one flat shape

Everything is sized to sit inside the central 2/3 of the canvas, which is all
that survives the launcher's mask. Run from the repo root (needs ImageMagick):

    python3 tools/icons/make_tapin_icons.py

Writes assets/icon/ (full icon and a flat glyph for the in-app logo) and the
Android launcher icons and system splash icon under android/app/src/main/res.
"""
import os
import subprocess
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
ASSETS = os.path.join(ROOT, "assets", "icon")
SOURCE = os.path.join(ROOT, "tools", "icons", "source", "tapin_hand_ripples.png")

NAVY = "#0D1946"  # the picture's flat background, sampled
# The hand, ring and sparks in the 1264px picture: x, y, width, height.
CROP = (400, 340, 490, 730)
# Their middle in the picture, which lands on the middle of the canvas.
CONTENT_CENTRE = (642, 707)
# Picture pixels -> canvas pixels: the 1024/1264 fit, kept a little under 1 so
# the hand's bottom stays inside the launcher mask.
FACTOR = (1024 / 1264) * 0.94
# The ripples' centre in the picture (the middle of the coral ring), and their
# radii in picture pixels.
RIPPLE_CENTRE = (632, 562)
RIPPLE_RADII = (372, 288, 201)


def run(*cmd):
    subprocess.run(cmd, check=True, capture_output=True)


def to_canvas(px, py):
    """A point in the picture -> where it lands on the 1024 canvas."""
    return (
        512 + (px - CONTENT_CENTRE[0]) * FACTOR,
        512 + (py - CONTENT_CENTRE[1]) * FACTOR,
    )


def drop_shadow(src, out, blur, dy, opacity):
    """A soft black shadow shaped like [src]'s alpha, pushed down by [dy]."""
    run("magick", src, "-alpha", "extract", "-blur", f"0x{blur}", "-roll", f"+0+{dy}",
        "-write", "mpr:a", "+delete", "-size", "1024x1024", "xc:black", "mpr:a",
        "-compose", "CopyOpacity", "-composite", "-channel", "A",
        "-evaluate", "multiply", str(opacity), "+channel", out)


def build_layers(tmp):
    """-> (background, foreground, art) PNG paths, all 1024px.

    [art] is the hand, ring and sparks alone, for the flat themed shape."""
    x, y, w, h = CROP
    sw, sh = round(w * FACTOR), round(h * FACTOR)
    crop = f"{w}x{h}+{x}+{y}"
    rgb = os.path.join(tmp, "art_rgb.png")
    run("magick", SOURCE, "-crop", crop, "+repage", "-resize", f"{sw}x{sh}!", rgb)
    # Brightness separates the hand, ring and sparks from the dark navy and the
    # faint ripples; the soft ramp keeps their edges smooth.
    mask = os.path.join(tmp, "mask.png")
    run("magick", SOURCE, "-crop", crop, "+repage", "-colorspace", "Gray",
        "-level", "30%,48%", "-resize", f"{sw}x{sh}!", mask)
    cut = os.path.join(tmp, "cut.png")
    run("magick", rgb, mask, "-alpha", "off", "-compose", "CopyOpacity", "-composite", cut)

    left, top = to_canvas(x, y)
    art = os.path.join(tmp, "art.png")
    run("magick", "-size", "1024x1024", "xc:none", cut, "-geometry",
        f"+{round(left)}+{round(top)}", "-composite", art)
    shadow = os.path.join(tmp, "shadow.png")
    drop_shadow(art, shadow, 12, 12, 0.42)
    fg = os.path.join(tmp, "fg.png")
    # Start from a colour canvas: composited onto the grey shadow image first,
    # ImageMagick would turn the whole layer grey.
    run("magick", "-size", "1024x1024", "xc:none", shadow, "-composite", art,
        "-composite", "-type", "TrueColorAlpha", fg)

    # Concentric circles: soft discs around the ring, brightest in the middle.
    cx, cy = to_canvas(*RIPPLE_CENTRE)
    bg_cmd = ["magick", "-size", "1024x1024", f"xc:{NAVY}"]
    for r in RIPPLE_RADII:
        r = r * FACTOR
        bg_cmd += ["-fill", "rgba(124,134,255,0.055)", "-draw",
                   f"circle {cx:.1f},{cy:.1f} {cx + r:.1f},{cy:.1f}"]
    bg = os.path.join(tmp, "bg.png")
    run(*bg_cmd, bg)
    return bg, fg, art


def flat_shape(art, out, colour="white"):
    """The art's outline as one flat colour, for themed icons and the in-app logo."""
    run("magick", art, "-alpha", "extract", "-write", "mpr:a", "+delete",
        "-size", "1024x1024", f"xc:{colour}", "mpr:a", "-compose", "CopyOpacity",
        "-composite", out)


def rounded(icon, out, size):
    with tempfile.TemporaryDirectory() as tmp:
        mask = os.path.join(tmp, "mask.png")
        run("magick", "-size", "1024x1024", "xc:none", "-fill", "white",
            "-draw", "roundrectangle 0,0 1023,1023 230,230", mask)
        run("magick", icon, mask, "-alpha", "off", "-compose", "CopyOpacity",
            "-composite", "-resize", f"{size}x{size}", out)


def resized(src, out, size):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    run("magick", src, "-resize", f"{size}x{size}", out)


DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def main():
    with tempfile.TemporaryDirectory() as tmp:
        bg, fg, art = build_layers(tmp)
        icon = os.path.join(tmp, "icon.png")
        run("magick", bg, fg, "-composite", icon)
        mono = os.path.join(tmp, "mono.png")
        flat_shape(art, mono)

        resized(icon, os.path.join(ASSETS, "tapin_launcher_1024.png"), 1024)
        # The in-app logo: the flat shape, trimmed, tinted by the theme at runtime.
        run("magick", mono, "-trim", "+repage", "-bordercolor", "none", "-border", "8",
            "-resize", "256x256", os.path.join(ASSETS, "tapin_glyph.png"))
        for d, scale in DENSITIES.items():
            resized(fg, f"{RES}/drawable-{d}/ic_launcher_foreground.png", round(108 * scale))
            resized(mono, f"{RES}/drawable-{d}/ic_launcher_monochrome.png", round(108 * scale))
            resized(bg, f"{RES}/drawable-{d}/ic_launcher_background.png", round(108 * scale))
            os.makedirs(f"{RES}/mipmap-{d}", exist_ok=True)
            rounded(icon, f"{RES}/mipmap-{d}/ic_launcher.png", round(48 * scale))
            # Android 12+ splash icon: a 288dp canvas whose middle 192dp circle
            # is what shows, exactly the area this composition is designed for.
            resized(icon, f"{RES}/drawable-{d}/splash_tapin.png", round(288 * scale))
    print("done")


if __name__ == "__main__":
    main()
