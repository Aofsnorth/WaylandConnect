from PIL import Image
import os

src = "/home/arthenyx/Dokumen/MyProject/WaylandConnect/wayland_connect_desktop/assets/images/app_icon.png"
res_path = "/home/arthenyx/Dokumen/MyProject/WaylandConnect/flutter_app/android/app/src/main/res"

sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

if not os.path.exists(src):
    print(f"Source {src} not found")
else:
    img = Image.open(src)
    for folder, size in sizes.items():
        folder_path = os.path.join(res_path, folder)
        os.makedirs(folder_path, exist_ok=True)
        # Resizing
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(folder_path, "ic_launcher.png"))
        resized.save(os.path.join(folder_path, "ic_launcher_round.png")) # Round can be same for square logos
    print("Icons generated successfully!")
