from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, UnidentifiedImageError


SCHEMA_VERSION = 1
SILHOUETTE_IOU_MIN = 0.88
MOBILE_SUBJECT_HEIGHT_MIN = 0.78
MOBILE_SUBJECT_HEIGHT_MAX = 0.90
GROWTH_TRUNK_X_RATIOS = (0.065, 0.205, 0.385, 0.605, 0.855)


class ValidationInputError(ValueError):
    pass


def rounded(value: float) -> float:
    return round(float(value), 6)


def load_image(path: Path) -> Image.Image:
    if not path.is_file():
        raise ValidationInputError(f"缺少输入图片：{path}")
    try:
        image = Image.open(path)
        image.load()
        return image
    except (OSError, UnidentifiedImageError) as error:
        raise ValidationInputError(f"图片无法解码：{path}：{error}") from error


def foreground_mask(image: Image.Image) -> np.ndarray:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.int32)
    alpha = rgba[:, :, 3]
    if np.mean(alpha < 250) > 0.001:
        mask = alpha > 24
    else:
        rgb = rgba[:, :, :3]
        height, width = rgb.shape[:2]
        vertical = max(2, height // 50)
        horizontal = max(2, width // 50)
        edge = np.concatenate(
            (
                rgb[:vertical].reshape(-1, 3),
                rgb[-vertical:].reshape(-1, 3),
                rgb[:, :horizontal].reshape(-1, 3),
                rgb[:, -horizontal:].reshape(-1, 3),
            )
        )
        background = np.percentile(edge, 80, axis=0)
        luminance = rgb @ np.array((0.2126, 0.7152, 0.0722))
        background_luminance = background @ np.array((0.2126, 0.7152, 0.0722))
        color_distance = np.sqrt(np.square(rgb - background).sum(axis=2))
        mask = (luminance < background_luminance - 32) & (color_distance > 38)

    if not np.any(mask):
        raise ValidationInputError("图片中未检测到可验收主体")
    return mask


def subject_bounds(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def row_width_percentiles(
    cropped_mask: np.ndarray, start: float, end: float
) -> list[float]:
    height, width = cropped_mask.shape
    top = int(height * start)
    bottom = max(top + 1, int(height * end))
    widths: list[float] = []
    for row in cropped_mask[top:bottom]:
        occupied = np.where(row)[0]
        if occupied.size:
            widths.append((int(occupied.max()) - int(occupied.min()) + 1) / width)
    if not widths:
        return [0.0, 0.0, 0.0, 0.0]
    return [rounded(value) for value in np.percentile(widths, (20, 50, 80, 95))]


def measure_subject(mask: np.ndarray) -> dict[str, Any]:
    canvas_height, canvas_width = mask.shape
    left, top, right, bottom = subject_bounds(mask)
    cropped = mask[top:bottom, left:right]
    subject_height, subject_width = cropped.shape
    crown_rows = row_width_percentiles(cropped, 0.12, 0.58)
    trunk_rows = row_width_percentiles(cropped, 0.62, 0.78)
    root_rows = row_width_percentiles(cropped, 0.84, 0.99)
    crown_region = cropped[
        int(subject_height * 0.08) : max(1, int(subject_height * 0.60))
    ]
    trunk_width = max(trunk_rows[1], 1 / subject_width)
    crown_width = max(crown_rows[2], 1 / subject_width)

    return {
        "canvasSize": [canvas_width, canvas_height],
        "bounds": [left, top, right, bottom],
        "subjectWidthRatio": rounded(subject_width / canvas_width),
        "subjectHeightRatio": rounded(subject_height / canvas_height),
        "aspectRatio": rounded(subject_width / subject_height),
        "foregroundAreaRatio": rounded(mask.mean()),
        "crownRowWidthP80": crown_rows[2],
        "crownFillRatio": rounded(crown_region.mean()),
        "trunkRowWidthP50": trunk_rows[1],
        "rootRowWidthP80": root_rows[2],
        "rootToTrunkRatio": rounded(root_rows[2] / trunk_width),
        "rootToCrownRatio": rounded(root_rows[2] / crown_width),
    }


def normalized_subject_mask(mask: np.ndarray) -> np.ndarray:
    left, top, right, bottom = subject_bounds(mask)
    cropped = mask[top:bottom, left:right]
    target_size = 512
    target_height = 460
    scaled_width = max(1, round(cropped.shape[1] * target_height / cropped.shape[0]))
    resized = Image.fromarray((cropped * 255).astype(np.uint8)).resize(
        (scaled_width, target_height), Image.Resampling.NEAREST
    )
    resized_mask = np.asarray(resized) > 0
    normalized = np.zeros((target_size, target_size), dtype=bool)
    source_left = max(0, (scaled_width - target_size) // 2)
    target_left = max(0, (target_size - scaled_width) // 2)
    copy_width = min(target_size, scaled_width)
    normalized[52:, target_left : target_left + copy_width] = resized_mask[
        :, source_left : source_left + copy_width
    ]
    return normalized


def silhouette_iou(reference_mask: np.ndarray, candidate_mask: np.ndarray) -> float:
    reference = normalized_subject_mask(reference_mask)
    candidate = normalized_subject_mask(candidate_mask)
    union = np.logical_or(reference, candidate).sum()
    if not union:
        return 0.0
    return rounded(np.logical_and(reference, candidate).sum() / union)


def sample_background(image: Image.Image) -> np.ndarray:
    rgb = np.asarray(image.convert("RGB"), dtype=np.int32)
    strip_height = max(2, rgb.shape[0] // 12)
    strip = rgb[:strip_height].reshape(-1, 3)
    luminance = strip @ np.array((0.2126, 0.7152, 0.0722))
    chroma = strip.max(axis=1) - strip.min(axis=1)
    candidates = strip[(luminance >= np.percentile(luminance, 55)) & (chroma < 55)]
    if not len(candidates):
        candidates = strip
    return np.median(candidates, axis=0)


def longest_true_run(values: np.ndarray) -> int:
    padded = np.pad(values.astype(np.int8), (1, 1))
    changes = np.diff(padded)
    starts = np.where(changes == 1)[0]
    ends = np.where(changes == -1)[0]
    if not starts.size:
        return 0
    return int(np.max(ends - starts))


def flat_boundary_run_ratios(
    image: Image.Image, expected_background: np.ndarray
) -> tuple[float, float]:
    rgb = np.asarray(image.convert("RGB"), dtype=np.int32)
    off_background = (
        np.sqrt(np.square(rgb - expected_background).sum(axis=2)) > 35
    )
    horizontal_change = np.sqrt(np.square(rgb[:, 1:] - rgb[:, :-1]).sum(axis=2))
    horizontal_pairs = (
        off_background[:, 1:] & off_background[:, :-1] & (horizontal_change <= 8)
    )
    vertical_change = np.sqrt(np.square(rgb[1:] - rgb[:-1]).sum(axis=2))
    vertical_pairs = (
        off_background[1:] & off_background[:-1] & (vertical_change <= 8)
    )
    horizontal = max(
        (longest_true_run(row) + 1 for row in horizontal_pairs), default=0
    )
    vertical = max(
        (longest_true_run(column) + 1 for column in vertical_pairs.T), default=0
    )
    return horizontal / rgb.shape[1], vertical / rgb.shape[0]


def measure_storyboard_growth(image: Image.Image) -> list[float]:
    mask = foreground_mask(image)
    height, width = mask.shape
    ground = int(height * 0.955)
    half_window = max(2, int(width * 0.035))
    measured: list[float] = []
    for ratio in GROWTH_TRUNK_X_RATIOS:
        center = int(width * ratio)
        local = mask[:, max(0, center - half_window) : min(width, center + half_window)]
        occupied_rows = np.where(local.any(axis=1))[0]
        top = int(occupied_rows.min()) if occupied_rows.size else ground
        measured.append(rounded(max(0, ground - top) / height))
    mature_height = max(measured[-1], 1 / height)
    return [rounded(value / mature_height) for value in measured]


def build_calibration(
    front_image: Image.Image,
    growth_image: Image.Image,
    support_image: Image.Image,
) -> tuple[dict[str, Any], np.ndarray]:
    front_mask = foreground_mask(front_image)
    front_metrics = measure_subject(front_mask)
    reference_growth = measure_storyboard_growth(growth_image)
    positive_growth_steps = [
        current - previous
        for previous, current in zip(reference_growth, reference_growth[1:])
        if current > previous
    ]
    minimum_reference_step = min(positive_growth_steps, default=0.08)
    background_samples = np.stack(
        (
            sample_background(front_image),
            sample_background(growth_image),
            sample_background(support_image),
        )
    )
    background = np.median(background_samples, axis=0)
    support_horizontal_run, support_vertical_run = flat_boundary_run_ratios(
        support_image, background
    )
    rectangular_seam_run_min = max(
        0.45, min(0.75, min(support_horizontal_run, support_vertical_run) * 1.5)
    )

    thresholds = {
        "aspectRatio": {
            "min": rounded(max(0.62, front_metrics["aspectRatio"] * 0.90)),
            "max": rounded(min(0.90, front_metrics["aspectRatio"] * 1.08)),
        },
        "silhouetteIouMin": SILHOUETTE_IOU_MIN,
        "crownRowWidthP80Min": rounded(front_metrics["crownRowWidthP80"] * 0.88),
        "crownFillRatioMin": rounded(front_metrics["crownFillRatio"] * 0.90),
        "rootRowWidthP80Min": rounded(front_metrics["rootRowWidthP80"] * 0.95),
        "rootToTrunkRatioMin": rounded(front_metrics["rootToTrunkRatio"] * 0.75),
        "growthRegressionTolerance": 0.01,
        "growthHeightStepMin": rounded(max(0.005, minimum_reference_step * 0.15)),
        "backgroundMedianDistanceMax": 18.0,
        "backgroundOffColorRatioMax": 0.12,
        "edgePollutionRatioMax": 0.04,
        "rectangularSeamRunRatioMin": rounded(rectangular_seam_run_min),
        "mobileSubjectHeightRatio": {
            "min": MOBILE_SUBJECT_HEIGHT_MIN,
            "max": MOBILE_SUBJECT_HEIGHT_MAX,
        },
    }
    return (
        {
            "frontReferenceMetrics": front_metrics,
            "storyboardStageHeightRatios": reference_growth,
            "backgroundRgb": [rounded(value) for value in background],
            "thresholds": thresholds,
        },
        front_mask,
    )


def check_result(
    metrics: dict[str, Any], thresholds: dict[str, Any], failures: list[dict[str, str]]
) -> dict[str, Any]:
    return {
        "pass": not failures,
        "metrics": metrics,
        "thresholds": thresholds,
        "failures": failures,
    }


def failure(code: str, message: str) -> dict[str, str]:
    return {"code": code, "message": message}


def monotonic_failures(
    values: list[float], tolerance: float, minimum_step: float = 0.0
) -> list[int]:
    failed: list[int] = []
    for index, (previous, current) in enumerate(zip(values, values[1:]), start=1):
        if current < previous - tolerance or current - previous < minimum_step:
            failed.append(index)
    return failed


def background_boundary_metrics(
    image: Image.Image, mask: np.ndarray, expected_background: np.ndarray
) -> dict[str, Any]:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.int32)
    rgb = rgba[:, :, :3]
    alpha = rgba[:, :, 3]
    background_pixels = rgb[~mask]
    median = (
        np.median(background_pixels, axis=0)
        if len(background_pixels)
        else np.array((0.0, 0.0, 0.0))
    )
    distances = np.sqrt(np.square(background_pixels - expected_background).sum(axis=1))
    height, width = mask.shape
    edge_size = max(2, min(height, width) // 50)
    side_limit = int(height * 0.85)
    edge_pixels = np.concatenate(
        (
            rgb[:edge_size].reshape(-1, 3),
            rgb[:side_limit, :edge_size].reshape(-1, 3),
            rgb[:side_limit, -edge_size:].reshape(-1, 3),
        )
    )
    edge_distances = np.sqrt(np.square(edge_pixels - expected_background).sum(axis=1))
    horizontal_run, vertical_run = flat_boundary_run_ratios(
        image, expected_background
    )
    return {
        "backgroundMedianRgb": [rounded(value) for value in median],
        "backgroundMedianDistance": rounded(
            np.sqrt(np.square(median - expected_background).sum())
        ),
        "backgroundOffColorRatio": rounded(np.mean(distances > 28)),
        "edgePollutionRatio": rounded(np.mean(edge_distances > 35)),
        "longFlatHorizontalRunRatio": rounded(horizontal_run),
        "longFlatVerticalRunRatio": rounded(vertical_run),
        "transparentPixelRatio": rounded(np.mean(alpha < 250)),
    }


def validate(
    stage_paths: list[Path],
    mature_browser_path: Path,
    front_reference_path: Path,
    growth_reference_path: Path,
    support_reference_path: Path,
) -> dict[str, Any]:
    stage_images = [load_image(path) for path in stage_paths]
    stage_sizes = {image.size for image in stage_images}
    if len(stage_sizes) != 1:
        raise ValidationInputError("五阶段离线渲染图必须使用相同画布尺寸")

    browser_image = load_image(mature_browser_path)
    front_image = load_image(front_reference_path)
    growth_image = load_image(growth_reference_path)
    support_image = load_image(support_reference_path)
    calibration, front_mask = build_calibration(
        front_image, growth_image, support_image
    )
    thresholds = calibration["thresholds"]
    stage_masks = [foreground_mask(image) for image in stage_images]
    stage_metrics = [measure_subject(mask) for mask in stage_masks]
    mature_metrics = stage_metrics[-1]

    iou = silhouette_iou(front_mask, stage_masks[-1])
    silhouette_failures: list[dict[str, str]] = []
    aspect_limits = thresholds["aspectRatio"]
    if not aspect_limits["min"] <= mature_metrics["aspectRatio"] <= aspect_limits["max"]:
        silhouette_failures.append(
            failure("silhouette_aspect", "成熟树轮廓宽高比超出批准参考图容差")
        )
    if iou < thresholds["silhouetteIouMin"]:
        silhouette_failures.append(
            failure("silhouette_iou", "成熟树归一化轮廓与批准正视图差异过大")
        )

    crown_failures: list[dict[str, str]] = []
    if mature_metrics["crownRowWidthP80"] < thresholds["crownRowWidthP80Min"]:
        crown_failures.append(
            failure("crown_lateral_spread", "成熟树树冠横向展开不足")
        )
    if mature_metrics["crownFillRatio"] < thresholds["crownFillRatioMin"]:
        crown_failures.append(failure("crown_fill", "成熟树树冠过疏或呈柱状簇生"))

    root_failures: list[dict[str, str]] = []
    if mature_metrics["rootRowWidthP80"] < thresholds["rootRowWidthP80Min"]:
        root_failures.append(failure("root_lateral_spread", "成熟树根系横向外扩不足"))
    if mature_metrics["rootToTrunkRatio"] < thresholds["rootToTrunkRatioMin"]:
        root_failures.append(failure("root_flare", "成熟树根颈相对主干外扩不足"))

    heights = [item["subjectHeightRatio"] for item in stage_metrics]
    widths = [item["subjectWidthRatio"] for item in stage_metrics]
    areas = [item["foregroundAreaRatio"] for item in stage_metrics]
    growth_failures: list[dict[str, str]] = []
    height_regressions = monotonic_failures(
        heights, thresholds["growthRegressionTolerance"], thresholds["growthHeightStepMin"]
    )
    width_regressions = monotonic_failures(
        widths, thresholds["growthRegressionTolerance"]
    )
    area_regressions = monotonic_failures(
        areas, thresholds["growthRegressionTolerance"]
    )
    if height_regressions:
        growth_failures.append(failure("growth_height", "五阶段树高未严格单调成长"))
    if width_regressions:
        growth_failures.append(failure("growth_width", "五阶段冠幅或根幅发生回缩"))
    if area_regressions:
        growth_failures.append(failure("growth_area", "五阶段可见植株面积发生回退"))

    browser_mask = foreground_mask(browser_image)
    browser_subject = measure_subject(browser_mask)
    expected_background = np.asarray(calibration["backgroundRgb"])
    background_metrics = background_boundary_metrics(
        browser_image, browser_mask, expected_background
    )
    stage_background_metrics = [
        background_boundary_metrics(image, mask, expected_background)
        for image, mask in zip(stage_images, stage_masks)
    ]
    background_metrics["stageMetrics"] = stage_background_metrics
    background_failures: list[dict[str, str]] = []
    if (
        background_metrics["backgroundMedianDistance"]
        > thresholds["backgroundMedianDistanceMax"]
    ):
        background_failures.append(
            failure("background_color", "浏览器截图背景偏离批准米白环境")
        )
    if (
        background_metrics["backgroundOffColorRatio"]
        > thresholds["backgroundOffColorRatioMax"]
    ):
        background_failures.append(
            failure("background_pollution", "浏览器截图存在大面积背景色差或矩形底")
        )
    if background_metrics["edgePollutionRatio"] > thresholds["edgePollutionRatioMax"]:
        background_failures.append(
            failure("boundary_pollution", "浏览器截图顶部或侧边存在可见污染边界")
        )
    seam_run_min = thresholds["rectangularSeamRunRatioMin"]
    if (
        background_metrics["longFlatHorizontalRunRatio"] >= seam_run_min
        and background_metrics["longFlatVerticalRunRatio"] >= seam_run_min
    ):
        background_failures.append(
            failure("boundary_pollution", "浏览器截图存在长直矩形底图接缝")
        )
    if background_metrics["transparentPixelRatio"] > 0:
        background_failures.append(
            failure("browser_transparency", "浏览器结果图不得含透明像素")
        )
    for index, stage_background in enumerate(stage_background_metrics, start=1):
        if (
            stage_background["backgroundMedianDistance"]
            > thresholds["backgroundMedianDistanceMax"]
        ):
            background_failures.append(
                failure(
                    "stage_background_color",
                    f"第 {index} 阶段背景偏离批准米白环境",
                )
            )
        if (
            stage_background["backgroundOffColorRatio"]
            > thresholds["backgroundOffColorRatioMax"]
        ):
            background_failures.append(
                failure(
                    "stage_background_pollution",
                    f"第 {index} 阶段存在大面积背景色差或矩形底",
                )
            )
        if stage_background["edgePollutionRatio"] > thresholds["edgePollutionRatioMax"]:
            background_failures.append(
                failure(
                    "stage_boundary_pollution",
                    f"第 {index} 阶段顶部或侧边存在可见污染边界",
                )
            )
        if (
            stage_background["longFlatHorizontalRunRatio"] >= seam_run_min
            and stage_background["longFlatVerticalRunRatio"] >= seam_run_min
        ):
            background_failures.append(
                failure(
                    "stage_boundary_pollution",
                    f"第 {index} 阶段存在长直矩形底图接缝",
                )
            )
        if stage_background["transparentPixelRatio"] > 0:
            background_failures.append(
                failure("stage_transparency", f"第 {index} 阶段不得含透明像素")
            )

    mobile_failures: list[dict[str, str]] = []
    mobile_limits = thresholds["mobileSubjectHeightRatio"]
    if not (
        mobile_limits["min"]
        <= browser_subject["subjectHeightRatio"]
        <= mobile_limits["max"]
    ):
        mobile_failures.append(
            failure("mobile_subject_height", "成熟树在移动端可用高度中的占比不合格")
        )

    checks = {
        "silhouette_dimensions": check_result(
            {**mature_metrics, "silhouetteIou": iou},
            {
                "aspectRatio": thresholds["aspectRatio"],
                "silhouetteIouMin": thresholds["silhouetteIouMin"],
            },
            silhouette_failures,
        ),
        "crown_spread": check_result(
            {
                "crownRowWidthP80": mature_metrics["crownRowWidthP80"],
                "crownFillRatio": mature_metrics["crownFillRatio"],
            },
            {
                "crownRowWidthP80Min": thresholds["crownRowWidthP80Min"],
                "crownFillRatioMin": thresholds["crownFillRatioMin"],
            },
            crown_failures,
        ),
        "root_spread": check_result(
            {
                "rootRowWidthP80": mature_metrics["rootRowWidthP80"],
                "rootToTrunkRatio": mature_metrics["rootToTrunkRatio"],
                "rootToCrownRatio": mature_metrics["rootToCrownRatio"],
            },
            {
                "rootRowWidthP80Min": thresholds["rootRowWidthP80Min"],
                "rootToTrunkRatioMin": thresholds["rootToTrunkRatioMin"],
            },
            root_failures,
        ),
        "growth_monotonicity": check_result(
            {
                "stageSubjectHeightRatios": heights,
                "stageSubjectWidthRatios": widths,
                "stageForegroundAreaRatios": areas,
                "stageMetrics": stage_metrics,
            },
            {
                "regressionTolerance": thresholds["growthRegressionTolerance"],
                "heightStepMin": thresholds["growthHeightStepMin"],
            },
            growth_failures,
        ),
        "background_boundary": check_result(
            background_metrics,
            {
                "backgroundRgb": calibration["backgroundRgb"],
                "backgroundMedianDistanceMax": thresholds[
                    "backgroundMedianDistanceMax"
                ],
                "backgroundOffColorRatioMax": thresholds[
                    "backgroundOffColorRatioMax"
                ],
                "edgePollutionRatioMax": thresholds["edgePollutionRatioMax"],
                "rectangularSeamRunRatioMin": thresholds[
                    "rectangularSeamRunRatioMin"
                ],
                "transparentPixelRatioMax": 0.0,
            },
            background_failures,
        ),
        "mobile_composition": check_result(
            browser_subject,
            {"subjectHeightRatio": mobile_limits},
            mobile_failures,
        ),
    }
    all_failures = [
        {"check": name, **item}
        for name, check in checks.items()
        for item in check["failures"]
    ]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "pass": all(check["pass"] for check in checks.values()),
        "manualReviewRequired": True,
        "inputs": {
            "stages": [path.resolve().as_posix() for path in stage_paths],
            "matureBrowser": mature_browser_path.resolve().as_posix(),
            "frontReference": front_reference_path.resolve().as_posix(),
            "growthReference": growth_reference_path.resolve().as_posix(),
            "supportReference": support_reference_path.resolve().as_posix(),
        },
        "calibration": calibration,
        "checks": checks,
        "failures": all_failures,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="校验魔树五阶段美术与移动端构图")
    parser.add_argument("--stages", nargs=5, type=Path, required=True)
    parser.add_argument("--mature-browser", type=Path, required=True)
    parser.add_argument("--front-reference", type=Path, required=True)
    parser.add_argument("--growth-reference", type=Path, required=True)
    parser.add_argument("--support-reference", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = parse_args()
    try:
        report = validate(
            args.stages,
            args.mature_browser,
            args.front_reference,
            args.growth_reference,
            args.support_reference,
        )
    except ValidationInputError as error:
        report = {
            "schemaVersion": SCHEMA_VERSION,
            "pass": False,
            "manualReviewRequired": True,
            "inputError": str(error),
            "checks": {},
            "failures": [
                {"check": "inputs", "code": "invalid_input", "message": str(error)}
            ],
        }
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 2

    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
