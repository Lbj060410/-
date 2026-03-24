export const add: (a: number, b: number) => number;
export const loadModel: (name: string, buf: ArrayBuffer) => boolean;
export const detectOffline: (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number) => string;
export const detectPlate: (
  detModelName: string,
  recModelName: string,
  rgba: ArrayBuffer,
  w: number,
  h: number,
  conf: number
) => string;
export const decodeQr: (rgba: ArrayBuffer, w: number, h: number) => string;
export const encodeGbk: (text: string) => ArrayBuffer;
