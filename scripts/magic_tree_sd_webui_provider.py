from __future__ import annotations

import argparse
import base64
import io
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image


DEFAULT_API_URL = "http://127.0.0.1:7860"


def image_to_base64(path: Path) -> str:
    with path.open("rb") as file:
        return base64.b64encode(file.read()).decode("ascii")


def save_jpeg_from_base64(payload: str, output: Path, quality: int) -> None:
    raw = base64.b64decode(payload.split(",", 1)[-1])
    image = Image.open(io.BytesIO(raw)).convert("RGB")
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, format="JPEG", quality=quality, optimize=True)


def post_json(url: str, body: dict, timeout: int) -> dict:
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def build_payload(args: argparse.Namespace) -> dict:
    return {
        "init_images": [image_to_base64(args.input)],
        "prompt": args.prompt,
        "negative_prompt": args.negative_prompt,
        "denoising_strength": args.denoise,
        "width": args.width,
        "height": args.height,
        "seed": args.seed,
        "steps": args.steps,
        "cfg_scale": args.cfg_scale,
        "sampler_name": args.sampler,
        "batch_size": 1,
        "n_iter": 1,
        "restore_faces": False,
        "tiling": False,
        "resize_mode": 1,
        # 魔树序列要靠输入帧保持机位；这里不启用 WebUI 的额外后处理，避免土堆和背景漂移。
        "do_not_save_samples": True,
        "do_not_save_grid": True,
    }


def run(args: argparse.Namespace) -> int:
    if not args.input.exists():
        print(f"输入帧不存在: {args.input}", file=sys.stderr)
        return 2

    api_url = args.api_url.rstrip("/")
    endpoint = f"{api_url}/sdapi/v1/img2img"

    try:
        response = post_json(endpoint, build_payload(args), args.timeout)
    except urllib.error.URLError as exc:
        print(
            f"无法连接 img2img 后端: {endpoint}\n"
            "请先启动 Stable Diffusion WebUI / Forge，并开启 --api。",
            file=sys.stderr,
        )
        print(f"底层错误: {exc}", file=sys.stderr)
        return 3

    images = response.get("images") or []
    if not images:
        print("img2img 后端没有返回图片。", file=sys.stderr)
        return 4

    save_jpeg_from_base64(images[0], args.output, args.jpeg_quality)
    print(f"已生成: {args.output}")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stable Diffusion WebUI / Forge img2img provider，供魔树 pipeline 的 --provider-command 调用。"
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--prompt", default=os.environ.get("MAGIC_TREE_PROMPT", ""))
    parser.add_argument(
        "--negative-prompt",
        default=os.environ.get("MAGIC_TREE_NEGATIVE_PROMPT", ""),
    )
    parser.add_argument("--denoise", type=float, required=True)
    parser.add_argument("--width", type=int, default=941)
    parser.add_argument("--height", type=int, default=1672)
    parser.add_argument("--seed", type=int, default=-1)
    parser.add_argument("--steps", type=int, default=30)
    parser.add_argument("--cfg-scale", type=float, default=5.5)
    parser.add_argument("--sampler", default="DPM++ 2M Karras")
    parser.add_argument("--jpeg-quality", type=int, default=90)
    parser.add_argument(
        "--api-url",
        default=os.environ.get("SD_WEBUI_URL", DEFAULT_API_URL),
        help="Stable Diffusion WebUI / Forge API 地址，默认读取 SD_WEBUI_URL 或 http://127.0.0.1:7860",
    )
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    raise SystemExit(run(args))


if __name__ == "__main__":
    main()
