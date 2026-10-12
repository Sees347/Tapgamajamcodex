from pathlib import Path
from PIL import Image, ImageDraw

root = Path('/workspace/validation')
progresses = (5, 35, 85, 105)
width, height = 360, 215
sheet = Image.new('RGB', (width * 4, height * 4), (16, 20, 30))
draw = ImageDraw.Draw(sheet)
for stage in (1, 2, 3):
    for col, progress in enumerate(progresses):
        path = root / f'swordfish-003-stage{stage}-p{progress:03}-f1.png'
        image = Image.open(path).convert('RGB').crop((510, 250, 830, 440)).resize((width, 190))
        x, y = col * width, (stage - 1) * height
        sheet.paste(image, (x, y + 25))
        draw.text((x + 8, y + 6), f'Stage {stage} | {progress}% | right', fill=(220, 230, 245))
for col, stage in enumerate((1, 2, 3, 5)):
    path = root / f'swordfish-003-stage{stage}-p035-f-1.png'
    image = Image.open(path).convert('RGB').crop((450, 250, 770, 440)).resize((width, 190))
    x, y = col * width, height * 3
    sheet.paste(image, (x, y + 25))
    label = f'Stage {stage} | left' if stage != 5 else 'Solid | original atlas | left'
    draw.text((x + 8, y + 6), label, fill=(220, 230, 245))
sheet.save(root / 'swordfish-003-contact-sheet.png')
print('已生成刀光多帧与镜像对照图')
