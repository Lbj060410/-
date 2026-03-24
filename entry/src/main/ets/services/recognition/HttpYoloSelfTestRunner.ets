/**
 * 代码指南：
 * 文件： services/recognition/HttpYoloSelfTestRunner.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
 */
// entry/src/main/ets/services/recognition/HttpYoloSelfTestRunner.ets
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap

import { recogStore } from '../../state/RecogStore'
import { videoStore } from '../../state/VideoStore'
import { RecognitionFactory } from './RecognitionFactory'
import { RecogEngineType } from './RecognitionConfig'
import { RecognitionCoreResult, RecognitionResult } from './RecognitionResult'
import { RecogStatus } from './RecognitionResult'
import { RecognitionTaskKind, RecognitionTaskSource, RecognitionSubtype } from './RecognitionTask'
import { IRecognitionService } from './RecognitionService'

export class HttpYoloSelfTestRunner {
  private running: boolean = false
  private timerId: number = -1
  private inFlight: boolean = false

  private cachedPm?: PixelMap
  private svc?: IRecognitionService

  start(): void {
    this.stop()

    // 仅在选择 http-yolo 时开启自检
    recogStore.setRecogText(`selftest check: engine=${recogStore.recogEngineType} endpointLen=${recogStore.recogHttpEndpoint.length}`)

    if (recogStore.recogEngineType !== RecogEngineType.HTTP_YOLO) {
      recogStore.setRecogText('selftest not started: engineType != HTTP_YOLO')
      return
    }
    if (recogStore.recogHttpEndpoint.trim().length <= 0) {
      recogStore.setRecogText('selftest not started: endpoint empty')
      return
    }

    const factory: RecognitionFactory = new RecognitionFactory()
    this.svc = factory.create({ engineType: RecogEngineType.HTTP_YOLO, httpEndpoint: recogStore.recogHttpEndpoint, offlineModelName: '', offlineConfThresh: 0.4 })

    this.running = true
    recogStore.setRecogStatus(RecogStatus.RUNNING)
    recogStore.setRecogText('http-yolo selftest started')

    this.timerId = setInterval((): void => {
      void this.tick()
    }, 2000) as number
  }

  stop(): void {
    this.running = false
    if (this.timerId >= 0) {
      try { clearInterval(this.timerId) } catch (e) {}
      this.timerId = -1
    }
    this.inFlight = false
    this.svc = undefined
  }

  private async tick(): Promise<void> {
    if (!this.running) return
    if (this.inFlight) return

    if (!videoStore.recognitionEnabled) {
      recogStore.setRecogText('http-yolo selftest paused: recognitionEnabled=false')
      return
    }

    // 有真实 live 画面时，不抢占（只检查 livePixelMap，避免失败帧误判）
    if (videoStore.livePixelMap) {
      recogStore.setRecogText('http-yolo selftest idle: live frame active')
      return
    }

    const svc: IRecognitionService | undefined = this.svc
    if (!svc) {
      recogStore.setRecogText('http-yolo selftest fail: service undefined')
      return
    }

    this.inFlight = true
    try {
      recogStore.setRecogText('http-yolo selftest: sending...')
      const pm: PixelMap = await this.getOrCreateSelfTestPixelMap()

      const core: RecognitionCoreResult = await svc.recognize(pm)
      const wrapped: RecognitionResult = this.wrapSelfTestResult(core)

      // 仅用于面板观测：写入 lastRecog
      recogStore.setRecogResult(wrapped)

      if (wrapped.ok) {
        recogStore.setRecogStatus(RecogStatus.RUNNING)
        recogStore.setRecogText(`${wrapped.engine} selftest ok boxes=${wrapped.boxes.length} cost=${wrapped.costMs}ms`)
      } else {
        recogStore.setRecogStatus(RecogStatus.ERROR)
        recogStore.setRecogText(wrapped.errorText)
      }
    } catch (e) {
      let msg: string
      try {
        msg = JSON.stringify(e)
      } catch {
        msg = String(e)
      }
      recogStore.setRecogStatus(RecogStatus.ERROR)
      recogStore.setRecogText(`ERR:${msg}`)
    } finally {
      this.inFlight = false
    }
  }

  private wrapSelfTestResult(core: RecognitionCoreResult): RecognitionResult {
    return {
      taskId: `selftest-${Date.now()}`,
      kind: RecognitionTaskKind.SNAPSHOT,
      subtype: RecognitionSubtype.YOLO,
      source: RecognitionTaskSource.PAGE2_BUTTON,
      tsMs: core.tsMs,
      costMs: core.costMs,
      engine: core.engine,
      boxes: core.boxes,
      texts: core.texts,
      ok: core.ok,
      errorText: core.errorText
    }
  }

  private async getOrCreateSelfTestPixelMap(): Promise<PixelMap> {
    if (this.cachedPm) return this.cachedPm

    // 创建一个 4x4 纯色 PixelMap（RGBA_8888，每像素4字节）
    const w: number = 4
    const h: number = 4
    const buf: ArrayBuffer = new ArrayBuffer(w * h * 4)
    const view: Uint8Array = new Uint8Array(buf)
    for (let i: number = 0; i < view.length; i += 4) {
      view[i] = 128     // R
      view[i + 1] = 128 // G
      view[i + 2] = 128 // B
      view[i + 3] = 255 // A
    }
    const opts: image.InitializationOptions = {
      size: { width: w, height: h },
      pixelFormat: image.PixelMapFormat.RGBA_8888
    }
    const pm: PixelMap = await image.createPixelMap(buf, opts)
    this.cachedPm = pm
    return pm
  }
}

