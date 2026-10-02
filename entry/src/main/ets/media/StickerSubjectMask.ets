/** Native alpha values belong to the complete, already oriented processing input. */
export function copySubjectMask(native: Int32Array, width: number, height: number): Uint8Array {
  const length = width * height;
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 ||
    !Number.isSafeInteger(length) || native === undefined || native === null || native.length !== length) {
    return new Uint8Array(0);
  }
  const mask = new Uint8Array(length);
  let visible = false;
  for (let index = 0; index < length; index++) {
    const value = native[index];
    if (!Number.isInteger(value) || value < 0 || value > 255) { return new Uint8Array(0); }
    mask[index] = value;
    if (value > 0) { visible = true; }
  }
  // A close-up or a soft edge is valid alpha; only a truly empty result is unusable.
  return visible ? mask : new Uint8Array(0);
}

/** Per-pixel maximum unions candidates without rescaling or inventing an opaque background. */
export function mergeSubjectMasks(masks: Uint8Array[], width: number, height: number): Uint8Array {
  const length = width * height;
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 ||
    !Number.isSafeInteger(length) || masks.length === 0) { return new Uint8Array(0); }
  const union = new Uint8Array(length);
  let visible = false;
  for (const mask of masks) {
    if (mask === undefined || mask === null || mask.length !== length) { return new Uint8Array(0); }
    for (let index = 0; index < length; index++) {
      if (mask[index] > union[index]) { union[index] = mask[index]; }
      if (union[index] > 0) { visible = true; }
    }
  }
  return visible ? union : new Uint8Array(0);
}
