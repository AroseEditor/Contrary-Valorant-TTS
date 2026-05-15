"""
generate_icon.py
Generates icon.ico (multi-size) and icon_256.png for Contrary Valorant TTS.
Requires: pip install pillow
"""

from PIL import Image, ImageDraw
import math, os

BG      = (0x0f, 0x0e, 0x17, 255)
RED     = (0xff, 0x46, 0x55, 255)
WHITE   = (0xff, 0xff, 0xff, 255)
RED_SEP = (0xff, 0x46, 0x55, 180)

SIZES = [256, 128, 64, 48, 32, 16]


def draw_icon(size: int) -> Image.Image:
    img  = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s    = size

    # ── Background ──────────────────────────────────────────────────────────
    draw.rectangle([0, 0, s - 1, s - 1], fill=BG)

    # ── Chevron (Valorant-style, pointing right) ─────────────────────────────
    # Occupies top 58% of canvas, centered horizontally
    chevron_top    = int(s * 0.08)
    chevron_bottom = int(s * 0.58)
    cx             = s / 2
    ch             = chevron_bottom - chevron_top
    half_w         = s * 0.38
    tip_x          = cx + half_w * 0.55   # tip of the V pointing right
    thickness      = ch * 0.36            # arm thickness

    # Upper arm of chevron
    upper = [
        (cx - half_w,         chevron_top),
        (tip_x,               chevron_top + ch * 0.5),
        (tip_x - thickness,   chevron_top + ch * 0.5),
        (cx - half_w + thickness * 0.82, chevron_top + thickness * 0.88),
    ]
    # Lower arm of chevron
    lower = [
        (cx - half_w,         chevron_bottom),
        (tip_x,               chevron_top + ch * 0.5),
        (tip_x - thickness,   chevron_top + ch * 0.5),
        (cx - half_w + thickness * 0.82, chevron_bottom - thickness * 0.88),
    ]

    draw.polygon(upper, fill=RED)
    draw.polygon(lower, fill=RED)

    # ── Highlight slash across chevron ───────────────────────────────────────
    if size >= 32:
        lw      = max(1, int(s * 0.018))
        slash_x1 = int(cx - half_w * 0.05)
        slash_y1 = int(chevron_top + ch * 0.18)
        slash_x2 = int(tip_x - thickness * 0.6)
        slash_y2 = int(chevron_top + ch * 0.42)
        draw.line([(slash_x1, slash_y1), (slash_x2, slash_y2)],
                  fill=(255, 255, 255, 120), width=lw)

    # ── Separator line ────────────────────────────────────────────────────────
    sep_y  = int(s * 0.62)
    sep_hw = int(s * 0.20)
    if size >= 32:
        draw.line([(int(cx) - sep_hw, sep_y), (int(cx) + sep_hw, sep_y)],
                  fill=RED_SEP, width=max(1, int(s * 0.008)))

    # ── Microphone ────────────────────────────────────────────────────────────
    mic_top    = int(s * 0.65)
    mic_bottom = int(s * 0.83)
    mic_mh     = mic_bottom - mic_top
    mic_w      = int(s * 0.18)
    mic_cx     = int(cx)
    mic_rx     = mic_cx - mic_w // 2
    mic_ry     = mic_top
    radius     = max(2, int(mic_w * 0.45))

    # Body: rounded rectangle
    if size >= 32:
        draw.rounded_rectangle(
            [mic_rx, mic_ry, mic_rx + mic_w, mic_bottom],
            radius=radius, fill=WHITE
        )
    else:
        draw.rectangle([mic_rx, mic_ry, mic_rx + mic_w, mic_bottom], fill=WHITE)

    # Arc (mic stand curve)
    arc_margin = int(s * 0.10)
    arc_top    = int(s * 0.77)
    arc_bottom = int(s * 0.88)
    lw_arc     = max(1, int(s * 0.025))
    if size >= 32:
        draw.arc(
            [mic_cx - arc_margin, arc_top, mic_cx + arc_margin, arc_bottom],
            start=0, end=180, fill=WHITE, width=lw_arc
        )
        # Vertical stand
        stand_x = mic_cx
        draw.line([(stand_x, arc_bottom - lw_arc), (stand_x, int(s * 0.92))],
                  fill=WHITE, width=lw_arc)
        # Foot line
        foot_hw = int(s * 0.07)
        draw.line([(stand_x - foot_hw, int(s * 0.92)),
                   (stand_x + foot_hw, int(s * 0.92))],
                  fill=WHITE, width=lw_arc)

    return img


def main():
    images = []
    base   = draw_icon(256)

    # Save 256 PNG for README
    base.save("icon_256.png", "PNG")
    print("[OK] icon_256.png saved")

    # Build multi-size ICO
    for sz in SIZES:
        if sz == 256:
            images.append(base.copy())
        else:
            images.append(base.resize((sz, sz), Image.LANCZOS))

    images[0].save(
        "icon.ico",
        format="ICO",
        sizes=[(s, s) for s in SIZES],
        append_images=images[1:]
    )
    print("[OK] icon.ico saved with sizes:", SIZES)


if __name__ == "__main__":
    main()
