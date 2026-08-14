import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

im_a = Image.open('tool/output/proposal_A_white_hiko.png').convert('RGBA')
im_b = Image.open('tool/output/proposal_B_card_sky.png').convert('RGBA')
im_c = Image.open('tool/output/proposal_C_big_Hi.png').convert('RGBA')
im_d = Image.open('tool/output/proposal_D_lowercase_hiko.png').convert('RGBA')

grid_w, grid_h = 1800, 1150
grid = Image.new('RGB', (grid_w, grid_h), (242, 245, 252))
draw = ImageDraw.Draw(grid)

font_title = ImageFont.truetype('tool/fonts/Fredoka-Bold.ttf', 44)
font_label = ImageFont.truetype('tool/fonts/Fredoka-Bold.ttf', 30)

title_text = "Hiko App Icon Proposals (Bright / 亮色设计方案)"
bbox = draw.textbbox((0, 0), title_text, font=font_title)
draw.text(((grid_w - (bbox[2]-bbox[0]))//2, 35), title_text, fill=(20, 40, 85), font=font_title)

icon_size = 380
positions = [
    (150, 130, im_a, "A: Classic Bright Hiko (White/Cream)", "Clean warm-white bg + Navy blue text + Play/Book/Sakura"),
    (970, 130, im_b, "B: Sky Blue Card Style", "Pastel cyan-blue bg + Elevated white card badge"),
    (150, 630, im_c, "C: Compact 'Hi' Master Icon", "Bold 'Hi' app glyph + Sakura & Play accents (Great for dock)"),
    (970, 630, im_d, "D: Soft Lowercase 'hiko'", "Rounded bubble lowercase + Soft disc badge")
]

for x, y, img, label, desc in positions:
    shadow = Image.new('RGBA', (icon_size+40, icon_size+40), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_draw.rounded_rectangle([15, 20, icon_size+25, icon_size+30], radius=int(icon_size*0.23), fill=(20, 35, 70, 40))
    shadow = shadow.filter(ImageFilter.GaussianBlur(12))
    grid.paste(shadow, (x-20, y-10), shadow)
    
    resized_icon = img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    grid.paste(resized_icon, (x, y), resized_icon)
    
    draw.text((x, y + icon_size + 15), label, fill=(25, 45, 90), font=font_label)
    draw.text((x, y + icon_size + 55), desc, fill=(100, 120, 150), font=ImageFont.truetype('tool/fonts/Fredoka-Bold.ttf', 20))

grid.save('tool/output/all_proposals_grid.png')
print("Showcase grid created: tool/output/all_proposals_grid.png")
