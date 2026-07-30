from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageStat


BG = np.array([253, 246, 236], dtype=np.float32)


def load_frames(frame_dir: Path) -> list[Path]:
    jpg = sorted(frame_dir.glob("magic_tree_f*.jpg"))
    png = sorted(frame_dir.glob("magic_tree_f*.png"))
    frames = jpg if jpg else png
    if len(frames) != 28:
        raise SystemExit(f"需要 28 帧，当前 {len(frames)} 帧")
    return frames


def green_mask(arr: np.ndarray) -> np.ndarray:
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    return (g > r + 10) & (g > b + 14) & (g > 70)


def soil_mask(arr: np.ndarray) -> np.ndarray:
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    avg = (r + g + b) / 3
    return (avg < 120) & (r > g * 0.65) & (g > b * 0.55)


def bbox(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("frame_dir", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--max-diff", type=float, default=8.0)
    parser.add_argument("--max-soil-drift", type=float, default=0.01)
    args = parser.parse_args()

    paths = load_frames(args.frame_dir)
    images = [Image.open(p).convert("RGB") for p in paths]
    arrays = [np.asarray(im).astype(np.float32) for im in images]
    sizes = sorted({im.size for im in images})

    diffs = [
        float(np.mean(np.abs(arrays[i + 1] - arrays[i])))
        for i in range(len(arrays) - 1)
    ]

    plant_tops: list[float] = []
    soil_bottoms: list[float] = []
    soil_widths: list[float] = []
    bg_means: list[list[float]] = []
    for arr in arrays:
        gm = green_mask(arr)
        sm = soil_mask(arr)
        gb = bbox(gm)
        sb = bbox(sm)
        h, w = arr.shape[:2]
        plant_tops.append((gb[1] / h) if gb else 1.0)
        if sb:
            soil_widths.append((sb[2] - sb[0] + 1) / w)
            soil_bottoms.append(sb[3] / h)
        else:
            soil_widths.append(0.0)
            soil_bottoms.append(0.0)
        bg_sample = arr[: max(1, h // 8), :, :]
        bg_means.append([round(v, 2) for v in ImageStat.Stat(Image.fromarray(bg_sample.astype(np.uint8))).mean])

    top_regressions = [
        i + 1
        for i in range(len(plant_tops) - 1)
        if plant_tops[i + 1] > plant_tops[i] + 0.006
    ]
    soil_width_drift = max(soil_widths) - min(soil_widths)
    soil_bottom_drift = max(soil_bottoms) - min(soil_bottoms)
    bg_range = np.ptp(np.array(bg_means), axis=0).tolist()

    result = {
        "frame_count": len(paths),
        "sizes": sizes,
        "avg_neighbor_diff_min": round(min(diffs), 3),
        "avg_neighbor_diff_max": round(max(diffs), 3),
        "avg_neighbor_diff_values": [round(v, 3) for v in diffs],
        "plant_top_regressions": top_regressions,
        "soil_width_min": round(min(soil_widths), 4),
        "soil_width_max": round(max(soil_widths), 4),
        "soil_width_drift": round(soil_width_drift, 4),
        "soil_bottom_min": round(min(soil_bottoms), 4),
        "soil_bottom_max": round(max(soil_bottoms), 4),
        "soil_bottom_drift": round(soil_bottom_drift, 4),
        "background_mean_range": [round(float(v), 3) for v in bg_range],
        "pass": (
            max(diffs) <= args.max_diff
            and not top_regressions
            and soil_width_drift <= args.max_soil_drift
            and soil_bottom_drift <= args.max_soil_drift
        ),
    }

    text = json.dumps(result, ensure_ascii=False, indent=2)
    print(text)
    if args.json_out:
        args.json_out.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
