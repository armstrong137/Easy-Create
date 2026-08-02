from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from string import Template


FRAME_COUNT = 28
WIDTH = 941
HEIGHT = 1672
BACKGROUND = "#FDF6EC"
DEFAULT_FRAME_DIR = Path("picture/魔树动画素材")
DEFAULT_RECIPE = DEFAULT_FRAME_DIR / "magic_tree_img2img_recipe.json"
VALIDATOR = Path("scripts/validate_magic_tree_frames.py")


def growth_curve(index: int) -> float:
    return (index - 1) / (FRAME_COUNT - 1)


def frame_name(index: int) -> str:
    return f"magic_tree_f{index:02d}.jpg"


def stage_description(progress: float) -> str:
    if progress < 0.16:
        return "完整小树苗，细主干，少量卷曲藤梢，小树冠清楚闭合"
    if progress < 0.38:
        return "幼年魔藤树，主干略变粗，树冠升高，新增少量叶片"
    if progress < 0.68:
        return "成长中的魔藤树，藤条逐步缠绕变粗，叶片数量增加，单叶尺寸稳定"
    if progress < 0.90:
        return "接近成熟的魔藤树，高度继续增长，树冠更密，主藤更有体积"
    return "完整成熟魔藤树，树冠饱满，藤条粗壮，但机位和土堆完全不变"


def positive_prompt(index: int) -> str:
    progress = growth_curve(index)
    return (
        "single complete magical vine tree growth frame, "
        f"frame {index:02d} of 28, progress {progress:.3f}, "
        f"{stage_description(progress)}, "
        "full plant visible from soil mound to closed crown, fixed front camera, "
        "fixed lens, fixed composition, fixed soil mound, fixed cream background "
        f"{BACKGROUND}, realistic high detail fantasy botanical illustration, "
        "braided green vines, natural curled tender shoot at the top, "
        "1 to 2 small fresh leaves near the growth tip, consistent light direction, "
        "leaf count gradually increases, trunk gradually taller and thicker, "
        "single leaf absolute size stays almost unchanged, JPEG asset, no text"
    )


def negative_prompt() -> str:
    return (
        "cropped plant, cut line, reveal animation, mature tree lower half only, "
        "zoom, scaled copy, stretching, tiling, repeated texture, patch overlay, "
        "flat green paper crown, gray smoke, blurred top, white halo, matting halo, "
        "transparent background, changing soil, moving soil, changing camera, "
        "background color drift, huge leaves, shrinking tree, duplicate frame, "
        "watermark, label, text, border, UI, shadow card"
    )


def denoise_strength(index: int) -> float:
    if index == 1:
        return 0.34
    if index <= 5:
        return 0.16
    if index <= 18:
        return 0.14
    return 0.12


# 链式生成全程用同一颗种子：种子逐帧变动会在低重绘之外额外引入随机漂移，
# 而我们要的恰恰是"只在上一帧上小改"。
CHAIN_SEED = 860731


def build_recipe(frame_dir: Path, reference: Path | None) -> dict:
    frames = []
    for index in range(1, FRAME_COUNT + 1):
        input_frame = None
        if index == 1 and reference:
            input_frame = str(reference)
        elif index > 1:
            input_frame = str(frame_dir / frame_name(index - 1))

        frames.append(
            {
                "frame": index,
                "input": input_frame,
                "output": str(frame_dir / frame_name(index)),
                "width": WIDTH,
                "height": HEIGHT,
                "background": BACKGROUND,
                "format": "jpeg",
                "jpeg_quality": 90,
                "denoise_strength": denoise_strength(index),
                "seed": CHAIN_SEED,
                "prompt": positive_prompt(index),
                "negative_prompt": negative_prompt(),
                "must_keep": [
                    "每一帧都是完整植株，不允许只露出成熟树的一部分",
                    "土堆位置、宽度、底边、纹理必须逐帧固定",
                    "背景必须逐帧保持 #FDF6EC",
                    "树冠必须真实重绘成绿色嫩梢，不能用覆盖层、羽化、涂抹补丁",
                    "单叶尺寸基本不变，通过增加叶片数量和主藤粗细表现生长",
                ],
            }
        )

    return {
        "version": 1,
        "goal": "完整小树苗自然长成完整魔藤树的 28 帧 img2img 链式素材",
        "frame_count": FRAME_COUNT,
        "size": [WIDTH, HEIGHT],
        "background": BACKGROUND,
        "frame_dir": str(frame_dir),
        "validator": str(VALIDATOR),
        "rejection_rules": [
            "禁止成熟大树等比缩放",
            "禁止成熟大树自下而上揭开",
            "禁止后期覆盖层、遮罩羽化、涂抹拉伸、贴图补树冠",
        ],
        "frames": frames,
    }


def write_recipe(args: argparse.Namespace) -> int:
    # f01 没有上一帧可用，必须给一张起始参考图；否则 provider 会在第一帧
    # 拿到空输入直接失败，整条链断在第一步。
    if not args.reference:
        print(
            "缺少 --reference：第 1 帧没有上一帧可用，必须指定一张起始参考图。"
            " 这张图应当是一株完整的小树苗（有根、有干、有小树冠，"
            "立在与目标一致的固定土堆上、背景 #FDF6EC），而不是成熟大树。",
            file=sys.stderr,
        )
        return 2
    if not args.reference.exists():
        print(f"起始参考图不存在: {args.reference}", file=sys.stderr)
        return 2

    recipe = build_recipe(args.frame_dir, args.reference)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(recipe, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"已写入配方: {args.out}")
    return 0


def format_command(template: str, frame: dict) -> str:
    values = {
        "input": frame.get("input") or "",
        "output": frame["output"],
        "prompt": frame["prompt"],
        "negative_prompt": frame["negative_prompt"],
        "denoise": str(frame["denoise_strength"]),
        "width": str(frame["width"]),
        "height": str(frame["height"]),
        "seed": str(frame["seed"]),
        "frame": f"{frame['frame']:02d}",
    }
    return Template(template).safe_substitute(values)


def run_recipe(args: argparse.Namespace) -> int:
    recipe = json.loads(args.recipe.read_text(encoding="utf-8"))
    frames = recipe["frames"]
    frame_dir = Path(recipe["frame_dir"])
    frame_dir.mkdir(parents=True, exist_ok=True)

    for frame in frames:
        command = format_command(args.provider_command, frame)
        print(f"生成 f{frame['frame']:02d}: {command}")
        if args.dry_run:
            continue
        env = os.environ.copy()
        env["MAGIC_TREE_PROMPT"] = frame["prompt"]
        env["MAGIC_TREE_NEGATIVE_PROMPT"] = frame["negative_prompt"]
        completed = subprocess.run(command, shell=True, env=env)
        if completed.returncode != 0:
            print(f"生成 f{frame['frame']:02d} 失败，退出码 {completed.returncode}")
            return completed.returncode

    if args.dry_run:
        return 0
    return validate_frames(argparse.Namespace(frame_dir=frame_dir, json_out=args.json_out))


def validate_frames(args: argparse.Namespace) -> int:
    command = [sys.executable, str(VALIDATOR), str(args.frame_dir)]
    if args.json_out:
        command.extend(["--json-out", str(args.json_out)])
    completed = subprocess.run(command)
    return completed.returncode


def main() -> None:
    parser = argparse.ArgumentParser(
        description="生成魔树 img2img 链式素材配方，并在外部生成器完成后跑验收。"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    recipe_parser = sub.add_parser("write-recipe", help="写出 28 帧生成配方 JSON")
    recipe_parser.add_argument("--frame-dir", type=Path, default=DEFAULT_FRAME_DIR)
    recipe_parser.add_argument("--reference", type=Path)
    recipe_parser.add_argument("--out", type=Path, default=DEFAULT_RECIPE)
    recipe_parser.set_defaults(func=write_recipe)

    run_parser = sub.add_parser("run", help="按配方调用外部 img2img 命令")
    run_parser.add_argument("--recipe", type=Path, default=DEFAULT_RECIPE)
    run_parser.add_argument(
        "--provider-command",
        required=True,
        help=(
            "外部生成器命令模板，可用 $input $output $prompt "
            "$negative_prompt $denoise $width $height $seed $frame；"
            "PowerShell 中请用单引号包住整段模板，避免变量被提前展开"
        ),
    )
    run_parser.add_argument("--json-out", type=Path)
    run_parser.add_argument("--dry-run", action="store_true")
    run_parser.set_defaults(func=run_recipe)

    validate_parser = sub.add_parser("validate", help="验收当前帧目录")
    validate_parser.add_argument("--frame-dir", type=Path, default=DEFAULT_FRAME_DIR)
    validate_parser.add_argument("--json-out", type=Path)
    validate_parser.set_defaults(func=validate_frames)

    args = parser.parse_args()
    raise SystemExit(args.func(args))


if __name__ == "__main__":
    main()
