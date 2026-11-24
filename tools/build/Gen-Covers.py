"""生成 Moonlight 分辨率卡片封面（600x800 PNG）。

为什么用脚本画而不是配图：
  - 分辨率数字必须准确，AI 生成图经常写错；
  - 每张卡的屏幕比例要能一眼区分（16:9 / 16:10 / 4:3 / 手机宽屏）；
  - 统一风格，改一处即可全部重生成。

用法：
  python tools/build/Gen-Covers.py
输出：
  payload/covers/res-<宽>x<高>.png
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 600, 800
BG = "#0F1218"
PANEL = "#161B24"
TEXT = "#F8FAFC"
MUTED = "#94A3B8"

FONT_RES = r"C:\Windows\Fonts\consola.ttf"
FONT_CN = r"C:\Windows\Fonts\msyh.ttc"

OUT = Path(__file__).resolve().parents[2] / "payload" / "covers"

# 顺序即 Moonlight 里的展示顺序：iOS → 安卓 → Switch → 电视 → 通用。
# OPPO 实测可用的串流档位是 2354x1080（不是其屏幕原生 2772x1272）。
CARDS = [
    ("iPhone 17 Pro Max", 2868, 1320, 60, "#60A5FA"),
    ("iPad Pro 12.9", 2732, 2048, 120, "#A78BFA"),
    ("Find X9 Pro", 2354, 1080, 120, "#2DD4BF"),
    ("Switch 底座", 1920, 1080, 60, "#F87171"),
    ("电视 4K", 3840, 2160, 60, "#FBBF24"),
    ("通用", 2560, 1440, 60, "#34D399"),
]


MARGIN = 44


def centered(draw, text, font, y, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((W - (right - left)) / 2 - left, y - top), text, font=font, fill=fill)


def fit(draw, text, path, size, max_w, min_size=24):
    while size > min_size:
        font = ImageFont.truetype(path, size)
        left, _, right, _ = draw.textbbox((0, 0), text, font=font)
        if right - left <= max_w:
            return font
        size -= 2
    return ImageFont.truetype(path, min_size)


def make(device, width, height, fps, accent):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    draw.rectangle([0, 0, W, 10], fill=accent)

    f_dev = fit(draw, device, FONT_CN, 52, W - MARGIN * 2)
    f_res = fit(draw, f"{width}×{height}", FONT_RES, 96, W - MARGIN * 2)
    f_fps = ImageFont.truetype(FONT_RES, 54)

    centered(draw, device, f_dev, 200, MUTED)
    centered(draw, f"{width}×{height}", f_res, 400, TEXT)

    label = f"{fps} Hz"
    left, top, right, bottom = draw.textbbox((0, 0), label, font=f_fps)
    draw.text(((W - (right - left)) / 2 - left, 560 - top), label, font=f_fps, fill=accent)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"res-{width}x{height}.png"
    img.save(path, "PNG", optimize=True)
    return path


if __name__ == "__main__":
    for device, w, h, fps, color in CARDS:
        p = make(device, w, h, fps, color)
        print(f"{p.name}  {p.stat().st_size // 1024} KB")
