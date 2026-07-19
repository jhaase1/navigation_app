"""Generates the app icon assets used by flutter_launcher_icons.

Not part of the Flutter build - a one-off design script. Re-run and commit
the resulting PNGs if the icon design changes.
"""

from PIL import Image, ImageDraw

FINAL = 1024
SS = 4
SIZE = FINAL * SS

TOP = (66, 165, 245)     # #42A5F5
BOTTOM = (13, 71, 161)   # #0D47A1
WHITE = (255, 255, 255, 255)


def lerp_color(t):
    r = int(TOP[0] + (BOTTOM[0] - TOP[0]) * t)
    g = int(TOP[1] + (BOTTOM[1] - TOP[1]) * t)
    b = int(TOP[2] + (BOTTOM[2] - TOP[2]) * t)
    return (r, g, b)


def gradient_square(size):
    grad = Image.new("RGB", (size, size), 0)
    gdraw = ImageDraw.Draw(grad)
    for y in range(size):
        gdraw.line([(0, y), (size, y)], fill=lerp_color(y / (size - 1)))
    return grad


def draw_camera_glyph(draw, img, cx, cy, scale):
    """Draws the camcorder glyph centered at (cx, cy); scale=1 matches the
    proportions used in the full-bleed icon."""
    s = scale * SS

    body_w, body_h = 380 * s, 300 * s
    body_left = cx - 260 * s
    body_top = cy - body_h / 2
    body_right = body_left + body_w
    body_bottom = body_top + body_h
    draw.rounded_rectangle(
        [body_left, body_top, body_right, body_bottom], radius=48 * s, fill=WHITE
    )

    lens_r = 60 * s
    lens_cx = body_left + 110 * s
    lens_cy = body_top
    draw.ellipse(
        [lens_cx - lens_r, lens_cy - lens_r * 0.6,
         lens_cx + lens_r, lens_cy + lens_r * 0.9],
        fill=WHITE,
    )

    trap_left_x = body_right - 4 * s
    trap_top_y = cy - 95 * s
    trap_bottom_y = cy + 95 * s
    trap_tip_x = body_right + 210 * s
    trap_tip_top_y = cy - 165 * s
    trap_tip_bottom_y = cy + 165 * s
    draw.polygon(
        [
            (trap_left_x, trap_top_y),
            (trap_left_x, trap_bottom_y),
            (trap_tip_x, trap_tip_bottom_y),
            (trap_tip_x, trap_tip_top_y),
        ],
        fill=WHITE,
    )

    lens_hole_r = 78 * s
    hole_cx, hole_cy = body_left + body_w * 0.62, cy

    ring_r = 52 * s
    dot_r = 16 * s
    return hole_cx, hole_cy, lens_hole_r, ring_r, dot_r


def make_full_icon(rounded: bool):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    grad = gradient_square(SIZE)

    if rounded:
        mask = Image.new("L", (SIZE, SIZE), 0)
        inset = 24 * SS
        radius = 220 * SS
        ImageDraw.Draw(mask).rounded_rectangle(
            [inset, inset, SIZE - inset, SIZE - inset], radius=radius, fill=255
        )
        bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        bg.paste(grad, (0, 0), mask)
        img = Image.alpha_composite(img, bg)
    else:
        img.paste(grad, (0, 0))
        img.putalpha(255)

    draw = ImageDraw.Draw(img)
    cx, cy = SIZE / 2, SIZE / 2
    hole_cx, hole_cy, lens_hole_r, ring_r, dot_r = draw_camera_glyph(
        draw, img, cx, cy, scale=1.0
    )

    hole_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(hole_mask).ellipse(
        [hole_cx - lens_hole_r, hole_cy - lens_hole_r,
         hole_cx + lens_hole_r, hole_cy + lens_hole_r],
        fill=255,
    )
    blue = lerp_color(hole_cy / (SIZE - 1))
    blue_dot = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    blue_dot.paste((*blue, 255), (0, 0), hole_mask)
    img = Image.alpha_composite(img, blue_dot)
    draw = ImageDraw.Draw(img)

    draw.ellipse(
        [hole_cx - ring_r, hole_cy - ring_r, hole_cx + ring_r, hole_cy + ring_r],
        outline=WHITE, width=14 * SS,
    )
    draw.ellipse(
        [hole_cx - dot_r, hole_cy - dot_r, hole_cx + dot_r, hole_cy + dot_r],
        fill=WHITE,
    )

    return img.resize((FINAL, FINAL), Image.LANCZOS)


def make_foreground():
    """Transparent-background glyph only, inset for Android's adaptive-icon
    safe zone (content should sit within the center ~66% of the canvas)."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = SIZE / 2, SIZE / 2
    scale = 0.62
    hole_cx, hole_cy, lens_hole_r, ring_r, dot_r = draw_camera_glyph(
        draw, img, cx, cy, scale=scale
    )

    blue = (13, 71, 161, 255)
    hole_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(hole_mask).ellipse(
        [hole_cx - lens_hole_r, hole_cy - lens_hole_r,
         hole_cx + lens_hole_r, hole_cy + lens_hole_r],
        fill=255,
    )
    hole_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hole_layer.paste(blue, (0, 0), hole_mask)
    img = Image.alpha_composite(img, hole_layer)
    draw = ImageDraw.Draw(img)

    draw.ellipse(
        [hole_cx - ring_r, hole_cy - ring_r, hole_cx + ring_r, hole_cy + ring_r],
        outline=WHITE, width=int(14 * SS * scale),
    )
    draw.ellipse(
        [hole_cx - dot_r, hole_cy - dot_r, hole_cx + dot_r, hole_cy + dot_r],
        fill=WHITE,
    )

    return img.resize((FINAL, FINAL), Image.LANCZOS)


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))

    make_full_icon(rounded=False).save(os.path.join(here, "icon.png"))
    make_full_icon(rounded=True).save(os.path.join(here, "icon_rounded_preview.png"))
    make_foreground().save(os.path.join(here, "icon_foreground.png"))
    print("done")
