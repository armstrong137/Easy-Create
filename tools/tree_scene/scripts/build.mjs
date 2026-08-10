import { cp, mkdir, rm } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = resolve(toolRoot, '..', '..');
const outputRoot = resolve(repoRoot, 'assets', 'tree_scene');

const copies = [
  ['src', 'dist'],
  ['node_modules/three/build/three.module.js', 'vendor/three.module.js'],
  ['node_modules/three/build/three.core.js', 'vendor/three.core.js'],
  ['node_modules/three/examples/jsm/loaders/GLTFLoader.js', 'vendor/addons/loaders/GLTFLoader.js'],
  ['node_modules/three/examples/jsm/loaders/KTX2Loader.js', 'vendor/addons/loaders/KTX2Loader.js'],
  ['node_modules/three/examples/jsm/utils/BufferGeometryUtils.js', 'vendor/addons/utils/BufferGeometryUtils.js'],
  ['node_modules/three/examples/jsm/utils/SkeletonUtils.js', 'vendor/addons/utils/SkeletonUtils.js'],
  ['node_modules/three/examples/jsm/utils/WorkerPool.js', 'vendor/addons/utils/WorkerPool.js'],
  ['node_modules/three/examples/jsm/math/ColorSpaces.js', 'vendor/addons/math/ColorSpaces.js'],
  ['node_modules/three/examples/jsm/libs/ktx-parse.module.js', 'vendor/addons/libs/ktx-parse.module.js'],
  ['node_modules/three/examples/jsm/libs/meshopt_decoder.module.js', 'vendor/addons/libs/meshopt_decoder.module.js'],
  ['node_modules/three/examples/jsm/libs/zstddec.module.js', 'vendor/addons/libs/zstddec.module.js'],
  ['node_modules/three/examples/jsm/libs/basis', 'vendor/addons/libs/basis'],
];

await rm(resolve(outputRoot, 'dist'), { recursive: true, force: true });
await rm(resolve(outputRoot, 'vendor'), { recursive: true, force: true });

for (const [source, target] of copies) {
  const sourcePath = resolve(toolRoot, source);
  const targetPath = resolve(outputRoot, target);
  await mkdir(dirname(targetPath), { recursive: true });
  await cp(sourcePath, targetPath, { recursive: true });
}

console.log(`魔树场景构建完成：${outputRoot}`);
