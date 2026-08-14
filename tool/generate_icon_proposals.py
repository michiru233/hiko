import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

os.makedirs('tool/output', exist_ok=True)

def create_squircle_mask(size, radius_ratio=0.224):
    scale = 4
    w, h = size * scale, size * scale
    r = int(w * radius_ratio)
    mask = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)

def draw_play_triangle(draw, cx, cy, size, color, angle=0):
    # Equilateral triangle pointing right, rounded
    h = size
    w = size * 0.9
    # rotated or direct
    # let's create a local polygon
    pts = [
        (-w * 0.45, -h * 0.5),
        (-w * 0.45, h * 0.5),
        (w * 0.55, 0)
    ]
    rad = math.radians(angle)
    rot_pts = []
    for px, py in pts:
        rx = px * math.cos(rad) - py * math.sin(rad) + cx
        ry = px * math.sin(rad) + py * math.cos(rad) + cy
        rot_pts.append((rx, ry))
    
    draw.polygon(rot_pts, fill=color)

def draw_rounded_play(draw, cx, cy, size, color, angle=0):
    # Draw smooth rounded triangle
    # We can draw on 4x canvas and downscale or use overlapping circles
    w = size * 0.88
    h = size * 0.95
    r = size * 0.18
    # 3 vertices
    p1 = (-w * 0.45 + r, -h * 0.5 + r)
    p2 = (-w * 0.45 + r, h * 0.5 - r)
    p3 = (w * 0.55 - r * 1.5, 0)
    
    rad = math.radians(angle)
    def rot(pt):
        px, py = pt
        return (px * math.cos(rad) - py * math.sin(rad) + cx,
                px * math.sin(rad) + py * math.cos(rad) + cy)

    c1, c2, c3 = rot(p1), rot(p2), rot(p3)
    
    # Draw circles at vertices and connecting polygon
    draw.ellipse([c1[0]-r, c1[1]-r, c1[0]+r, c1[1]+r], fill=color)
    draw.ellipse([c2[0]-r, c2[1]-r, c2[0]+r, c2[1]+r], fill=color)
    draw.ellipse([c3[0]-r, c3[1]-r, c3[0]+r, c3[1]+r], fill=color)
    
    # Polygon connecting tangents
    draw_play_triangle(draw, cx, cy, size*0.95, color, angle)

def draw_book(draw, cx, cy, size, color, angle=0):
    # Two open pages with cute round shapes
    pw = size * 0.40
    ph = size * 0.75
    r = int(size * 0.16)
    gap = size * 0.08
    
    # We can draw left page and right page
    # Left page tilted slightly
    left_rect = [cx - pw - gap/2, cy - ph/2, cx - gap/2, cy + ph/2]
    right_rect = [cx + gap/2, cy - ph/2, cx + pw + gap/2, cy + ph/2]
    
    draw.rounded_rectangle(left_rect, radius=r, fill=color)
    draw.rounded_rectangle(right_rect, radius=r, fill=color)

def draw_sakura(draw, cx, cy, size, petal_color, center_color=None):
    # 5-petal sakura flower
    num_petals = 5
    petal_r = size * 0.27
    dist = size * 0.28
    for i in range(num_petals):
        angle = i * (2 * math.pi / num_petals) - math.pi / 2
        px = cx + dist * math.cos(angle)
        py = cy + dist * math.sin(angle)
        draw.ellipse([px - petal_r, py - petal_r, px + petal_r, py + petal_r], fill=petal_color)
    draw.ellipse([cx - petal_r*1.1, cy - petal_r*1.1, cx + petal_r*1.1, cy + petal_r*1.1], fill=petal_color)
    
    # Center 5-pointed star/dot or small pistil
    if center_color:
        dot_r = size * 0.09
        draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=center_color)
        for i in range(num_petals):
            angle = i * (2 * math.pi / num_petals) - math.pi / 2
            px = cx + (dist*0.5) * math.cos(angle)
            py = cy + (dist*0.5) * math.sin(angle)
            draw.line([(cx, cy), (px, py)], fill=center_color, width=max(2, int(size*0.04)))

def draw_headphones(draw, cx, cy, size, color):
    band_w = max(3, int(size * 0.16))
    draw.arc([cx - size*0.42, cy - size*0.46, cx + size*0.42, cy + size*0.35], start=185, end=-5, fill=color, width=band_w)
    cup_w = size * 0.22
    cup_h = size * 0.42
    draw.rounded_rectangle([cx - size*0.48 - cup_w/2, cy - cup_h*0.2, cx - size*0.48 + cup_w/2, cy + cup_h*0.8], radius=int(cup_w/2), fill=color)
    draw.rounded_rectangle([cx + size*0.48 - cup_w/2, cy - cup_h*0.2, cx + size*0.48 + cup_w/2, cy + cup_h*0.8], radius=int(cup_w/2), fill=color)

def draw_gradient_background(draw, size, c_top, c_bottom, direction='vertical'):
    for y in range(size):
        for x in range(size):
            if direction == 'vertical':
                t = y / (size - 1)
            elif direction == 'diagonal':
                t = (x + y) / (2 * (size - 1))
            elif direction == 'radial':
                dx = (x - size/2) / (size/2)
                dy = (y - size/2) / (size/2)
                t = min(1.0, math.sqrt(dx*dx + dy*dy))
            else:
                t = x / (size - 1)
            
            r = int(c_top[0] + (c_bottom[0] - c_top[0]) * t)
            g = int(c_top[1] + (c_bottom[1] - c_top[1]) * t)
            b = int(c_top[2] + (c_bottom[2] - c_top[2]) * t)
            draw.point((x, y), fill=(r, g, b))

print("Proposals helper script ready")
