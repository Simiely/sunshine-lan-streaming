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

CARDS = [
    ("Find X9 Pro", 2772, 1272, 60, "#2DD4BF"),
    ("iPhone 17 Pro Max", 2868, 1320, 60, "#60A5FA"),
    ("iPad Pro 12.9", 2732, 2048, 120, "#A78BFA"),
    ("Switch 底座", 1920, 1080, 60, "#F87171"),
    ("电视 4K", 3840, 2160, 60, "#FBBF24"),
    ("通用", 1280, 720, 60, "#94A3B8"),
    ("通用", 2560, 1440, 60, "#34D399"),
    ("通用", 1440, 900, 60, "#F472B6"),
]


def centered(draw, text, font, y, fill):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(((W - (right - left)) / 2 - left, y - top), text, font=font, fill=fill)


def make(device, width, height, fps, accent):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)

    draw.rectangle([0, 0, W, 10], fill=accent)

    max_w, max_h = 440, 290
    ratio = width / height
    sw = max_w
    sh = int(sw / ratio)
    if sh > max_h:
        sh = max_h
        sw = int(sh * ratio)
    x0 = (W - sw) // 2
    y0 = 300 - sh // 2
    draw.rounded_rectangle([x0, y0, x0 + sw, y0 + sh], radius=12, outline=accent, width=4)
    draw.rounded_rectangle([x0 + 10, y0 + 10, x0 + sw - 10, y0 + sh - 10], radius=8, fill=PANEL)

    f_res = ImageFont.truetype(FONT_RES, 68)
    f_dev = ImageFont.truetype(FONT_CN, 30)
    f_fps = ImageFont.truetype(FONT_RES, 26)

    centered(draw, f"{width}×{height}", f_res, 500, TEXT)
    centered(draw, device, f_dev, 610, MUTED)

    badge = f"{fps} Hz"
    left, top, right, bottom = draw.textbbox((0, 0), badge, font=f_fps)
    bw, bh = right - left, bottom - top
    bx, by = (W - bw) / 2, 686
    draw.rounded_rectangle([bx - 18, by - 8, bx + bw + 18, by + bh + 8], radius=16, fill=PANEL)
    draw.text((bx - left, by - top), badge, font=f_fps, fill=accent)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"res-{width}x{height}.png"
    img.save(path, "PNG", optimize=True)
    return path


if __name__ == "__main__":
    for device, w, h, fps, color in CARDS:
        p = make(device, w, h, fps, color)
        print(f"{p.name}  {p.stat().st_size // 1024} KB")
