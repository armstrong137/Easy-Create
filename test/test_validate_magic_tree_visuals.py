from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


PROJECT_ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = PROJECT_ROOT / "scripts" / "validate_magic_tree_visuals.py"
REFERENCE_ROOT = PROJECT_ROOT / "assets" / "source" / "magic_tree" / "references"
FAILED_BROWSER_CAPTURE = (
    PROJECT_ROOT
    / "docs"
    / "ui_review"
    / "rounds"
    / "2026-08-10"
    / "tree-3d"
    / "mature-430x932.jpg"
)


def create_failed_capture_stages(root: Path) -> list[Path]:
    source = Image.open(FAILED_BROWSER_CAPTURE).convert("RGB")
    background = source.getpixel((0, 0))
    stage_paths: list[Path] = []
    for index, scale in enumerate((0.30, 0.47, 0.63, 0.81, 1.00)):
        canvas = Image.new("RGB", source.size, background)
        resized = source.resize(
            (round(source.width * scale), round(source.height * scale)),
            Image.Resampling.LANCZOS,
        )
        canvas.paste(
            resized,
            ((source.width - resized.width) // 2, source.height - resized.height),
        )
        path = root / f"failed_stage_{index}.png"
        canvas.save(path)
        stage_paths.append(path)
    return stage_paths


def create_reference_shaped_inputs(root: Path) -> tuple[list[Path], Path]:
    source = Image.open(REFERENCE_ROOT / "树形正视图.png").convert("RGB")
    background = source.getpixel((0, 0))
    stage_paths: list[Path] = []
    for index, scale in enumerate((0.30, 0.47, 0.63, 0.81, 1.00)):
        canvas = Image.new("RGB", source.size, background)
        resized = source.resize(
            (round(source.width * scale), round(source.height * scale)),
            Image.Resampling.LANCZOS,
        )
        canvas.paste(
            resized,
            ((source.width - resized.width) // 2, source.height - resized.height),
        )
        path = root / f"stage_{index}.png"
        canvas.save(path)
        stage_paths.append(path)

    browser = Image.new("RGB", (430, 932), (253, 246, 236))
    browser_tree = source.resize((420, 900), Image.Resampling.LANCZOS)
    browser.paste(browser_tree, (5, 16))
    browser_path = root / "mature-browser.png"
    browser.save(browser_path)
    return stage_paths, browser_path


class ValidateMagicTreeVisualsTest(unittest.TestCase):
    def run_validator(
        self, stage_paths: list[Path], mature_browser: Path
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(VALIDATOR),
                "--stages",
                *(str(path) for path in stage_paths),
                "--mature-browser",
                str(mature_browser),
                "--front-reference",
                str(REFERENCE_ROOT / "树形正视图.png"),
                "--growth-reference",
                str(REFERENCE_ROOT / "五阶段成长分镜.png"),
                "--support-reference",
                str(REFERENCE_ROOT / "章节目枝直接承托效果图.png"),
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )

    def test_current_cactus_tree_is_rejected_with_all_visual_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            stages = create_failed_capture_stages(Path(temp_dir))

            result = self.run_validator(stages, FAILED_BROWSER_CAPTURE)

        self.assertEqual(result.returncode, 1, result.stderr or result.stdout)
        report = json.loads(result.stdout)
        self.assertFalse(report["pass"])
        self.assertEqual(
            set(report["checks"]),
            {
                "silhouette_dimensions",
                "crown_spread",
                "root_spread",
                "growth_monotonicity",
                "background_boundary",
                "mobile_composition",
            },
        )
        for check_name in ("silhouette_dimensions", "root_spread", "mobile_composition"):
            self.assertFalse(report["checks"][check_name]["pass"], check_name)
        self.assertTrue(report["manualReviewRequired"])

    def test_reference_shaped_growth_passes_the_automatic_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            stages, browser = create_reference_shaped_inputs(Path(temp_dir))

            result = self.run_validator(stages, browser)

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            report = json.loads(result.stdout)
            self.assertTrue(report["pass"])
            self.assertTrue(all(check["pass"] for check in report["checks"].values()))

    def test_internal_rectangular_boundary_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            stages, browser_path = create_reference_shaped_inputs(Path(temp_dir))
            browser = Image.open(browser_path).convert("RGB")
            ImageDraw.Draw(browser).rectangle(
                (45, 145, 385, 825), outline=(150, 150, 150), width=4
            )
            browser.save(browser_path)

            result = self.run_validator(stages, browser_path)

            self.assertEqual(result.returncode, 1, result.stderr or result.stdout)
            report = json.loads(result.stdout)
            self.assertFalse(report["checks"]["background_boundary"]["pass"])
            self.assertTrue(
                any(
                    item["code"] == "boundary_pollution"
                    for item in report["checks"]["background_boundary"]["failures"]
                )
            )

    def test_transparent_offline_stage_is_reported_as_boundary_pollution(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            stages, browser = create_reference_shaped_inputs(Path(temp_dir))
            first_stage = Image.open(stages[0]).convert("RGBA")
            alpha = Image.new("L", first_stage.size, 255)
            ImageDraw.Draw(alpha).rectangle((0, 0, 12, first_stage.height), fill=0)
            first_stage.putalpha(alpha)
            first_stage.save(stages[0])

            result = self.run_validator(stages, browser)

            report = json.loads(result.stdout)
            self.assertFalse(report["checks"]["background_boundary"]["pass"])
            self.assertTrue(
                any(
                    item["code"] == "stage_transparency"
                    for item in report["checks"]["background_boundary"]["failures"]
                )
            )


if __name__ == "__main__":
    unittest.main()
