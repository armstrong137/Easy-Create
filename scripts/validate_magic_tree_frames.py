from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


BG = np.array([253, 246, 236], dtype=np.float32)
LUMA_WEIGHTS = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
BG_LUMA = float(np.dot(BG, LUMA_WEIGHTS))


def load_frames(frame_dir: Path) -> list[Path]:
    jpg = sorted(frame_dir.glob("magic_tree_f*.jpg"))
    png = sorted(frame_dir.glob("magic_tree_f*.png"))
    frames = jpg if jpg else png
    if len(frames) != 28:
        raise SystemExit(f"需要 28 帧，当前 {len(frames)} 帧")
    return frames


def luminance(arr: np.ndarray) -> np.ndarray:
    return arr.astype(np.float32) @ LUMA_WEIGHTS


def saturation(arr: np.ndarray) -> np.ndarray:
    rgb = arr.astype(np.float32) / 255.0
    max_channel = rgb.max(axis=2)
    min_channel = rgb.min(axis=2)
    sat = np.zeros_like(max_channel)
    non_black = max_channel > 0
    sat[non_black] = (
        (max_channel[non_black] - min_channel[non_black])
        / max_channel[non_black]
        * 255.0
    )
    return sat


def foreground_mask(arr: np.ndarray) -> np.ndarray:
    diff = np.abs(arr.astype(np.float32) - BG).sum(axis=2)
    return diff > 34


def green_mask(arr: np.ndarray) -> np.ndarray:
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    return (g > r + 10) & (g > b + 14) & (g > 70)


def soil_mask(arr: np.ndarray) -> np.ndarray:
    h = arr.shape[0]
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    avg = (r + g + b) / 3
    yy = np.arange(h)[:, None]
    lower_band = yy > h * 0.70
    greenish = (g > r * 1.10) & (g > b * 1.15)
    brownish = (r >= g * 0.70) & (g >= b * 0.55)
    return lower_band & (avg < 125) & brownish & ~greenish


def bbox(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def crop_bbox(arr: np.ndarray, box: tuple[int, int, int, int]) -> Image.Image:
    x0, y0, x1, y1 = box
    crop = arr[y0 : y1 + 1, x0 : x1 + 1].astype(np.uint8)
    return Image.fromarray(crop, mode="RGB")


def scaled_final_diff(
    final_arr: np.ndarray,
    target_arr: np.ndarray,
    final_box: tuple[int, int, int, int],
    target_box: tuple[int, int, int, int],
) -> float:
    target = crop_bbox(target_arr, target_box)
    final = crop_bbox(final_arr, final_box).resize(target.size, Image.Resampling.LANCZOS)
    return float(
        np.mean(
            np.abs(np.asarray(final).astype(np.float32) - np.asarray(target).astype(np.float32))
        )
    )


def connected_component_diameters(mask: np.ndarray) -> list[float]:
    # 粗略叶片代理：只统计较大的绿色连通块，避免把藤须碎片算进去。
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    diameters: list[float] = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if seen[y, x] or not mask[y, x]:
                continue
            q: deque[tuple[int, int]] = deque([(x, y)])
            seen[y, x] = True
            area = 0
            min_x = max_x = x
            min_y = max_y = y
            while q:
                cx, cy = q.popleft()
                area += 4
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)
                for nx, ny in ((cx + 2, cy), (cx - 2, cy), (cx, cy + 2), (cx, cy - 2)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny, nx] and mask[ny, nx]:
                        seen[ny, nx] = True
                        q.append((nx, ny))
            bw = max_x - min_x + 2
            bh = max_y - min_y + 2
            if 2500 <= area <= 30000 and 0.35 <= bw / max(1, bh) <= 2.8:
                diameters.append(float((bw * bh) ** 0.5))
    return diameters


def crown_smear_ratio(arr: np.ndarray, plant_top: float) -> float:
    h = arr.shape[0]
    top = min(h - 1, max(0, int(round(plant_top * h))))
    bottom = min(h, top + 120)
    if bottom <= top:
        return 0.0
    band = arr[top:bottom]
    content = foreground_mask(band)
    if not np.any(content):
        return 0.0
    bg_distance = np.abs(band.astype(np.float32) - BG).sum(axis=2)
    bright_content = content & (luminance(band) >= BG_LUMA - 90) & (bg_distance <= 95)
    return float(np.count_nonzero(bright_content) / np.count_nonzero(content))


def crown_saturation_metrics(
    arr: np.ndarray,
    plant_top: float,
    green_box: tuple[int, int, int, int] | None,
) -> tuple[float, float]:
    h = arr.shape[0]
    top = min(h - 1, max(0, int(round(plant_top * h))))
    crown_bottom = min(h, top + 90)
    fg = foreground_mask(arr)
    sat = saturation(arr)

    crown_content = fg[top:crown_bottom]
    crown_sat = sat[top:crown_bottom][crown_content]
    if len(crown_sat) == 0:
        return 1.0, 0.0

    if green_box:
        mid_y = int(green_box[1] + (green_box[3] - green_box[1]) * 0.45)
    else:
        mid_y = top + 160

    mid_sat = None
    for offset in (0, 90, 180, -90, 270, -180, 360, 450, -270):
        y0 = max(0, min(h - 90, mid_y + offset))
        values = sat[y0 : y0 + 90][fg[y0 : y0 + 90]]
        if len(values) > 20:
            mid_sat = values
            break

    if mid_sat is None or len(mid_sat) == 0:
        return 1.0, float(np.mean(crown_sat < 60))

    return (
        float(np.mean(crown_sat) / max(1.0, float(np.mean(mid_sat)))),
        float(np.mean(crown_sat < 60)),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("frame_dir", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--max-diff", type=float, default=8.0)
    parser.add_argument("--max-soil-drift", type=float, default=0.01)
    parser.add_argument("--min-scaled-final-diff", type=float, default=15.0)
    parser.add_argument("--max-width-height-growth-ratio", type=float, default=0.5)
    parser.add_argument("--max-leaf-diameter-drift", type=float, default=0.2)
    parser.add_argument("--max-crown-smear-ratio", type=float, default=0.03)
    parser.add_argument("--max-brightness-over-bg", type=float, default=10.0)
    parser.add_argument("--min-crown-saturation-ratio", type=float, default=0.85)
    parser.add_argument("--max-crown-gray-ratio", type=float, default=0.20)
    args = parser.parse_args()

    paths = load_frames(args.frame_dir)
    images = [Image.open(p).convert("RGB") for p in paths]
    arrays = [np.asarray(im).astype(np.float32) for im in images]
    sizes = sorted({im.size for im in images})

    diffs = [
        float(np.mean(np.abs(arrays[i + 1] - arrays[i])))
        for i in range(len(arrays) - 1)
    ]

    content_boxes: list[tuple[int, int, int, int]] = []
    plant_tops: list[float] = []
    soil_bottoms: list[float] = []
    soil_widths: list[float] = []
    leaf_medians: list[float | None] = []
    leaf_counts: list[int] = []
    bg_means: list[list[float]] = []
    brightness_over_bg: list[float] = []
    green_boxes: list[tuple[int, int, int, int] | None] = []

    for arr in arrays:
        fg = foreground_mask(arr)
        gm = green_mask(arr)
        sm = soil_mask(arr)
        fb = bbox(fg)
        gb = bbox(gm)
        sb = bbox(sm)
        h, w = arr.shape[:2]
        green_boxes.append(gb)
        content_boxes.append(fb if fb else (0, 0, 0, 0))
        plant_tops.append((gb[1] / h) if gb else 1.0)
        if sb:
            soil_widths.append((sb[2] - sb[0] + 1) / w)
            soil_bottoms.append(sb[3] / h)
        else:
            soil_widths.append(0.0)
            soil_bottoms.append(0.0)
        diameters = connected_component_diameters(gm)
        leaf_counts.append(len(diameters))
        leaf_medians.append(float(np.median(diameters)) if len(diameters) >= 6 else None)
        corner = max(32, min(h, w) // 12)
        bg_sample = np.concatenate(
            [
                arr[:corner, :corner].reshape(-1, 3),
                arr[:corner, -corner:].reshape(-1, 3),
                arr[-corner:, :corner].reshape(-1, 3),
                arr[-corner:, -corner:].reshape(-1, 3),
            ],
            axis=0,
        )
        bg_means.append([round(float(v), 2) for v in bg_sample.mean(axis=0)])
        brightness_over_bg.append(float(np.max(luminance(arr)) - BG_LUMA))

    crown_smears = [
        crown_smear_ratio(arr, plant_top)
        for arr, plant_top in zip(arrays, plant_tops, strict=True)
    ]
    crown_saturation = [
        crown_saturation_metrics(arr, plant_top, green_box)
        for arr, plant_top, green_box in zip(arrays, plant_tops, green_boxes, strict=True)
    ]
    crown_saturation_ratios = [v[0] for v in crown_saturation]
    crown_gray_ratios = [v[1] for v in crown_saturation]

    top_regressions = [
        i + 1
        for i in range(len(plant_tops) - 1)
        if plant_tops[i + 1] > plant_tops[i] + 0.006
    ]
    soil_width_drift = max(soil_widths) - min(soil_widths)
    soil_bottom_drift = max(soil_bottoms) - min(soil_bottoms)
    bg_range = np.ptp(np.array(bg_means), axis=0).tolist()

    widths = [b[2] - b[0] + 1 for b in content_boxes]
    heights = [b[3] - b[1] + 1 for b in content_boxes]
    width_growth = max(widths) / max(1, min(v for v in widths if v > 1))
    height_growth = max(heights) / max(1, min(v for v in heights if v > 1))
    width_height_growth_ratio = width_growth / max(0.001, height_growth)

    final_arr = arrays[-1]
    final_box = content_boxes[-1]
    scaled_checks: dict[str, float] = {}
    for frame_number in (12, 20, 24):
        idx = frame_number - 1
        scaled_checks[f"f28_to_f{frame_number:02d}"] = scaled_final_diff(
            final_arr, arrays[idx], final_box, content_boxes[idx]
        )

    present_leaf_medians = [v for v in leaf_medians if v is not None]
    if present_leaf_medians:
        leaf_drift = (max(present_leaf_medians) - min(present_leaf_medians)) / max(
            1.0, float(np.median(present_leaf_medians))
        )
    else:
        leaf_drift = 0.0

    scaled_final_min = min(scaled_checks.values())
    pass_checks = {
        "neighbor_diff": max(diffs) <= args.max_diff,
        "not_scaled_final": scaled_final_min >= args.min_scaled_final_diff,
        "vertical_growth_ratio": width_height_growth_ratio <= args.max_width_height_growth_ratio,
        "leaf_diameter_stable": leaf_drift <= args.max_leaf_diameter_drift,
        "soil_width_stable": soil_width_drift <= args.max_soil_drift,
        "soil_bottom_stable": soil_bottom_drift <= args.max_soil_drift,
        "plant_top_monotonic": not top_regressions,
        "background_stable": max(bg_range) <= 2.0,
        "crown_smear": max(crown_smears) <= args.max_crown_smear_ratio,
        "brightness_not_over_bg": max(brightness_over_bg) <= args.max_brightness_over_bg,
        "crown_saturation_ratio": min(crown_saturation_ratios)
        >= args.min_crown_saturation_ratio,
        "crown_gray_ratio": max(crown_gray_ratios) <= args.max_crown_gray_ratio,
        "format_and_size": len(sizes) == 1
        and sizes[0] == (941, 1672)
        and paths[0].suffix.lower() == ".jpg",
    }

    result = {
        "frame_count": len(paths),
        "sizes": sizes,
        "format": paths[0].suffix.lower().lstrip("."),
        "avg_neighbor_diff_min": round(min(diffs), 3),
        "avg_neighbor_diff_max": round(max(diffs), 3),
        "avg_neighbor_diff_values": [round(v, 3) for v in diffs],
        "scaled_final_diff": {k: round(v, 3) for k, v in scaled_checks.items()},
        "scaled_final_diff_min": round(scaled_final_min, 3),
        "content_width_growth": round(width_growth, 3),
        "content_height_growth": round(height_growth, 3),
        "width_height_growth_ratio": round(width_height_growth_ratio, 3),
        "leaf_diameter_medians": [None if v is None else round(v, 3) for v in leaf_medians],
        "leaf_component_counts": leaf_counts,
        "leaf_diameter_drift": round(leaf_drift, 3),
        "plant_top_regressions": top_regressions,
        "soil_width_min": round(min(soil_widths), 4),
        "soil_width_max": round(max(soil_widths), 4),
        "soil_width_drift": round(soil_width_drift, 4),
        "soil_bottom_min": round(min(soil_bottoms), 4),
        "soil_bottom_max": round(max(soil_bottoms), 4),
        "soil_bottom_drift": round(soil_bottom_drift, 4),
        "background_mean_range": [round(float(v), 3) for v in bg_range],
        "crown_smear_ratio_max": round(max(crown_smears), 4),
        "crown_smear_ratio_values": [round(v, 4) for v in crown_smears],
        "brightness_over_bg_max": round(max(brightness_over_bg), 3),
        "brightness_over_bg_values": [round(v, 3) for v in brightness_over_bg],
        "crown_saturation_ratio_min": round(min(crown_saturation_ratios), 4),
        "crown_saturation_ratio_values": [
            round(v, 4) for v in crown_saturation_ratios
        ],
        "crown_gray_ratio_max": round(max(crown_gray_ratios), 4),
        "crown_gray_ratio_values": [round(v, 4) for v in crown_gray_ratios],
        "checks": pass_checks,
        "pass": all(pass_checks.values()),
    }

    text = json.dumps(result, ensure_ascii=False, indent=2)
    print(text)
    if args.json_out:
        args.json_out.write_text(text, encoding="utf-8")
    if not result["pass"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
