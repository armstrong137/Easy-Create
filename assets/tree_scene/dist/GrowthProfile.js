const AGE_STOPS = Object.freeze([0.08, 0.25, 0.48, 0.72, 1]);
const HEIGHT_RATIOS = Object.freeze([0.20, 0.38, 0.59, 0.80, 1.0]);
const RADIAL_RATIOS = Object.freeze([0.06, 0.19, 0.43, 0.72, 1.0]);

function interpolateProfile(age, values) {
  const value = Math.min(1, Math.max(0, Number(age) || 0));
  if (value <= AGE_STOPS[0]) return values[0];
  for (let index = 0; index < AGE_STOPS.length - 1; index += 1) {
    const lower = AGE_STOPS[index];
    const upper = AGE_STOPS[index + 1];
    if (value <= upper) {
      const mix = (value - lower) / (upper - lower);
      return values[index] + (values[index + 1] - values[index]) * mix;
    }
  }
  return values.at(-1);
}

export function heightRatioForAge(age) {
  return interpolateProfile(age, HEIGHT_RATIOS);
}

export function radialRatioForAge(age) {
  return interpolateProfile(age, RADIAL_RATIOS);
}
