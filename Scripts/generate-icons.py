#!/usr/bin/env python3
"""Build AppIcon + MenuIcon assets from Design/*.svg (via pre-rasterized PNG or qlmanage)."""

from __future__ import annotations

import json
import math
import struct
import subprocess
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "Design"
APP_ASSETS = ROOT / "Apps/RightKit/Resources/Assets.xcassets"
APP_ICON = APP_ASSETS / "AppIcon.appiconset"
STATUS_ITEM = APP_ASSETS / "StatusItem.imageset"
EXT_ASSETS = ROOT / "Extensions/RightKitFinderSync/Resources/Assets.xcassets"
MENU_ICON = EXT_ASSETS / "MenuIcon.imageset"
EXT_APP_ICON = EXT_ASSETS / "AppIcon.appiconset"


def clamp(v: float) -> int:
    return max(0, min(255, int(round(v))))


def write_png(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\x00" + row for row in rows)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def read_png(path: Path) -> tuple[int, int, list[list[tuple[int, int, int, int]]]]:
    """Minimal PNG reader (8-bit RGBA only)."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    width = height = None
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        tag = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, bit, color, comp, filt, inter = struct.unpack(">IIBBBBB", chunk)
            assert bit == 8 and color == 6 and inter == 0, "need 8-bit RGBA non-interlaced PNG"
        elif tag == b"IDAT":
            idat += chunk
        elif tag == b"IEND":
            break
    assert width and height
    raw = zlib.decompress(idat)
    rows_out: list[list[tuple[int, int, int, int]]] = []
    stride = width * 4
    i = 0
    prev = bytearray(stride)
    for _y in range(height):
        ftype = raw[i]
        i += 1
        scan = bytearray(raw[i : i + stride])
        i += stride
        if ftype == 1:  # Sub
            for x in range(stride):
                left = scan[x - 4] if x >= 4 else 0
                scan[x] = (scan[x] + left) & 0xFF
        elif ftype == 2:  # Up
            for x in range(stride):
                scan[x] = (scan[x] + prev[x]) & 0xFF
        elif ftype == 3:  # Average
            for x in range(stride):
                left = scan[x - 4] if x >= 4 else 0
                scan[x] = (scan[x] + ((left + prev[x]) // 2)) & 0xFF
        elif ftype == 4:  # Paeth
            for x in range(stride):
                a = scan[x - 4] if x >= 4 else 0
                b = prev[x]
                c = prev[x - 4] if x >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                scan[x] = (scan[x] + pr) & 0xFF
        elif ftype != 0:
            raise ValueError(f"unsupported filter {ftype}")
        prev = scan
        row = []
        for x in range(width):
            o = x * 4
            row.append((scan[o], scan[o + 1], scan[o + 2], scan[o + 3]))
        rows_out.append(row)
    return width, height, rows_out


def resize_rgba(
    src: list[list[tuple[int, int, int, int]]], out_w: int, out_h: int
) -> list[list[tuple[int, int, int, int]]]:
    """Box-filter downscale / nearest-ish upscale."""
    in_h = len(src)
    in_w = len(src[0])
    out: list[list[tuple[int, int, int, int]]] = []
    for y in range(out_h):
        sy0 = y * in_h / out_h
        sy1 = (y + 1) * in_h / out_h
        y0, y1 = int(sy0), min(in_h, max(int(math.ceil(sy1)), int(sy0) + 1))
        row = []
        for x in range(out_w):
            sx0 = x * in_w / out_w
            sx1 = (x + 1) * in_w / out_w
            x0, x1 = int(sx0), min(in_w, max(int(math.ceil(sx1)), int(sx0) + 1))
            r = g = b = a = wsum = 0.0
            for yy in range(y0, y1):
                yw = min(sy1, yy + 1) - max(sy0, yy)
                for xx in range(x0, x1):
                    xw = min(sx1, xx + 1) - max(sx0, xx)
                    w = xw * yw
                    pr, pg, pb, pa = src[yy][xx]
                    r += pr * w
                    g += pg * w
                    b += pb * w
                    a += pa * w
                    wsum += w
            if wsum <= 0:
                row.append((0, 0, 0, 0))
            else:
                row.append(
                    (
                        clamp(r / wsum),
                        clamp(g / wsum),
                        clamp(b / wsum),
                        clamp(a / wsum),
                    )
                )
        out.append(row)
    return out


import math  # after annotations for resize


def pixels_to_rows(pixels: list[list[tuple[int, int, int, int]]]) -> list[bytes]:
    rows = []
    for row in pixels:
        buf = bytearray()
        for r, g, b, a in row:
            buf.extend((r, g, b, a))
        rows.append(bytes(buf))
    return rows


def content_bbox(
    src: list[list[tuple[int, int, int, int]]],
    white_threshold: int = 245,
) -> tuple[int, int, int, int]:
    """Return inclusive content bounds of non-white, non-transparent ink."""
    h = len(src)
    w = len(src[0]) if h else 0
    min_x, min_y, max_x, max_y = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[y][x]
            if a < 12:
                continue
            lum = (r + g + b) / 3.0
            if lum >= white_threshold and abs(r - g) < 10 and abs(g - b) < 10:
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    if max_x < 0:
        return 0, 0, max(w - 1, 0), max(h - 1, 0)
    return min_x, min_y, max_x, max_y


def crop_to_content(
    src: list[list[tuple[int, int, int, int]]],
    pad_ratio: float = 0.02,
) -> list[list[tuple[int, int, int, int]]]:
    h = len(src)
    w = len(src[0]) if h else 0
    min_x, min_y, max_x, max_y = content_bbox(src)
    pad = max(1, int(pad_ratio * max(w, h)))
    min_x = max(0, min_x - pad)
    min_y = max(0, min_y - pad)
    max_x = min(w - 1, max_x + pad)
    max_y = min(h - 1, max_y + pad)
    return [row[min_x : max_x + 1] for row in src[min_y : max_y + 1]]


def compose_app_icon(logo: list[list[tuple[int, int, int, int]]], size: int) -> list[bytes]:
    """Centered white plate and logo with the outer padding used by macOS app icons."""
    white = (255, 255, 255)
    # Leave 10% transparent space on every side, including around the white plate.
    plate_size = size * 0.80

    # 1) Knock out white background from raster
    cleaned: list[list[tuple[int, int, int, int]]] = []
    for row in logo:
        nr = []
        for r, g, b, a in row:
            if a < 12:
                nr.append((0, 0, 0, 0))
                continue
            lum = (r + g + b) / 3.0
            if lum >= 245 and abs(r - g) < 10 and abs(g - b) < 10:
                nr.append((0, 0, 0, 0))
            else:
                nr.append((r, g, b, a))
        cleaned.append(nr)

    # 2) Crop to ink bbox so source left/top bias is removed
    cropped = crop_to_content(cleaned, pad_ratio=0.01)

    # 3) Scale the logo with its plate, preserving the original internal proportions.
    target = max(1, int(plate_size * 0.80))
    ch = len(cropped)
    cw = len(cropped[0]) if ch else 1
    # Keep aspect ratio
    scale = min(target / max(cw, 1), target / max(ch, 1))
    tw = max(1, int(round(cw * scale)))
    th = max(1, int(round(ch * scale)))
    logo_r = resize_rgba(cropped, tw, th)

    # Pixel-center with rounding (avoid half-pixel left bias)
    ox = int(round((size - tw) / 2.0))
    oy = int(round((size - th) / 2.0))

    r_app = plate_size * 0.223
    aa = max(plate_size / 128.0, 0.9)
    out: list[list[tuple[int, int, int, int]]] = []

    def sd_round_rect(px, py, cx, cy, hw, hh, r):
        dx = abs(px - cx) - (hw - r)
        dy = abs(py - cy) - (hh - r)
        ox_, oy_ = max(dx, 0.0), max(dy, 0.0)
        return math.hypot(ox_, oy_) + min(max(dx, dy), 0.0) - r

    def cover(sd, aaf=1.0):
        return max(0.0, min(1.0, 0.5 - sd / max(aaf, 1e-6)))

    for y in range(size):
        row = []
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            app_c = cover(
                sd_round_rect(px, py, size / 2, size / 2, plate_size / 2, plate_size / 2, r_app),
                aa,
            )
            if app_c <= 0:
                row.append((0, 0, 0, 0))
                continue

            r, g, b = float(white[0]), float(white[1]), float(white[2])

            lx, ly = x - ox, y - oy
            if 0 <= lx < tw and 0 <= ly < th:
                lr, lg, lb, la = logo_r[ly][lx]
                if la > 8:
                    al = la / 255.0
                    # Preserve original logo colors on white
                    r = r * (1 - al) + lr * al
                    g = g * (1 - al) + lg * al
                    b = b * (1 - al) + lb * al

            row.append((clamp(r), clamp(g), clamp(b), clamp(app_c * 255)))
        out.append(row)
    return pixels_to_rows(out)


def knock_out_light_background(
    src: list[list[tuple[int, int, int, int]]], light_threshold: int = 240
) -> list[list[tuple[int, int, int, int]]]:
    """qlmanage often paints SVG on opaque white — treat near-white as transparent."""
    out = []
    for row in src:
        nr = []
        for r, g, b, a in row:
            if a < 8:
                nr.append((0, 0, 0, 0))
                continue
            lum = (r + g + b) / 3.0
            if lum >= light_threshold and abs(r - g) < 12 and abs(g - b) < 12:
                nr.append((0, 0, 0, 0))
            else:
                nr.append((r, g, b, a))
        out.append(nr)
    return out


def make_template_menu(
    src: list[list[tuple[int, int, int, int]]], size: int, width_scale: float = 0.82
) -> list[bytes]:
    """Monochrome template; optionally compress horizontal scale to look slimmer."""
    cleaned = knock_out_light_background(src)
    # Crop to content bounding box first, then scale to full canvas
    h = len(cleaned)
    w = len(cleaned[0]) if h else 0
    min_x, min_y, max_x, max_y = w, h, 0, 0
    found = False
    for y in range(h):
        for x in range(w):
            r, g, b, a = cleaned[y][x]
            if a < 8:
                continue
            lum = (r + g + b) / 3.0
            if lum >= 235:
                continue
            found = True
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    if not found:
        min_x, min_y, max_x, max_y = 0, 0, max(w - 1, 0), max(h - 1, 0)

    pad_src = max(2, int(0.02 * max(w, h)))
    min_x = max(0, min_x - pad_src)
    min_y = max(0, min_y - pad_src)
    max_x = min(w - 1, max_x + pad_src)
    max_y = min(h - 1, max_y + pad_src)
    crop = [row[min_x : max_x + 1] for row in cleaned[min_y : max_y + 1]]

    # Full height, slightly narrower width for a slimmer menu glyph
    margin_y = max(0, int(round(size * 0.02)))
    content_h = max(1, size - margin_y * 2)
    content_w = max(1, int(round(size * width_scale)))
    scaled = resize_rgba(crop, content_w, content_h)

    # Center the slim glyph horizontally
    margin_x = (size - content_w) // 2

    out: list[list[tuple[int, int, int, int]]] = []
    for y in range(size):
        row = []
        for x in range(size):
            sx, sy = x - margin_x, y - margin_y
            if 0 <= sx < content_w and 0 <= sy < content_h:
                r, g, b, a = scaled[sy][sx]
                if a < 8:
                    row.append((0, 0, 0, 0))
                else:
                    lum = (r + g + b) / 3.0
                    mark = 1.0 if lum < 235 else max(0.0, (250 - lum) / 15.0)
                    ta = clamp(a * mark)
                    row.append((0, 0, 0, ta))
            else:
                row.append((0, 0, 0, 0))
        out.append(row)
    return pixels_to_rows(out)


def write_appicon_contents(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "images": [
                    {"size": "16x16", "idiom": "mac", "filename": "icon_16x16.png", "scale": "1x"},
                    {"size": "16x16", "idiom": "mac", "filename": "icon_16x16@2x.png", "scale": "2x"},
                    {"size": "32x32", "idiom": "mac", "filename": "icon_32x32.png", "scale": "1x"},
                    {"size": "32x32", "idiom": "mac", "filename": "icon_32x32@2x.png", "scale": "2x"},
                    {"size": "128x128", "idiom": "mac", "filename": "icon_128x128.png", "scale": "1x"},
                    {"size": "128x128", "idiom": "mac", "filename": "icon_128x128@2x.png", "scale": "2x"},
                    {"size": "256x256", "idiom": "mac", "filename": "icon_256x256.png", "scale": "1x"},
                    {"size": "256x256", "idiom": "mac", "filename": "icon_256x256@2x.png", "scale": "2x"},
                    {"size": "512x512", "idiom": "mac", "filename": "icon_512x512.png", "scale": "1x"},
                    {"size": "512x512", "idiom": "mac", "filename": "icon_512x512@2x.png", "scale": "2x"},
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )


def rasterize_svg_if_needed(svg: Path, out_png: Path, px: int) -> Path:
    if out_png.exists() and out_png.stat().st_mtime >= svg.stat().st_mtime:
        return out_png
    out_png.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path("/tmp/rightkit-ql")
    tmp.mkdir(exist_ok=True)
    # qlmanage writes name.svg.png
    subprocess.run(
        ["qlmanage", "-t", "-s", str(px), "-o", str(tmp), str(svg)],
        check=False,
        capture_output=True,
    )
    produced = tmp / f"{svg.name}.png"
    if not produced.exists():
        raise SystemExit(f"Failed to rasterize {svg} via qlmanage")
    out_png.write_bytes(produced.read_bytes())
    return out_png


def main() -> None:
    logo_svg = DESIGN / "icon.svg"
    menu_svg = DESIGN / "menu-icon.svg"
    if not logo_svg.exists() or not menu_svg.exists():
        raise SystemExit("Missing Design/icon.svg or Design/menu-icon.svg")

    logo_png = rasterize_svg_if_needed(logo_svg, DESIGN / "icon-1024.png", 1024)
    menu_png = rasterize_svg_if_needed(menu_svg, DESIGN / "menu-icon-512.png", 512)

    _, _, logo = read_png(logo_png)
    _, _, menu = read_png(menu_png)

    # App icons
    APP_ICON.mkdir(parents=True, exist_ok=True)
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, px in sizes:
        print(f"app {name}")
        write_png(APP_ICON / name, px, px, compose_app_icon(logo, px))
    write_appicon_contents(APP_ICON / "Contents.json")

    # Extension app icon copy
    EXT_APP_ICON.mkdir(parents=True, exist_ok=True)
    for name, _ in sizes:
        (EXT_APP_ICON / name).write_bytes((APP_ICON / name).read_bytes())
    write_appicon_contents(EXT_APP_ICON / "Contents.json")

    # macOS image sets only use 1× and 2× — a 3× child is rejected by actool.
    menu_template_sizes = [("menu_16.png", 16), ("menu_32.png", 32)]
    menu_contents = {
        "images": [
            {"filename": "menu_16.png", "idiom": "mac", "scale": "1x"},
            {"filename": "menu_32.png", "idiom": "mac", "scale": "2x"},
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }

    # Finder context-menu parent glyph (extension)
    EXT_ASSETS.mkdir(parents=True, exist_ok=True)
    (EXT_ASSETS / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    MENU_ICON.mkdir(parents=True, exist_ok=True)
    for name, px in menu_template_sizes:
        print(f"menu {name}")
        write_png(MENU_ICON / name, px, px, make_template_menu(menu, px))
    (MENU_ICON / "Contents.json").write_text(json.dumps(menu_contents, indent=2) + "\n")

    # The menu bar needs a larger glyph than Finder's 16-point context-menu icon.
    status_template_sizes = [("status_20.png", 20), ("status_40.png", 40)]
    status_contents = {
        **menu_contents,
        "images": [
            {"filename": "status_20.png", "idiom": "mac", "scale": "1x"},
            {"filename": "status_40.png", "idiom": "mac", "scale": "2x"},
        ],
    }
    STATUS_ITEM.mkdir(parents=True, exist_ok=True)
    for name, px in status_template_sizes:
        print(f"status {name}")
        write_png(STATUS_ITEM / name, px, px, make_template_menu(menu, px))
    (STATUS_ITEM / "Contents.json").write_text(json.dumps(status_contents, indent=2) + "\n")
    for legacy_name in ("menu_16.png", "menu_32.png"):
        (STATUS_ITEM / legacy_name).unlink(missing_ok=True)

    print("done")


if __name__ == "__main__":
    main()
