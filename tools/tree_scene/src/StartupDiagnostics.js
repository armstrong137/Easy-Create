export const startupStages = Object.freeze([
  'iframeLoading',
  'webglCreating',
  'modelLoading',
  'firstFrame',
  'ready',
  'failed',
  'timedOut',
]);

export function detectWebGL2Availability(
  createCanvas = () => document.createElement('canvas'),
) {
  try {
    return Boolean(createCanvas()?.getContext?.('webgl2'));
  } catch (_) {
    return false;
  }
}

export function createStartupErrorPayload({
  stage,
  error,
  webgl2Available,
  userAgent,
  modelUrl,
}) {
  return {
    stage,
    message: String(error),
    webgl2Available: Boolean(webgl2Available),
    userAgent: String(userAgent ?? ''),
    modelUrl: String(modelUrl ?? ''),
  };
}
