import taskpool from '@ohos.taskpool'
import image from '@ohos.multimedia.image'
import { bengkuiMasterError } from './BengkuiMasterLogger'

export interface JpegDecodeRgbaResult {
  ok: boolean
  width: number
  height: number
  rgba?: ArrayBuffer
}

interface RawBoxLite {
  cls: number
  score: number
  x: number
  y: number
  w: number
  h: number
}

@Concurrent
function validateJpegBufferTask(data: ArrayBuffer): boolean {
  if (!(data instanceof ArrayBuffer)) return false
  const bytes: Uint8Array = new Uint8Array(data)
  const n: number = bytes.length
  if (n < 4) return false

  // SOI marker: FF D8
  if ((bytes[0] & 0xff) !== 0xff || (bytes[1] & 0xff) !== 0xd8) return false
  // EOI marker: FF D9
  if ((bytes[n - 2] & 0xff) !== 0xff || (bytes[n - 1] & 0xff) !== 0xd9) return false

  return true
}

@Concurrent
function parseAndPostprocessNcnnBoxesTask(json: string, confThresh: number, nmsThresh: number): Array<RawBoxLite> {
  let rawBoxes: Array<RawBoxLite> = []
  try {
    const parsed: Object = JSON.parse(json) as Object
    if (Array.isArray(parsed)) {
      rawBoxes = parsed as Array<RawBoxLite>
    } else {
      return []
    }
  } catch (_) {
    return []
  }

  const filtered: Array<RawBoxLite> = []
  for (let i: number = 0; i < rawBoxes.length; i++) {
    const one: RawBoxLite = rawBoxes[i]
    if (!Number.isFinite(one.score) || !Number.isFinite(one.x) || !Number.isFinite(one.y) ||
      !Number.isFinite(one.w) || !Number.isFinite(one.h)) {
      continue
    }
    if (one.w <= 0 || one.h <= 0) continue
    if (one.score < confThresh) continue
    filtered.push(one)
  }

  filtered.sort((a: RawBoxLite, b: RawBoxLite): number => b.score - a.score)

  const kept: Array<RawBoxLite> = []
  for (let i: number = 0; i < filtered.length; i++) {
    const cur: RawBoxLite = filtered[i]
    let dropped: boolean = false
    for (let j: number = 0; j < kept.length; j++) {
      const prev: RawBoxLite = kept[j]
      if (prev.cls !== cur.cls) continue
      const ax0: number = prev.x - prev.w * 0.5
      const ay0: number = prev.y - prev.h * 0.5
      const ax1: number = prev.x + prev.w * 0.5
      const ay1: number = prev.y + prev.h * 0.5
      const bx0: number = cur.x - cur.w * 0.5
      const by0: number = cur.y - cur.h * 0.5
      const bx1: number = cur.x + cur.w * 0.5
      const by1: number = cur.y + cur.h * 0.5
      const interW: number = Math.max(0, Math.min(ax1, bx1) - Math.max(ax0, bx0))
      const interH: number = Math.max(0, Math.min(ay1, by1) - Math.max(ay0, by0))
      if (interW <= 0 || interH <= 0) continue
      const inter: number = interW * interH
      const union: number = Math.max(0, prev.w * prev.h) + Math.max(0, cur.w * cur.h) - inter
      const iou: number = union > 0 ? (inter / union) : 0
      if (iou >= nmsThresh) {
        dropped = true
        break
      }
    }
    if (!dropped) kept.push(cur)
  }
  return kept
}

@Concurrent
async function decodeJpegToRgbaTask(jpeg: ArrayBuffer): Promise<JpegDecodeRgbaResult> {
  if (!(jpeg instanceof ArrayBuffer) || jpeg.byteLength <= 0) {
    return { ok: false, width: 0, height: 0 }
  }

  let src: image.ImageSource | undefined = undefined
  let pm: image.PixelMap | undefined = undefined
  try {
    src = image.createImageSource(jpeg)
    pm = await src.createPixelMap()
    const info: image.ImageInfo = await pm.getImageInfo()
    const w: number = Math.max(0, Math.trunc(info.size.width))
    const h: number = Math.max(0, Math.trunc(info.size.height))
    if (w <= 0 || h <= 0) {
      return { ok: false, width: 0, height: 0 }
    }
    const rgba: ArrayBuffer = new ArrayBuffer(w * h * 4)
    await pm.readPixelsToBuffer(rgba)
    return { ok: true, width: w, height: h, rgba }
  } catch (_) {
    return { ok: false, width: 0, height: 0 }
  } finally {
    if (pm) {
      try { pm.release() } catch (_) {}
    }
    if (src) {
      try { src.release() } catch (_) {}
    }
  }
}

export async function validateJpegBuffer(data: ArrayBuffer): Promise<boolean> {
  try {
    const task: taskpool.Task = new taskpool.Task(validateJpegBufferTask, data)
    const ok: boolean = await taskpool.execute(task) as boolean
    return !!ok
  } catch (e) {
    bengkuiMasterError('BackgroundCompute.validateJpegBuffer.taskpool.execute', e, `bytes=${data.byteLength}`)
    return false
  }
}

export async function parseAndPostprocessNcnnBoxes(
  json: string,
  confThresh: number,
  nmsThresh: number
): Promise<Array<RawBoxLite>> {
  try {
    const task: taskpool.Task = new taskpool.Task(parseAndPostprocessNcnnBoxesTask, json, confThresh, nmsThresh)
    const out: Array<RawBoxLite> = await taskpool.execute(task) as Array<RawBoxLite>
    return Array.isArray(out) ? out : []
  } catch (e) {
    bengkuiMasterError(
      'BackgroundCompute.parseAndPostprocessNcnnBoxes.taskpool.execute',
      e,
      `jsonLen=${json.length},conf=${confThresh},nms=${nmsThresh}`
    )
    return []
  }
}

export async function decodeJpegToRgba(jpeg: ArrayBuffer): Promise<JpegDecodeRgbaResult> {
  try {
    const task: taskpool.Task = new taskpool.Task(decodeJpegToRgbaTask, jpeg)
    const out: JpegDecodeRgbaResult = await taskpool.execute(task) as JpegDecodeRgbaResult
    if (!out || out.ok !== true || !out.rgba) {
      return { ok: false, width: 0, height: 0 }
    }
    return out
  } catch (e) {
    bengkuiMasterError('BackgroundCompute.decodeJpegToRgba.taskpool.execute', e, `bytes=${jpeg.byteLength}`)
    return { ok: false, width: 0, height: 0 }
  }
}
