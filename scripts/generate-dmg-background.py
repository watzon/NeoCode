#!/usr/bin/env python3

from __future__ import annotations

import math
import pathlib
import struct
import sys
import zlib

WIDTH = 640
HEIGHT = 420


def clamp(value: float) -> int:
    return max(0, min(255, int(round(value))))


def blend_channel(base: int, tint: int, alpha: float) -> int:
    return clamp((base * (1.0 - alpha)) + (tint * alpha))


def blend_pixel(
    buffer: bytearray, x: int, y: int, color: tuple[int, int, int], alpha: float
) -> None:
    if alpha <= 0.0 or x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
        return

    index = (y * WIDTH + x) * 4
    buffer[index] = blend_channel(buffer[index], color[0], alpha)
    buffer[index + 1] = blend_channel(buffer[index + 1], color[1], alpha)
    buffer[index + 2] = blend_channel(buffer[index + 2], color[2], alpha)
    buffer[index + 3] = 255


def build_base() -> bytearray:
    pixels = bytearray(WIDTH * HEIGHT * 4)

    top = (28, 24, 31)
    bottom = (13, 14, 19)
    vignette_center_x = WIDTH / 2
    vignette_center_y = HEIGHT / 2
    vignette_radius = math.hypot(WIDTH / 2, HEIGHT / 2)

    for y in range(HEIGHT):
        ty = y / (HEIGHT - 1)
        for x in range(WIDTH):
            tx = x / (WIDTH - 1)

            r = top[0] * (1.0 - ty) + bottom[0] * ty
            g = top[1] * (1.0 - ty) + bottom[1] * ty
            b = top[2] * (1.0 - ty) + bottom[2] * ty

            left_glow = max(0.0, 1.0 - math.hypot(x - 155, y - 110) / 260.0)
            right_glow = max(0.0, 1.0 - math.hypot(x - 490, y - 160) / 250.0)
            vignette = (
                math.hypot(x - vignette_center_x, y - vignette_center_y)
                / vignette_radius
            )

            r += 24.0 * (left_glow**2) + 4.0 * (right_glow**2)
            g += 7.0 * (left_glow**2) + 5.0 * (right_glow**2)
            b += 33.0 * (left_glow**2) + 14.0 * (right_glow**2)

            stripe = 0.5 + 0.5 * math.sin((tx * 7.0) + (ty * 4.0))
            r += stripe * 1.2
            g += stripe * 1.0
            b += stripe * 1.5

            r -= vignette * 12.0
            g -= vignette * 12.0
            b -= vignette * 12.0

            index = (y * WIDTH + x) * 4
            pixels[index] = clamp(r)
            pixels[index + 1] = clamp(g)
            pixels[index + 2] = clamp(b)
            pixels[index + 3] = 255

    return pixels


def add_glow(
    buffer: bytearray,
    center_x: float,
    center_y: float,
    radius: float,
    color: tuple[int, int, int],
    strength: float,
) -> None:
    min_x = max(0, int(center_x - radius))
    max_x = min(WIDTH - 1, int(center_x + radius))
    min_y = max(0, int(center_y - radius))
    max_y = min(HEIGHT - 1, int(center_y + radius))

    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            distance = math.hypot(x - center_x, y - center_y) / radius
            if distance >= 1.0:
                continue
            alpha = strength * ((1.0 - distance) ** 2)
            blend_pixel(buffer, x, y, color, alpha)


def rounded_rect_distance(
    px: float,
    py: float,
    center_x: float,
    center_y: float,
    width: float,
    height: float,
    radius: float,
) -> float:
    dx = abs(px - center_x) - (width / 2.0 - radius)
    dy = abs(py - center_y) - (height / 2.0 - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def add_panel(
    buffer: bytearray,
    center_x: float,
    center_y: float,
    width: float,
    height: float,
    radius: float,
    fill: tuple[int, int, int],
    fill_alpha: float,
    stroke: tuple[int, int, int],
    stroke_alpha: float,
    stroke_width: float,
) -> None:
    min_x = max(0, int(center_x - width / 2.0 - 4))
    max_x = min(WIDTH - 1, int(center_x + width / 2.0 + 4))
    min_y = max(0, int(center_y - height / 2.0 - 4))
    max_y = min(HEIGHT - 1, int(center_y + height / 2.0 + 4))

    for y in range(min_y, max_y + 1):
        py = y + 0.5
        for x in range(min_x, max_x + 1):
            px = x + 0.5
            distance = rounded_rect_distance(
                px, py, center_x, center_y, width, height, radius
            )
            if distance <= 0.0:
                blend_pixel(buffer, x, y, fill, fill_alpha)
            if abs(distance) <= stroke_width:
                edge_alpha = max(0.0, 1.0 - (abs(distance) / stroke_width))
                blend_pixel(buffer, x, y, stroke, stroke_alpha * edge_alpha)


def segment_distance(
    px: float, py: float, ax: float, ay: float, bx: float, by: float
) -> float:
    abx = bx - ax
    aby = by - ay
    length_squared = abx * abx + aby * aby
    if length_squared == 0.0:
        return math.hypot(px - ax, py - ay)

    projection = ((px - ax) * abx + (py - ay) * aby) / length_squared
    projection = max(0.0, min(1.0, projection))
    nearest_x = ax + abx * projection
    nearest_y = ay + aby * projection
    return math.hypot(px - nearest_x, py - nearest_y)


def add_segment(
    buffer: bytearray,
    ax: float,
    ay: float,
    bx: float,
    by: float,
    color: tuple[int, int, int],
    width: float,
    alpha: float,
) -> None:
    min_x = max(0, int(min(ax, bx) - width - 2))
    max_x = min(WIDTH - 1, int(max(ax, bx) + width + 2))
    min_y = max(0, int(min(ay, by) - width - 2))
    max_y = min(HEIGHT - 1, int(max(ay, by) + width + 2))

    for y in range(min_y, max_y + 1):
        py = y + 0.5
        for x in range(min_x, max_x + 1):
            px = x + 0.5
            distance = segment_distance(px, py, ax, ay, bx, by)
            if distance > width:
                continue
            edge_alpha = max(0.0, 1.0 - (distance / width))
            blend_pixel(buffer, x, y, color, alpha * edge_alpha)


def write_png(path: pathlib.Path, pixels: bytearray) -> None:
    raw = bytearray()
    row_bytes = WIDTH * 4
    for y in range(HEIGHT):
        raw.append(0)
        start = y * row_bytes
        raw.extend(pixels[start : start + row_bytes])

    compressed = zlib.compress(bytes(raw), level=9)

    def chunk(name: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + name
            + data
            + struct.pack(">I", zlib.crc32(name + data) & 0xFFFFFFFF)
        )

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)))
    png.extend(chunk(b"IDAT", compressed))
    png.extend(chunk(b"IEND", b""))
    path.write_bytes(png)


def main() -> int:
    output_path = (
        pathlib.Path(sys.argv[1])
        if len(sys.argv) > 1
        else pathlib.Path("scripts/assets/dmg-background.png")
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)

    pixels = build_base()

    add_glow(pixels, 165, 155, 145, (130, 48, 255), 0.18)
    add_glow(pixels, 205, 170, 125, (255, 107, 25), 0.15)
    add_glow(pixels, 470, 160, 118, (132, 144, 178), 0.08)
    add_glow(pixels, 320, 205, 90, (255, 140, 76), 0.06)

    add_panel(
        pixels, 170, 188, 164, 170, 28, (18, 20, 27), 0.30, (255, 165, 120), 0.20, 1.6
    )
    add_panel(
        pixels, 470, 188, 164, 170, 28, (16, 19, 24), 0.26, (164, 176, 204), 0.16, 1.4
    )

    add_segment(pixels, 258, 188, 378, 188, (255, 174, 135), 3.0, 0.25)
    add_segment(pixels, 344, 176, 378, 188, (255, 174, 135), 2.4, 0.26)
    add_segment(pixels, 344, 200, 378, 188, (255, 174, 135), 2.4, 0.26)
    add_glow(pixels, 318, 188, 32, (255, 140, 76), 0.10)

    write_png(output_path, pixels)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
