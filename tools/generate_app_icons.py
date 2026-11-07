#!/usr/bin/env python3
"""توليد أيقونات تطبيق RuView Wi-Fi (هوية رادار نيون) لكل كثافات أندرويد.

يتطلّب: pillow  →  pip install pillow
التشغيل: python3 tools/generate_app_icons.py
المخرجات:
  android/app/src/main/res/mipmap-*/ic_launcher.png
  docs/branding/app_icon_512.png
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
BRANDING = ROOT / "docs" / "branding"

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

CYAN = (0, 229, 255)
EMERALD = (0, 245, 160)
BG_TOP = (10, 20, 32)
BG_BOTTOM = (5, 7, 13)

SUPERSAMPLE = 4


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    strip = Image.new("RGB", (1, size))
    for y in range(size):
        strip.putpixel((0, y), mix(top, bottom, y / max(1, size - 1)))
    return strip.resize((size, size), Image.Resampling.BILINEAR)


def radial_glow(size: int, color: tuple[int, int, int], peak_alpha: int) -> Image.Image:
    small = 64
    glow = Image.new("RGBA", (small, small), (0, 0, 0, 0))
    for y in range(small):
        for x in range(small):
            distance = math.hypot(x - small / 2, y - small / 2) / (small / 2)
            alpha = max(0, 1 - distance) ** 2 * peak_alpha
            glow.putpixel((x, y), (*color, round(alpha)))
    return glow.resize((size, size), Image.Resampling.BICUBIC)


def draw_radar(size: int) -> Image.Image:
    """يرسم أيقونة رادار: حلقات ماسحة + نقطة حياة على خلفية داكنة."""
    s = size * SUPERSAMPLE
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # خلفية متدرّجة داخل زوايا دائرية
    background = vertical_gradient(s, BG_TOP, BG_BOTTOM).convert("RGBA")
    canvas.paste(background, (0, 0), rounded_mask(s, int(s * 0.235)))

    # هالتان نيون
    cyan_glow = radial_glow(int(s * 0.95), CYAN, 70)
    canvas.alpha_composite(cyan_glow, (int(s * 0.22), int(-s * 0.30)))
    emerald_glow = radial_glow(int(s * 0.75), EMERALD, 45)
    canvas.alpha_composite(emerald_glow, (int(-s * 0.25), int(s * 0.45)))

    draw = ImageDraw.Draw(canvas)
    center = (s / 2, s / 2)
    max_radius = s * 0.34

    # حلقات رادار
    for index in range(4):
        radius = max_radius * (0.35 + index * 0.22)
        draw.ellipse(
            (
                center[0] - radius,
                center[1] - radius,
                center[0] + radius,
                center[1] + radius,
            ),
            outline=mix(CYAN, EMERALD, index / 3) + (80,),
            width=max(1, int(s * 0.006)),
        )

    # أقواس المسح
    for index in range(3):
        radius = max_radius * (0.45 + index * 0.2)
        draw.arc(
            (
                center[0] - radius,
                center[1] - radius,
                center[0] + radius,
                center[1] + radius,
            ),
            start=-62,
            end=18,
            fill=mix(CYAN, EMERALD, index / 2) + (240,),
            width=max(2, int(s * 0.016)),
        )

    # شعاع المسح
    angle = math.radians(-18)
    draw.line(
        (center[0], center[1], center[0] + math.cos(angle) * max_radius, center[1] + math.sin(angle) * max_radius),
        fill=CYAN + (170,),
        width=max(2, int(s * 0.012)),
    )

    # نقطة الحياة
    blip_radius = max_radius * 0.6
    blip = (
        center[0] + math.cos(math.radians(-34)) * blip_radius,
        center[1] + math.sin(math.radians(-34)) * blip_radius,
    )
    dot = max(3, int(s * 0.022))
    draw.ellipse(
        (blip[0] - dot * 2.2, blip[1] - dot * 2.2, blip[0] + dot * 2.2, blip[1] + dot * 2.2),
        fill=EMERALD + (70,),
    )
    draw.ellipse((blip[0] - dot, blip[1] - dot, blip[0] + dot, blip[1] + dot), fill=EMERALD + (255,))

    # مركز الهوائي
    core = max(4, int(s * 0.026))
    draw.ellipse(
        (center[0] - core * 2.4, center[1] - core * 2.4, center[0] + core * 2.4, center[1] + core * 2.4),
        fill=CYAN + (55,),
    )
    draw.ellipse((center[0] - core, center[1] - core, center[0] + core, center[1] + core), fill=CYAN + (255,))

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    for folder, size in SIZES.items():
        target = RES / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        draw_radar(size).save(target, optimize=True)
        print(f"✔ {target.relative_to(ROOT)}  ({size}px)")

    BRANDING.mkdir(parents=True, exist_ok=True)
    master = BRANDING / "app_icon_512.png"
    draw_radar(512).save(master, optimize=True)
    print(f"✔ {master.relative_to(ROOT)}  (512px)")


if __name__ == "__main__":
    main()
