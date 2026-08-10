export const PROTOCOL_VERSION = 1;

const requireInteger = (value, field) => {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new TypeError(`${field} 必须是非负安全整数`);
  }
};

const requireText = (value, field) => {
  if (typeof value !== 'string' || value.length === 0) {
    throw new TypeError(`${field} 必须是非空字符串`);
  }
};

export function decodeCommand(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new TypeError('场景命令必须是对象');
  }
  if (raw.protocolVersion !== PROTOCOL_VERSION) {
    throw new RangeError(`不支持的协议版本：${raw.protocolVersion}`);
  }

  requireInteger(raw.sequence, 'sequence');
  requireText(raw.sceneSessionId, 'sceneSessionId');
  requireText(raw.type, 'type');

  return Object.freeze({
    protocolVersion: PROTOCOL_VERSION,
    sceneSessionId: raw.sceneSessionId,
    sequence: raw.sequence,
    type: raw.type,
    payload: raw.payload ?? null,
  });
}

export function encodeEvent({ sceneSessionId, sequence, type, payload = null }) {
  requireInteger(sequence, 'sequence');
  requireText(sceneSessionId, 'sceneSessionId');
  requireText(type, 'type');
  return {
    protocolVersion: PROTOCOL_VERSION,
    sceneSessionId,
    sequence,
    type,
    payload,
  };
}
