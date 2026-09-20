from pathlib import Path

from PIL import Image, ImageDraw

src_path = Path(
    r"C:\Users\goodb\.cursor\projects\c-Users-goodb-Downloads-blender-with-libraries-5-2-0"
    r"\assets\c__Users_goodb_AppData_Roaming_Cursor_User_workspaceStorage_"
    r"e05e637d2f2e2b611bdfafb5379b4661_images_image-6b16ee2d-83d7-44a7-812d-a56faa2607a5.png"
)
res = Path(r"c:\Users\goodb\Downloads\blender-with-libraries-5.2.0\android\app\src\main\res")
brand = Path(r"c:\Users\goodb\Downloads\blender-with-libraries-5.2.0\android\branding")
brand.mkdir(parents=True, exist_ok=True)

src = Image.open(src_path).convert("RGBA")
src.save(brand / "blender_logo.png")

pixels = src.getdata()
cleared = []
for r, g, b, a in pixels:
    if r < 18 and g < 18 and b < 18:
        cleared.append((0, 0, 0, 0))
    else:
        cleared.append((r, g, b, a))
logo = Image.new("RGBA", src.size)
logo.putdata(cleared)
bbox = logo.getbbox()
if bbox:
    logo = logo.crop(bbox)


def fit_on_canvas(size, scale=0.84, background=(0, 0, 0, 255)):
    canvas = Image.new("RGBA", (size, size), background)
    inner = max(1, int(size * scale))
    fitted = logo.copy()
    fitted.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.alpha_composite(fitted, (x, y))
    return canvas


def circle_mask(im):
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    mask = Image.new("L", im.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((1, 1, im.size[0] - 2, im.size[1] - 2), fill=255)
    out.paste(im, (0, 0))
    out.putalpha(mask)
    return out


densities = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

for folder, size in densities.items():
    dest = res / folder
    dest.mkdir(parents=True, exist_ok=True)
    icon = fit_on_canvas(size, scale=0.90, background=(0, 0, 0, 255))
    icon.save(dest / "ic_launcher.png", "PNG")
    circle_mask(icon).save(dest / "ic_launcher_round.png", "PNG")
    print(f"wrote {folder} {size}x{size}")

fg_dir = res / "drawable-xxxhdpi"
fg_dir.mkdir(parents=True, exist_ok=True)
fg = fit_on_canvas(432, scale=0.68, background=(0, 0, 0, 0))
fg.save(fg_dir / "ic_launcher_foreground.png", "PNG")
print("wrote adaptive foreground 432x432")
print("done")
