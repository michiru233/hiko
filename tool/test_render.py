import os
from PIL import Image, ImageDraw, ImageFont

fonts_to_test = [
    ('Fredoka', 'tool/fonts/Fredoka-Bold.ttf'),
    ('Nunito', 'tool/fonts/Nunito-Black.ttf'),
    ('Baloo2', 'tool/fonts/Baloo2-ExtraBold.ttf'),
    ('Sniglet', 'tool/fonts/Sniglet-ExtraBold.ttf'),
    ('ArialRounded', '/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf'),
]

im = Image.new('RGB', (1600, 1000), (245, 247, 250))
draw = ImageDraw.Draw(im)

y = 50
for name, font_path in fonts_to_test:
    if os.path.exists(font_path):
        font = ImageFont.truetype(font_path, 90)
        draw.text((50, y), f"{name}:", fill=(100, 100, 100), font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf', 30))
        draw.text((300, y - 20), "Hiko  hiko  Hi", fill=(20, 40, 90), font=font)
        y += 180

im.save('tool/font_test.png')
print("Font test saved")
