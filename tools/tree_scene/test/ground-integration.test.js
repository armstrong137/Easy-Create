import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('runtime hides the finite soil disc and uses a seamless parchment ground', async () => {
  const source = await readFile(new URL('../src/MagicTreeScene.js', import.meta.url), 'utf8');
  assert.match(source, /ec_role === 'soil_mound'/);
  assert.match(source, /ec_role === 'moss_patches'/);
  assert.match(source, /GroundPlane/);
  assert.match(source, /ShadowMaterial/);
  assert.doesNotMatch(source, /ParchmentGround/);
  assert.doesNotMatch(source, /vein\.visible = treeAge >=/);
});

test('runtime branches inherit bark from the main-tree role group', async () => {
  const source = await readFile(new URL('../src/MagicTreeScene.js', import.meta.url), 'utf8');
  assert.match(source, /let mainTreeRole = null/);
  assert.match(source, /mainTreeRole\?\.traverse/);
});

test('the organic root flare remains visible as part of the approved ancient-tree silhouette', async () => {
  const source = await readFile(new URL('../src/MagicTreeScene.js', import.meta.url), 'utf8');
  assert.match(source, /ec_role === 'root_flare'/);
  assert.doesNotMatch(source, /rootRole\.visible = false/);
});

test('formal art build keeps the fine twigs that carry crown anchors', async () => {
  const source = await readFile(
    new URL('../../../scripts/build_magic_tree_art_asset.py', import.meta.url),
    'utf8',
  );
  assert.match(source, /evaluated_mesh\(source, branch_density=1\.0, leaf_density=0\.0\)/);
  assert.match(source, /HEIGHT_RATIOS = \(0\.20, 0\.38, 0\.59, 0\.80, 1\.0\)/);
  assert.match(source, /RADIAL_RATIOS = \(0\.06, 0\.19, 0\.43, 0\.72, 1\.0\)/);
  assert.match(source, /bpy\.ops\.file\.pack_all\(\)/);
  assert.match(source, /for material in materials\.values\(\):\s+darken_bark\(material\)/);
});

test('refinement keeps every trunk material under the same ancient-bark grade', async () => {
  const source = await readFile(
    new URL('../../../scripts/refine_magic_tree_blend.py', import.meta.url),
    'utf8',
  );
  assert.match(source, /def ensure_bark_tint/);
  assert.match(source, /for material in tree\.data\.materials/);
  assert.match(source, /def rebuild_organic_roots/);
  assert.match(source, /root_count = 7/);
  assert.match(source, /buttress_rings =/);
  assert.doesNotMatch(source, /bpy\.data\.objects\["Roots"\]\.hide_render = True/);
  assert.match(source, /def hide_flat_ground_artifact/);
  assert.match(source, /polygon\.center\.z < 0\.08/);
  assert.match(source, /--output-glb/);
  assert.match(source, /bpy\.ops\.export_scene\.gltf/);
});

test('stand-ins use the same seamless-ground, hidden-root and leaf-cluster composition', async () => {
  const source = await readFile(
    new URL('../../../scripts/render_magic_tree_art_previews.py', import.meta.url),
    'utf8',
  );
  assert.match(source, /bpy\.data\.objects\["Soil"\]\.hide_render = True/);
  assert.match(source, /bpy\.data\.objects\["MossPatches"\]\.hide_render = True/);
  assert.doesNotMatch(source, /bpy\.data\.objects\["Roots"\]\.hide_render = True/);
  assert.match(source, /for cluster_index in range\(5\)/);
  assert.match(source, /anchor_index >= 42 and \(anchor_index \* 37\) % 100 >= 65/);
  assert.match(source, /material\.name\.startswith\("LeafBroadPBR"\)/);
});
