import test from 'node:test';
import assert from 'node:assert/strict';

import { decodeCommand, PROTOCOL_VERSION } from '../src/protocol.js';

test('拒绝错误版本和缺少 sequence 的命令', () => {
  assert.equal(PROTOCOL_VERSION, 1);
  assert.throws(() => decodeCommand({ protocolVersion: 2, sequence: 1 }));
  assert.throws(() => decodeCommand({ protocolVersion: 1 }));
});

test('接受带会话、序号和命令类型的合法命令', () => {
  const command = decodeCommand({
    protocolVersion: 1,
    sceneSessionId: 'scene-1',
    sequence: 3,
    type: 'scene.sync',
    payload: { chapters: [] },
  });

  assert.equal(command.sceneSessionId, 'scene-1');
  assert.equal(command.sequence, 3);
  assert.equal(command.type, 'scene.sync');
});
