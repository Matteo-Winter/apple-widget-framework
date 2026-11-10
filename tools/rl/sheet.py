import sys, os
from PIL import Image, ImageDraw
def sheet(names, out, kind="large", cols=4, w=300):
    ims = []
    for n in names:
        p = f"../../experiments/rendering/img/{n}-{kind}.png"
        if os.path.exists(p): ims.append((n, Image.open(p)))
    if not ims: return
    h = int(w * ims[0][1].height / ims[0][1].width)
    rows = (len(ims) + cols - 1) // cols
    S = Image.new("RGB", (cols * (w + 10), rows * (h + 30)), "white"); d = ImageDraw.Draw(S)
    for i, (n, im) in enumerate(ims):
        x, y = (i % cols) * (w + 10), (i // cols) * (h + 30)
        S.paste(im.convert("RGB").resize((w, h)), (x, y + 20)); d.text((x + 2, y + 4), n, fill="black")
    S.save(out)
if __name__ == "__main__":
    sheet(sys.argv[3:], sys.argv[1], sys.argv[2])
