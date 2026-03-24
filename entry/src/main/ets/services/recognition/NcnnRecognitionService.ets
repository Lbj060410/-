/**
 * 代码指南：
 * 文件： services/recognition/NcnnRecognitionService.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/NcnnRecognitionService.ets
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap
import resourceManager from '@ohos.resourceManager'
import { videoStore } from '../../state/VideoStore'

import { IRecognitionService } from './RecognitionService'
import { BBoxNorm, RecognitionCoreResult } from './RecognitionResult'
import { getLibEntryLastError, resolveLibEntryApi } from './LibEntryBridge'

interface RawBox {
  cls: number
  score: number
  x: number
  y: number
  w: number
  h: number
}

export class NcnnRecognitionService implements IRecognitionService {
  readonly name: string = 'offline-ncnn'
  private readonly diagTag: string = 'ncnn-bridge-20260306'

  private readonly modelName: string
  private readonly labels: string[]
  private readonly confThresh: number
  private readonly nmsThresh: number
  private loaded: boolean = false

  constructor(modelName: string, labels: string[], confThresh: number = 0.3, nmsThresh: number = 0.6) {
    this.modelName = modelName
    this.labels = labels
    this.confThresh = confThresh
    this.nmsThresh = nmsThresh
  }

  async recognize(pm: PixelMap): Promise<RecognitionCoreResult> {
    const t0: number = Date.now()

    // barrier 模型在当前 OpenHarmony 3.2 设备上存在原生段错误风险；
    // 当 page2 显式切到 traffic-only 保守模式时，跳过 barrier 推理。
    if (this.modelName === 'barrier' && !videoStore.page2BarrierExperimentalEnabled) {
      return this.errorResult(t0, '[ncnn-bridge] barrier ncnn disabled by page2 model switch')
    }

    try {
      const ok: boolean = await this.ensureModelLoaded()
      if (!ok) {
        return this.errorResult(t0, `[${this.diagTag}] model load failed`)
      }
    } catch (e) {
      return this.errorResult(t0, `[${this.diagTag}] model load failed: ${e}`)
    }

    try {
      const info: image.ImageInfo = await pm.getImageInfo()
      const w: number = info.size.width
      const h: number = info.size.height
      const buf: ArrayBuffer = new ArrayBuffer(w * h * 4)
      await pm.readPixelsToBuffer(buf)

      const libentry = this.requireNative()
      const json: string = libentry.detectNcnn(this.modelName, buf, w, h, this.confThresh, this.nmsThresh)
      const nativeErr: string = (typeof libentry.getLastError === 'function') ? String(libentry.getLastError()) : ''
      if (nativeErr.length > 0) {
        return this.errorResult(t0, `[${this.diagTag}] detect failed: ${nativeErr}`)
      }

      let rawBoxes: RawBox[]
      try {
        rawBoxes = JSON.parse(json) as RawBox[]
      } catch (e) {
        return this.errorResult(t0, `[${this.diagTag}] detect json parse failed: ${String(e)}`)
      }

      const postBoxes: RawBox[] = this.postprocessRawBoxes(rawBoxes)
      const boxes: BBoxNorm[] = postBoxes.map((b: RawBox): BBoxNorm => {
        const label: string = (b.cls >= 0 && b.cls < this.labels.length)
          ? this.labels[b.cls]
          : `cls${b.cls}`
        return {
          label: label,
          score: b.score,
          x: b.x - b.w * 0.5,
          y: b.y - b.h * 0.5,
          w: b.w,
          h: b.h
        }
      })

      return {
        tsMs: Date.now(),
        costMs: Date.now() - t0,
        engine: this.name,
        boxes: boxes,
        texts: [],
        ok: true,
        errorText: ''
      }
    } catch (e) {
      return this.errorResult(t0, `[${this.diagTag}] infer error: ${e}`)
    }
  }

  private postprocessRawBoxes(rawBoxes: RawBox[]): RawBox[] {
    const filtered: RawBox[] = []
    for (let i: number = 0; i < rawBoxes.length; i++) {
      const one: RawBox = rawBoxes[i]
      if (!Number.isFinite(one.score) || !Number.isFinite(one.x) || !Number.isFinite(one.y) ||
        !Number.isFinite(one.w) || !Number.isFinite(one.h)) {
        continue
      }
      if (one.w <= 0 || one.h <= 0) continue
      if (one.score < this.confThresh) continue
      filtered.push(one)
    }

    filtered.sort((a: RawBox, b: RawBox): number => b.score - a.score)

    const kept: RawBox[] = []
    for (let i: number = 0; i < filtered.length; i++) {
      const cur: RawBox = filtered[i]
      let dropped: boolean = false
      for (let j: number = 0; j < kept.length; j++) {
        const prev: RawBox = kept[j]
        if (prev.cls !== cur.cls) continue
        if (this.rawBoxIou(prev, cur) >= this.nmsThresh) {
          dropped = true
          break
        }
      }
      if (!dropped) kept.push(cur)
    }
    return kept
  }

  private rawBoxIou(a: RawBox, b: RawBox): number {
    const ax0: number = a.x - a.w * 0.5
    const ay0: number = a.y - a.h * 0.5
    const ax1: number = a.x + a.w * 0.5
    const ay1: number = a.y + a.h * 0.5

    const bx0: number = b.x - b.w * 0.5
    const by0: number = b.y - b.h * 0.5
    const bx1: number = b.x + b.w * 0.5
    const by1: number = b.y + b.h * 0.5

    const interW: number = Math.max(0, Math.min(ax1, bx1) - Math.max(ax0, bx0))
    const interH: number = Math.max(0, Math.min(ay1, by1) - Math.max(ay0, by0))
    if (interW <= 0 || interH <= 0) return 0

    const inter: number = interW * interH
    const union: number = Math.max(0, a.w * a.h) + Math.max(0, b.w * b.h) - inter
    if (union <= 0) return 0
    return inter / union
  }
  private async ensureModelLoaded(): Promise<boolean> {
    if (!this.loaded) {
      const ok: boolean = await this.loadModel()
      if (!ok) {
        return false
      }
      this.loaded = true
    }
    return true
  }

  private async loadModel(): Promise<boolean> {
    const ctx = globalThis.abilityContext as { resourceManager: resourceManager.ResourceManager }
    if (!ctx || !ctx.resourceManager) {
      throw new Error(`[${this.diagTag}] abilityContext.resourceManager missing`)
    }

    const rm: resourceManager.ResourceManager = ctx.resourceManager
    const paramFileName: string = `${this.modelName}.param`
    const binFileName: string = `${this.modelName}.bin`

    let paramBuf: ArrayBuffer
    try {
      const paramObj: Object = await this.getRawFileContentCompat(rm, paramFileName)
      paramBuf = this.toArrayBuffer(paramObj, paramFileName)
    } catch (e) {
      throw new Error(`[${this.diagTag}] getRawFileContent failed: ${paramFileName}, ${String(e)}`)
    }

    let binBuf: ArrayBuffer
    try {
      const binObj: Object = await this.getRawFileContentCompat(rm, binFileName)
      binBuf = this.toArrayBuffer(binObj, binFileName)
    } catch (e) {
      throw new Error(`[${this.diagTag}] getRawFileContent failed: ${binFileName}, ${String(e)}`)
    }

    const libentry = this.requireNative()
    const ok: boolean = libentry.loadNcnnModel(this.modelName, paramBuf, binBuf)
    if (!ok) {
      const nativeErr: string = (typeof libentry.getLastError === 'function') ? libentry.getLastError() : ''
      console.error(`NCNNLOAD|model=${this.modelName}|ok=0|param=${paramBuf.byteLength}|bin=${binBuf.byteLength}|err=${nativeErr.length > 0 ? nativeErr : '-'}`)
      throw new Error(`[${this.diagTag}] native loadNcnnModel false: ${this.modelName}, err=${nativeErr}`)
    }

    const nativeErr: string = (typeof libentry.getLastError === 'function') ? libentry.getLastError() : ''
    console.info(`NCNNLOAD|model=${this.modelName}|ok=1|param=${paramBuf.byteLength}|bin=${binBuf.byteLength}|${nativeErr}`)
    return true
  }

  private async getRawFileContentCompat(
    rm: resourceManager.ResourceManager,
    fileName: string
  ): Promise<Object> {
    const candidates: string[] = [fileName, `ncnn_models/${fileName}`]
    let lastErr: Object | string = ''

    for (const candidate of candidates) {
      try {
        return await rm.getRawFileContent(candidate)
      } catch (e) {
        lastErr = e
      }
    }

    throw new Error(`rawfile not found: ${candidates.join(' | ')}, last=${String(lastErr)}`)
  }

  private toArrayBuffer(dataObj: Object | undefined | null, fileName: string): ArrayBuffer {
    if (dataObj === undefined || dataObj === null) {
      throw new Error(`[${this.diagTag}] rawfile empty: ${fileName}`)
    }
    const maybeArrayBuffer = dataObj as ArrayBuffer
    if (maybeArrayBuffer instanceof ArrayBuffer) {
      return maybeArrayBuffer.slice(0)
    }

    const maybeBytes = dataObj as Uint8Array
    const rawObj = maybeBytes.buffer as Object | undefined
    if (rawObj) {
      const raw: ArrayBuffer = rawObj as ArrayBuffer
      const byteOffsetNum: number = Number(maybeBytes.byteOffset)
      const byteLengthNum: number = Number(maybeBytes.byteLength)
      if (Number.isFinite(byteOffsetNum) && Number.isFinite(byteLengthNum) && byteLengthNum > 0) {
        return raw.slice(byteOffsetNum, byteOffsetNum + byteLengthNum)
      }
    }

    const mapObj = dataObj as Record<string, Object>
    const nestedData: Object | undefined = mapObj['data']
    if (nestedData !== undefined) {
      return this.toArrayBuffer(nestedData, fileName)
    }

    const keys: string[] = Object.keys(mapObj)
    throw new Error(`[${this.diagTag}] invalid rawfile content: ${fileName}, keys=${keys.join(',')}`)
  }

  private requireNative(): {
    loadNcnnModel: (name: string, paramBuf: ArrayBuffer, binBuf: ArrayBuffer) => boolean
    detectNcnn: (name: string, rgba: ArrayBuffer, w: number, h: number, conf: number, nms: number) => string
    getLastError?: () => string
  } {
    const api = resolveLibEntryApi()
    const loadNcnnModel = api?.loadNcnnModel
    const detectNcnn = api?.detectNcnn
    if (typeof loadNcnnModel === 'function' && typeof detectNcnn === 'function') {
      return {
        loadNcnnModel,
        detectNcnn,
        getLastError: api?.getLastError
      }
    }
    const err: string = getLibEntryLastError()
    throw new Error(`native ncnn api unavailable: ${err}`)
  }

  private errorResult(t0: number, msg: string): RecognitionCoreResult {
    return {
      tsMs: Date.now(),
      costMs: Date.now() - t0,
      engine: this.name,
      boxes: [],
      texts: [],
      ok: false,
      errorText: msg
    }
  }
}

