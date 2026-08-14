import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def draw_squircle_mask(size, radius_ratio=0.22):
    # Create smooth squircle / rounded rect mask
    scale = 4
    w, h = size * scale, size * scale
    r = int(w * radius_ratio)
    mask = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)

def draw_play_icon(draw, cx, cy, size, color):
    # Equilateral triangle pointing right with rounded corners
    h = size
    w = size * 0.95
    # points: left-top, left-bottom, right-middle
    p1 = (cx - w * 0.45, cy - h * 0.5)
    p2 = (cx - w * 0.45, cy + h * 0.5)
    p3 = (cx + w * 0.55, cy)
    draw.polygon([p1, p2, p3], fill=color)

def draw_book_icon(draw, cx, cy, size, color):
    # Two curved pages open book
    pw = size * 0.42
    ph = size * 0.85
    # left page
    draw.rounded_rectangle([cx - pw - size*0.06, cy - ph/2, cx - size*0.06, cy + ph/2], radius=int(size*0.18), fill=color)
    # right page
    draw.rounded_rectangle([cx + size*0.06, cy - ph/2, cx + pw + size*0.06, cy + ph/2], radius=int(size*0.18), fill=color)

def draw_flower_icon(draw, cx, cy, size, color, center_dot_color=None):
    # 5-petal sakura flower
    num_petals = 5
    petal_r = size * 0.28
    dist = size * 0.26
    for i in range(num_petals):
        angle = i * (2 * math.pi / num_petals) - math.pi / 2
        px = cx + dist * math.cos(angle)
        py = cy + dist * math.sin(angle)
        draw.ellipse([px - petal_r, py - petal_r, px + petal_r, py + petal_r], fill=color)
    draw.ellipse([cx - petal_r*1.1, cy - petal_r*1.1, cx + petal_r*1.1, cy + petal_r*1.1], fill=color)
    if center_dot_color:
        # small center star / dot
        dot_r = size * 0.1
        draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=center_dot_color)

def draw_headphones_icon(draw, cx, cy, size, color):
    # Cute headphone headband + earcups
    # Headband arc
    band_w = int(size * 0.18)
    draw.arc([cx - size*0.42, cy - size*0.45, cx + size*0.42, cy + size*0.35], start=180, end=0, fill=color, width=band_w)
    # Earcups
    cup_w = size * 0.22
    cup_h = size * 0.45
    draw.rounded_rectangle([cx - size*0.48 - cup_w/2, cy - cup_h*0.2, cx - size*0.48 + cup_w/2, cy + cup_h*0.8], radius=int(cup_w/2), fill=color)
    draw.rounded_rectangle([cx + size*0.48 - cup_w/2, cy - cup_h*0.2, cx + size*0.48 + cup_w/2, cy + cup_h*0.8], radius=int(cup_w/2), fill=color)

def draw_sparkle_icon(draw, cx, cy, size, color):
    # 4-point star sparkle
    r = size * 0.5
    inner_r = size * 0.15
    pts = []
    for i in range(8):
        angle = i * math.pi / 4 - math.pi / 2
        cur_r = r if i % 2 == 0 else inner_r
        pts.append((cx + cur_r * math.cos(angle), cy + cur_r * math.sin(angle)))
    draw.polygon(pts, fill=color)

print("Helper functions defined successfully")
