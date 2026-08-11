import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createStartupErrorPayload,
  detectWebGL2Availability,
  startupStages,
} from '../src/StartupDiagnostics.js';

test('启动阶段名称与 Flutter 协议保持一致', () => {
  assert.deepEqual(startupStages, [
    'iframeLoading',
    'webglCreating',
    'modelLoading',
    'firstFrame',
    'ready',
    'failed',
    'timedOut',
  ]);
});

test('启动错误包含定位浏览器空白所需的完整信息', () => {
  const payload = createStartupErrorPayload({
    stage: 'modelLoading',
    error: new Error('model 404'),
    webgl2Available: false,
    userAgent: 'test-browser',
    modelUrl: '/magic_tree.glb',
  });

  assert.deepEqual(payload, {
    stage: 'modelLoading',
    message: 'Error: model 404',
    webgl2Available: false,
    userAgent: 'test-browser',
    modelUrl: '/magic_tree.glb',
  });
});

test('WebGL2 可用性以实际上下文创建结果为准', () => {
  assert.equal(detectWebGL2Availability(() => ({ getContext: () => null })), false);
  assert.equal(
    detectWebGL2Availability(() => ({ getContext: () => ({ version: 2 }) })),
    true,
  );
});
