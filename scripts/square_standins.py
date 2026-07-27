# 把星球替身图补成正方形（不缩放、只补透明边），并让球心落在图心。
#
# 为什么必须做：替身在 Flutter 侧是 `Image.asset(..., width: full, height: full,
# fit: BoxFit.fill)` 画进**正方形**框，而素材原是 974x907（长宽比 1.0739）——
# BoxFit.fill 会把球纵向拉伸 7.4%，替身球是椭圆，和真实场景的正球对不上，
# 交叉淡入时就是"大小/形状跳一下"（用户实测）。
#
# 补边后 BoxFit.fill 变成纯等比缩放：球保持正圆，且"球宽/图宽"比例不变，
# 仍与当初从真实场景截取时的取景一致（画在 3×直径 的框里 = 0.924×直径）。
#
# 幂等：已是正方形且球心居中的图不再改动。用法：python scripts/square_standins.py
import pathlib
from PIL import Image

DIR = pathlib.Path(__file__).resolve().parent.parent / 'assets/planet_scene/standins'

for path in sorted(DIR.glob('*.png')):
    im = Image.open(path).convert('RGBA')
    w, h = im.size
    bbox = im.split()[3].getbbox()
    if not bbox:
        print(f'跳过 {path.name}：整图透明')
        continue
    cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
    side = max(w, h)
    # 目标：球心落在新图正中
    off_x = round(side / 2 - cx)
    off_y = round(side / 2 - cy)
    if w == h and off_x == 0 and off_y == 0:
        print(f'{path.name}：已是正方形且球心居中，跳过')
        continue
    out = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    out.paste(im, (off_x, off_y))
    out.save(path)
    nb = out.split()[3].getbbox()
    ncx, ncy = (nb[0] + nb[2]) / 2, (nb[1] + nb[3]) / 2
    print(
        f'{path.name}: {w}x{h} -> {side}x{side}，'
        f'球径 {nb[2] - nb[0]}x{nb[3] - nb[1]}，'
        f'球心偏移 ({ncx - side / 2:+.1f}, {ncy - side / 2:+.1f})，'
        f'球宽/图宽 {(nb[2] - nb[0]) / side:.4f}'
    )
