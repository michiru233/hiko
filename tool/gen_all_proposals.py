import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

os.makedirs('tool/output', exist_ok=True)

# -------------------------------------------------------------
# 基础几何绘制辅助函数
# -------------------------------------------------------------
def create_squircle_mask(size, radius_ratio=0.224):
    scale = 4
    w, h = size * scale, size * scale
    r = int(w * radius_ratio)
    mask = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)

def draw_rounded_triangle(draw, cx, cy, size, color, angle=0):
    w = size * 0.88
    h = size * 0.95
    r = size * 0.16
    
    rad = math.radians(angle)
    def rot(px, py):
        return (px * math.cos(rad) - py * math.sin(rad) + cx,
                px * math.sin(rad) + py * math.cos(rad) + cy)

    p1 = (-w * 0.45 + r, -h * 0.5 + r)
    p2 = (-w * 0.45 + r, h * 0.5 - r)
    p3 = (w * 0.55 - r * 1.5, 0)

    c1, c2, c3 = rot(*p1), rot(*p2), rot(*p3)
    
    draw.ellipse([c1[0]-r, c1[1]-r, c1[0]+r, c1[1]+r], fill=color)
    draw.ellipse([c2[0]-r, c2[1]-r, c2[0]+r, c2[1]+r], fill=color)
    draw.ellipse([c3[0]-r, c3[1]-r, c3[0]+r, c3[1]+r], fill=color)
    
    # Fill center polygon
    pts = [rot(-w * 0.45, -h * 0.4), rot(-w * 0.45, h * 0.4), rot(w * 0.45, 0)]
    draw.polygon(pts, fill=color)
    draw.polygon([c1, c2, c3], fill=color)

def draw_book_icon(draw, cx, cy, size, color):
    pw = size * 0.38
    ph = size * 0.72
    r = int(size * 0.15)
    gap = size * 0.08
    draw.rounded_rectangle([cx - pw - gap/2, cy - ph/2, cx - gap/2, cy + ph/2], radius=r, fill=color)
    draw.rounded_rectangle([cx + gap/2, cy - ph/2, cx + pw + gap/2, cy + ph/2], radius=r, fill=color)

def draw_sakura_icon(draw, cx, cy, size, petal_color, center_color=None):
    num_petals = 5
    petal_r = size * 0.28
    dist = size * 0.28
    for i in range(num_petals):
        angle = i * (2 * math.pi / num_petals) - math.pi / 2
        px = cx + dist * math.cos(angle)
        py = cy + dist * math.sin(angle)
        draw.ellipse([px - petal_r, py - petal_r, px + petal_r, py + petal_r], fill=petal_color)
    draw.ellipse([cx - petal_r*1.1, cy - petal_r*1.1, cx + petal_r*1.1, cy + petal_r*1.1], fill=petal_color)
    if center_color:
        dot_r = size * 0.09
        draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=center_color)
        for i in range(num_petals):
            angle = i * (2 * math.pi / num_petals) - math.pi / 2
            px = cx + (dist*0.45) * math.cos(angle)
            py = cy + (dist*0.45) * math.sin(angle)
            draw.line([(cx, cy), (px, py)], fill=center_color, width=max(2, int(size*0.04)))

def draw_headphones_icon(draw, cx, cy, size, color):
    band_w = max(4, int(size * 0.16))
    draw.arc([cx - size*0.44, cy - size*0.46, cx + size*0.44, cy + size*0.35], start=185, end=-5, fill=color, width=band_w)
    cup_w = size * 0.22
    cup_h = size * 0.42
    draw.rounded_rectangle([cx - size*0.48 - cup_w/2, cy - cup_h*0.2, cx - size*0.48 + cup_w/2, cy + cup_h*0.8], radius=int(cup_w/2), fill=color)
    draw.rounded_rectangle([cx + size*0.48 - cup_w/2, cy - cup_h*0.2, cx + size*0.48 + cup_w/2, cy + cup_h*0.8], radius=int(cup_w/2), fill=color)

def draw_music_note(draw, cx, cy, size, color):
    # Two eighth notes connected by beam
    r = size * 0.16
    stem_h = size * 0.6
    stem_w = max(3, int(size * 0.08))
    # left head
    x1, y1 = cx - size*0.25, cy + size*0.25
    # right head
    x2, y2 = cx + size*0.22, cy + size*0.12
    draw.ellipse([x1-r*1.1, y1-r*0.8, x1+r*1.1, y1+r*0.8], fill=color)
    draw.ellipse([x2-r*1.1, y2-r*0.8, x2+r*1.1, y2+r*0.8], fill=color)
    # stems
    draw.rectangle([x1+r*0.7-stem_w, y1 - stem_h, x1+r*0.7, y1], fill=color)
    draw.rectangle([x2+r*0.7-stem_w, y2 - stem_h, x2+r*0.7, y2], fill=color)
    # beam
    beam_h = int(size * 0.14)
    pts = [
        (x1+r*0.7-stem_w, y1 - stem_h),
        (x2+r*0.7, y2 - stem_h),
        (x2+r*0.7, y2 - stem_h + beam_h),
        (x1+r*0.7-stem_w, y1 - stem_h + beam_h)
    ]
    draw.polygon(pts, fill=color)

FONT_FREDOKA = 'tool/fonts/Fredoka-Bold.ttf'
FONT_NUNITO = 'tool/fonts/Nunito-Black.ttf'
FONT_BALOO = 'tool/fonts/Baloo2-ExtraBold.ttf'

# ==============================================================================
# 方案 A: 【原汁原味还原 · 亮色柔白版】 "Hiko" 全拼音 + 萌趣三元图标 (播放键/小书/樱花)
# ==============================================================================
def render_proposal_A(size=1024):
    scale = 2
    csize = size * scale
    im = Image.new('RGB', (csize, csize), (248, 250, 253))
    draw = ImageDraw.Draw(im)
    
    # 柔和暖白渐变背景
    for y in range(csize):
        t = y / csize
        r = int(252 + (238 - 252) * t)
        g = int(253 + (244 - 253) * t)
        b = int(255 + (252 - 255) * t)
        draw.line([(0, y), (csize, y)], fill=(r, g, b))

    # 浅浅的内嵌光晕圆盘，增加现代应用图标层次感
    draw.ellipse([csize*0.06, csize*0.06, csize*0.94, csize*0.94], fill=(255, 255, 255, 200))
    
    # 字号与位置
    font = ImageFont.truetype(FONT_FREDOKA, int(370 * scale))
    text = "Hiko"
    text_color = (22, 45, 98) # 标志性深藏蓝（与原图一致的高质感深蓝）

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    start_x = (csize - tw) // 2
    base_y = csize * 0.54
    
    # 绘制基础文字
    draw.text((start_x, base_y - th*0.35), text, fill=text_color, font=font)
    
    # 计算 i, k, o 字符上方的精准锚点
    h_box = draw.textbbox((0, 0), "H", font=font)
    hi_box = draw.textbbox((0, 0), "Hi", font=font)
    hik_box = draw.textbbox((0, 0), "Hik", font=font)
    hiko_box = draw.textbbox((0, 0), "Hiko", font=font)
    
    x_i = start_x + h_box[2] + (hi_box[2] - h_box[2]) * 0.44
    x_k = start_x + hi_box[2] + (hik_box[2] - hi_box[2]) * 0.48
    x_o = start_x + hik_box[2] + (hiko_box[2] - hik_box[2]) * 0.50
    
    top_y = base_y - th * 0.58
    accent_s = 96 * scale
    
    # 顶部小图标（精确对应原图的三角播放键、展开书本、五瓣樱花）
    # 1. i 上方粉色播放键
    draw_rounded_triangle(draw, x_i, top_y + 12*scale, accent_s * 0.90, (255, 115, 138))
    # 2. k 上方薄荷青小书本
    draw_book_icon(draw, x_k, top_y + 8*scale, accent_s * 0.88, (68, 212, 180))
    # 3. o 上方粉色小樱花
    draw_sakura_icon(draw, x_o, top_y + 12*scale, accent_s * 0.95, (255, 120, 145), center_color=(255, 235, 240))

    # 输出
    mask = create_squircle_mask(size)
    res = im.resize((size, size), Image.Resampling.LANCZOS)
    res.putalpha(mask)
    res.save('tool/output/proposal_A_white_hiko.png')
    print("Proposal A saved")

# ==============================================================================
# 方案 B: 【元气马卡龙马赛克/渐变亮色底】 活泼天蓝浅底 + 白底圆角徽标 + Hiko
# ==============================================================================
def render_proposal_B(size=1024):
    scale = 2
    csize = size * scale
    im = Image.new('RGB', (csize, csize))
    draw = ImageDraw.Draw(im)
    
    # 活力天空蓝到清爽薄荷青的渐变底色
    for y in range(csize):
        for x in range(csize):
            t = (x * 0.4 + y * 0.6) / csize
            r = int(225 + (240 - 225) * t)
            g = int(242 + (250 - 242) * t)
            b = int(255 + (248 - 255) * t)
            draw.point((x, y), fill=(r, g, b))

    # 居中一个大气的白胶囊卡片，提供超高辨识度与立体感
    card_margin = csize * 0.08
    draw.rounded_rectangle(
        [card_margin, csize*0.20, csize - card_margin, csize*0.80],
        radius=int(csize*0.14),
        fill=(255, 255, 255)
    )
    
    font = ImageFont.truetype(FONT_FREDOKA, int(350 * scale))
    text = "Hiko"
    text_color = (30, 60, 130) # 活力皇家蓝

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    start_x = (csize - tw) // 2
    base_y = csize * 0.54
    draw.text((start_x, base_y - th*0.35), text, fill=text_color, font=font)
    
    h_box = draw.textbbox((0, 0), "H", font=font)
    hi_box = draw.textbbox((0, 0), "Hi", font=font)
    hik_box = draw.textbbox((0, 0), "Hik", font=font)
    hiko_box = draw.textbbox((0, 0), "Hiko", font=font)
    
    x_i = start_x + h_box[2] + (hi_box[2] - h_box[2]) * 0.44
    x_k = start_x + hi_box[2] + (hik_box[2] - hi_box[2]) * 0.48
    x_o = start_x + hik_box[2] + (hiko_box[2] - hik_box[2]) * 0.50
    
    top_y = base_y - th * 0.58
    accent_s = 92 * scale
    
    draw_rounded_triangle(draw, x_i, top_y + 12*scale, accent_s * 0.90, (255, 105, 135))
    draw_book_icon(draw, x_k, top_y + 8*scale, accent_s * 0.88, (50, 205, 175))
    draw_sakura_icon(draw, x_o, top_y + 12*scale, accent_s * 0.95, (255, 120, 150), center_color=(255, 235, 240))

    mask = create_squircle_mask(size)
    res = im.resize((size, size), Image.Resampling.LANCZOS)
    res.putalpha(mask)
    res.save('tool/output/proposal_B_card_sky.png')
    print("Proposal B saved")

# ==============================================================================
# 方案 C: 【超级大标 H + 耳机/樱花/播放三角 App 图标规范版】
# 作为桌面/手机 App 图标，小尺寸下大字母 "H" 或 "Hi" 超清晰
# ==============================================================================
def render_proposal_C(size=1024):
    scale = 2
    csize = size * scale
    im = Image.new('RGB', (csize, csize), (250, 252, 255))
    draw = ImageDraw.Draw(im)
    
    # 柔和暖粉蓝微渐变
    for y in range(csize):
        t = y / csize
        r = int(255 + (242 - 255) * t)
        g = int(248 + (248 - 248) * t)
        b = int(252 + (255 - 252) * t)
        draw.line([(0, y), (csize, y)], fill=(r, g, b))

    # 大气圆润的 "Hi" 字母组合（Hi-ko 缩写）
    font = ImageFont.truetype(FONT_FREDOKA, int(480 * scale))
    text = "Hi"
    text_color = (20, 42, 95)

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    start_x = (csize - tw) // 2 - 20*scale
    base_y = csize * 0.58
    draw.text((start_x, base_y - th*0.4), text, fill=text_color, font=font)
    
    # H 上方戴着一个可爱的小萌耳机，i 上方是粉色播放三角，右侧点缀小樱花
    h_box = draw.textbbox((0, 0), "H", font=font)
    hi_box = draw.textbbox((0, 0), "Hi", font=font)
    
    x_H = start_x + (h_box[2] - h_box[0]) * 0.5
    x_i = start_x + h_box[2] + (hi_box[2] - h_box[2]) * 0.45
    
    top_y = base_y - th * 0.65
    
    # i 点替换为粉色圆角播放三角
    draw_rounded_triangle(draw, x_i, top_y + 15*scale, 130 * scale, (255, 110, 135))
    
    # 右上方飘落樱花
    draw_sakura_icon(draw, csize*0.82, csize*0.28, 120 * scale, (255, 130, 160), center_color=(255, 235, 240))
    # 左上方薄荷绿小书
    draw_book_icon(draw, csize*0.18, csize*0.28, 110 * scale, (60, 210, 180))

    # 底部小副标 "hiko"
    sub_font = ImageFont.truetype(FONT_FREDOKA, int(90 * scale))
    sub_box = draw.textbbox((0, 0), "kikoeru audio", font=sub_font)
    draw.text(((csize - (sub_box[2]-sub_box[0]))//2, csize*0.82), "kikoeru audio", fill=(140, 160, 195), font=sub_font)

    mask = create_squircle_mask(size)
    res = im.resize((size, size), Image.Resampling.LANCZOS)
    res.putalpha(mask)
    res.save('tool/output/proposal_C_big_Hi.png')
    print("Proposal C saved")

# ==============================================================================
# 方案 D: 【全小写 'hiko' + 樱花花瓣飘落与播放键融合版】
# ==============================================================================
def render_proposal_D(size=1024):
    scale = 2
    csize = size * scale
    im = Image.new('RGB', (csize, csize))
    draw = ImageDraw.Draw(im)
    
    # 柔和暖白渐变背景
    for y in range(csize):
        t = y / csize
        r = int(255 + (240 - 255) * t)
        g = int(255 + (246 - 255) * t)
        b = int(255 + (255 - 255) * t)
        draw.line([(0, y), (csize, y)], fill=(r, g, b))

    # 柔和彩色圆形底背板
    draw.ellipse([csize*0.07, csize*0.07, csize*0.93, csize*0.93], fill=(242, 246, 255))
    
    font = ImageFont.truetype(FONT_FREDOKA, int(360 * scale))
    text = "hiko"
    text_color = (25, 50, 110)

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    start_x = (csize - tw) // 2
    base_y = csize * 0.55
    draw.text((start_x, base_y - th*0.35), text, fill=text_color, font=font)
    
    h_box = draw.textbbox((0, 0), "h", font=font)
    hi_box = draw.textbbox((0, 0), "hi", font=font)
    hik_box = draw.textbbox((0, 0), "hik", font=font)
    hiko_box = draw.textbbox((0, 0), "hiko", font=font)
    
    x_i = start_x + h_box[2] + (hi_box[2] - h_box[2]) * 0.46
    x_k = start_x + hi_box[2] + (hik_box[2] - hi_box[2]) * 0.50
    x_o = start_x + hik_box[2] + (hiko_box[2] - hik_box[2]) * 0.50
    
    top_y = base_y - th * 0.56
    accent_s = 92 * scale
    
    # 萌趣三元装饰
    draw_rounded_triangle(draw, x_i, top_y + 12*scale, accent_s * 0.88, (255, 110, 138))
    draw_book_icon(draw, x_k, top_y + 6*scale, accent_s * 0.85, (65, 215, 180))
    draw_sakura_icon(draw, x_o, top_y + 10*scale, accent_s * 0.95, (255, 125, 150), center_color=(255, 235, 240))

    mask = create_squircle_mask(size)
    res = im.resize((size, size), Image.Resampling.LANCZOS)
    res.putalpha(mask)
    res.save('tool/output/proposal_D_lowercase_hiko.png')
    print("Proposal D saved")

render_proposal_A()
render_proposal_B()
render_proposal_C()
render_proposal_D()
