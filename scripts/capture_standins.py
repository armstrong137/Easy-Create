# 从**真实 three.js 场景**重新生成各星球的替身图（standins/*.png）。
#
# 为什么需要：替身在 Flutter 侧被画进边长 sceneDiameter×3 的方框（BoxFit.fill）。
# 旧素材球体只有 288px 真实像素，而手机上球要显示到约 654 设备像素（3 倍屏）＝放大
# 2.3 倍，一盖上就是一团发虚的影子（用户实测"很低清晰度的地球"）。
#
# 取景为什么用 stage=3 + **正方形**窗口：
#   球径 = 画布 /(stage × 1.02 × frameRadius)
# 替身框 = sceneDiameter×3，而 sceneDiameter 正是各星球原始取景框，故 stage=3 时
# "球径/图宽" 恰好等于替身框所需比例。必须是正方形窗口——场景 fitDistance 取
# min(vfov, hfov)，非正方形会按短边取景、球偏小（旧素材 974×907 就是这么来的，
# 补边成正方形后球比实际小约 7%，交叉淡入时会跳一下）。
#
# 抓图方式：用 Edge 无头的 --screenshot + --default-background-color=00000000
# 直接拿透明截图。**不要**走 canvas.toDataURL——渲染器没开 preserveDrawingBuffer，
# 在渲染循环之外读会得到整张透明（踩过）。无头环境也没有真 GPU，必须显式软件 GL。
#
# 用法（需先跑起本地 web 服务，默认 8788，即 scripts/serve_web.ps1）：
#   python scripts/capture_standins.py            # 先落暂存目录，供人工确认
#   python scripts/capture_standins.py --install   # 确认无误后替换正式素材
import argparse
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets/planet_scene/standins'
PLANETS = ['earth', 'mars', 'jupiter', 'venus', 'saturn']
EDGES = [
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
]


def solid_ball(path, thr=200):
    """返回 (图宽, 实心球直径, 球心)：用于校验取景比例与居中。"""
    from PIL import Image
    im = Image.open(path).convert('RGBA')
    w, _ = im.size
    bb = im.split()[3].point(lambda v: 255 if v > thr else 0).getbbox()
    if not bb:
        return w, 0, (0, 0)
    return w, bb[2] - bb[0], ((bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=8788, help='已在跑的 web 服务端口')
    ap.add_argument('--size', type=int, default=1600, help='正方形窗口边长（=输出边长）')
    ap.add_argument('--budget', type=int, default=40000, help='虚拟时间预算 ms（等贴图上传）')
    ap.add_argument('--out-dir', default=str(ROOT / 'build/_standins_new'))
    ap.add_argument('--install', action='store_true', help='校验通过后替换正式素材')
    args = ap.parse_args()

    edge = next((p for p in EDGES if pathlib.Path(p).exists()), None)
    if not edge:
        raise SystemExit('找不到 Edge，无法无头截图')
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    scene = (f'http://127.0.0.1:{args.port}/assets/assets/planet_scene/index.html'
             '?planet={}&spin=0&stage=3&lod=mid')

    ok = True
    for name in PLANETS:
        dst = out / f'{name}.png'
        dst.unlink(missing_ok=True)
        subprocess.run(
            [edge, '--headless=new', '--no-first-run',
             # 无头没有真 GPU：显式软件 GL，否则 WebGL 不出图、截出整张透明
             '--disable-gpu', '--use-gl=angle', '--use-angle=swiftshader',
             f'--user-data-dir={ROOT / "build/_capture_profile"}',
             f'--window-size={args.size},{args.size}',
             '--default-background-color=00000000',   # 透明底
             f'--virtual-time-budget={args.budget}',
             f'--screenshot={dst}', scene.format(name)],
            capture_output=True, timeout=args.budget / 1000 + 120,
        )
        if not dst.exists():
            print(f'{name}: 截图失败')
            ok = False
            continue
        w, ball, center = solid_ball(dst)
        # 土星环有倾角，alpha 外框天然不以球心对称（球体本身仍居中，实景也是这个样子），
        # 故带环的星球放宽居中判据，只拦真正跑偏的图。
        tol = w * 0.01 if name == 'saturn' else 2
        centered = abs(center[0] - w / 2) <= tol and abs(center[1] - w / 2) <= tol
        good = ball > w * 0.2 and centered
        ok = ok and good
        print(f'{name:8} {w}x{w} 实心球 {ball}px 比例 {ball / w:.4f} '
              f'球心 {center} {"OK" if good else "异常"}')

    if not ok:
        raise SystemExit('有图不合格，未替换正式素材')
    if args.install:
        for name in PLANETS:
            shutil.copy2(out / f'{name}.png', ASSETS / f'{name}.png')
        print('已替换正式素材：', ASSETS)
    else:
        print('暂存于', out, '（加 --install 才替换正式素材）')


if __name__ == '__main__':
    main()
