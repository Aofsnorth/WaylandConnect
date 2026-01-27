from PIL import Image
import os

input_path = "/home/arthenyx/.gemini/antigravity/brain/4aef9b40-722a-4c5d-9039-22103a8da567/uploaded_media_1769395410822.jpg"
output_path = "/home/arthenyx/Dokumen/MyProject/WaylandConnect/wayland_connect_desktop/assets/images/app_icon.png"

img = Image.open(input_path).convert("RGBA")
pixels = img.getdata()

newData = []
for r, g, b, a in pixels:
    # Use max of channels as brightness indicator
    brightness = max(r, g, b)
    
    # Threshold: anything below 10 is pure black -> 0 alpha
    # Anything above 200 is solid -> 255 alpha
    # In between is a curve
    if brightness < 20:
        alpha = 0
    elif brightness > 180:
        alpha = 255
    else:
        # Linear map 20-180 to 0-255
        alpha = int((brightness - 20) * (255 / (180 - 20)))
    
    newData.append((r, g, b, alpha))

img.putdata(newData)
img.save(output_path, "PNG")
print(f"Saved optimized transparent icon to {output_path}")

