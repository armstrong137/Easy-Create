from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = PROJECT_ROOT / "scripts" / "validate_magic_tree_art_package.py"

REFERENCE_SIZES = {
    "树形正视图.png": (1024, 1400),
    "树形侧视图.png": (1024, 1400),
    "建模母版-成熟树四视图.png": (1600, 900),
    "五阶段成长分镜.png": (1600, 900),
    "建模母版-五阶段侧视图.png": (1600, 900),
    "章节枝六阶段分镜.png": (1600, 900),
    "材质母版-PBR细节.png": (1500, 900),
    "左右分区交互效果图.png": (900, 1400),
    "树龄与浏览解耦对照图.png": (1600, 900),
    "章节目枝直接承托效果图.png": (900, 1400),
}


def create_valid_package(root: Path) -> None:
    references = root / "references"
    textures = root / "textures_source"
    licenses = root / "licenses"
    references.mkdir(parents=True)
    textures.mkdir(parents=True)
    licenses.mkdir(parents=True)

    for name, size in REFERENCE_SIZES.items():
        Image.new("RGB", size, (253, 246, 236)).save(references / name)

    Image.new("RGB", (1024, 1024), (72, 55, 43)).save(
        textures / "bark_old_basecolor_source.png"
    )
    Image.new("RGB", (1024, 1024), (48, 39, 31)).save(
        textures / "soil_basecolor_source.png"
    )

    leaf = Image.new("RGBA", (1024, 768), (45, 83, 28, 0))
    for x in range(256, 768):
        for y in range(192, 576):
            leaf.putpixel((x, y), (45, 83, 28, 255))
    leaf.save(textures / "leaf_atlas_rgba.png")

    (root / "README.md").write_text("# 魔树美术资产\n", encoding="utf-8")
    (licenses / "ASSET_LICENSES.md").write_text(
        "# 授权清单\n", encoding="utf-8"
    )


class ValidateMagicTreeArtPackageTest(unittest.TestCase):
    def run_validator(self, root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(VALIDATOR), "--root", str(root), "--json"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )

    def test_complete_high_resolution_package_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            create_valid_package(root)

            result = self.run_validator(root)

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            report = json.loads(result.stdout)
            self.assertTrue(report["pass"])
            self.assertEqual(report["errors"], [])

    def test_low_resolution_front_view_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            create_valid_package(root)
            Image.new("RGB", (640, 800), (253, 246, 236)).save(
                root / "references" / "树形正视图.png"
            )

            result = self.run_validator(root)

            self.assertEqual(result.returncode, 1)
            report = json.loads(result.stdout)
            self.assertFalse(report["pass"])
            self.assertTrue(
                any(error["code"] == "min_size" for error in report["errors"])
            )


if __name__ == "__main__":
    unittest.main()
