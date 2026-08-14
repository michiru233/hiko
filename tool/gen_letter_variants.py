import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

os.makedirs('tool/output', exist_ok=True)

# Colors from sample image
PINK = (255, 112, 138)       # Coral pink triangle / sakura
CYAN = (72, 209, 178)        # Emerald / mint cyan book
DARK_BLUE = (15, 42, 95)     # Deep navy text in original
BRIGHT_BLUE = (45, 95, 210)  # Bright vibrant royal blue
INDIGO = (75, 65, 190)       # Soft violet indigo
CORAL = (255, 120, 140)
MINT = (60, 215, 175)
WHITE = (255, 255, 255)

FONT_FREDOKA = 'tool/fonts/Fredoka-Bold.ttf'
FONT_NUNITO = 'tool/fonts/Nunito-Black.ttf'
FONT_BALOO = 'tool/fonts/Baloo2-ExtraBold.ttf'

def render_proposal_1(size=1024):
    """
    方案 1: 经典浅奶油白底 + 完整 'Hiko' 泡泡字 + 顶部几何小萌标
    - H 上方：耳机/或者粉色播放三角形
    - i 上方：粉色播放三角 (作为 i 的小圆点替代，或独立点)
    - k 上方：薄荷绿小书本
    - o 上方：粉色樱花
    字色：明快温润的深绀蓝/藏青，底色：高雅柔白渐变 (#F7F9FD -> #EDF2FA)
    """
    scale = 2
    canvas_size = size * scale
    im = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    # Background gradient
    bg = Image.new('RGB', (canvas_size, canvas_size))
    bg_draw = ImageDraw.Draw(bg)
    for y in range(canvas_size):
        t = y / canvas_size
        r = int(248 + (235 - 248) * t)
        g = int(250 + (242 - 250) * t)
        b = int(255 + (252 - 255) * t)
        bg_draw.line([(0, y), (canvas_size, y)], fill=(r, g, b))
    
    im.paste(bg, (0, 0))
    
    # Soft inner glow / subtle border
    draw.rounded_rectangle([20, 20, canvas_size-21, canvas_size-21], radius=int(canvas_size*0.22), outline=(230, 236, 248), width=8)

    # Render "Hiko"
    font = ImageFont.truetype(FONT_FREDOKA, 380 * scale)
    
    # We want precise control over each letter and its decoration:
    # Let's measure and draw letters individually to position accents perfectly
    text = "Hiko"
    # Letter colors: vibrant rich blue
    text_color = (24, 48, 105)
    
    # Get total width
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    start_x = (canvas_size - tw) // 2
    base_y = canvas_size * 0.52
    
    # Draw text
    draw.text((start_x, base_y - th*0.3), text, fill=text_color, font=font)
    
    # Let's find positions of i, k, o
    # In Fredoka: 'H', 'i', 'k', 'o'
    h_box = draw.textbbox((0, 0), "H", font=font)
    hi_box = draw.textbbox((0, 0), "Hi", font=font)
    hik_box = draw.textbbox((0, 0), "Hik", font=font)
    hiko_box = draw.textbbox((0, 0), "Hiko", font=font)
    
    x_H = start_x + (h_box[2] - h_box[0]) / 2
    x_i = start_x + h_box[2] + (hi_box[2] - h_box[2] - (hi_box[0]-h_box[0])) * 0.45
    x_k = start_x + hi_box[2] + (hik_box[2] - hi_box[2]) * 0.48
    x_o = start_x + hik_box[2] + (hiko_box[2] - hik_box[2]) * 0.52
    
    top_y = base_y - th * 0.55
    
    # 1. Above 'i': Pink Play triangle (or replacing dot)
    # Let's draw pink play icon
    from tool.generate_icon_proposals import draw_rounded_play, draw_book, draw_sakura, draw_headphones
    
    # Accents
    accent_size = 90 * scale
    
    # Play icon over i
    draw_rounded_play(draw, x_i, top_y + 15*scale, accent_size * 0.85, (255, 110, 138), angle=0)
    
    # Book icon over k
    draw_book(draw, x_k, top_y + 10*scale, accent_size * 0.85, (65, 210, 180))
    
    # Sakura icon over o
    draw_sakura(draw, x_o, top_y + 15*scale, accent_size * 0.9, (255, 125, 150), center_color=(255, 235, 240))
    
    # Headphone over H? (Cute option)
    # draw_headphones(draw, x_H, top_y + 15*scale, accent_size * 0.9, (100, 150, 255))

    # Mask to macOS squircle
    mask = create_squircle_mask(size)
    result = im.resize((size, size), Image.Resampling.LANCZOS)
    result.putalpha(mask)
    result.save('tool/output/proposal_1_full_word_white.png')
    print("Proposal 1 rendered")

render_proposal_1()
