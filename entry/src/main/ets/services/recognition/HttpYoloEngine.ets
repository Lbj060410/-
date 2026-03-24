/**
 * 代码指南：
 * 文件： services/recognition/HttpYoloEngine.ets
 * 用途： Recognition pipeline (engine abstraction, scheduling, result conversion/report).
 * 何时修改： adding/removing model backends, task rules, or inference scheduling.
 * 相关文件： state/RecogStore.ets, services/source/*, pages that display recognition output.
 */
// entry/src/main/ets/services/recognition/HttpYoloEngine.ets
import http from '@ohos.net.http'
import { BBoxNorm, RecognitionCoreResult } from './RecognitionResult'

interface YoloHttpResponseShape {
  boxes?: Array<BBoxNorm>
  costMs?: number
}

export class HttpYoloEngine {
  readonly name: string = 'yolo-http'
  private readonly endpoint: string

  constructor(endpoint: string) {
    this.endpoint = endpoint
  }

  async detectJpeg(jpeg: ArrayBuffer): Promise<RecognitionCoreResult> {
    const t0: number = Date.now()
    const client: http.HttpRequest = http.createHttp()

    try {
      const resp: http.HttpResponse = await client.request(this.endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'image/jpeg'
        },
        extraData: jpeg,
        connectTimeout: 5000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      })

      if (resp.responseCode !== 200) {
        const msg: string = `http code=${resp.responseCode}`
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

      const text: string = resp.result as string
      const parsed: YoloHttpResponseShape = this.safeParse(text)

      const boxes: Array<BBoxNorm> = Array.isArray(parsed.boxes) ? parsed.boxes : []
      const costMs: number = (typeof parsed.costMs === 'number') ? parsed.costMs : (Date.now() - t0)

      return {
        tsMs: Date.now(),
        costMs,
        engine: this.name,
        boxes,
        texts: [],
        ok: true,
        errorText: ''
      }
    } catch (e) {
      let msg: string = 'http yolo failed'
      if (e instanceof Error) {
        msg = e.message
      } else if (typeof e === 'object' && e !== null) {
        const be = e as Record<string, Object>
        msg = `code=${be['code']} msg=${be['message']}`
      }
      return {
        tsMs: Date.now(),
        costMs: Date.now() - t0,
        engine: this.name,
        boxes: [],
        texts: [],
        ok: false,
        errorText: this.trim(msg, 140)
      }
    } finally {
      try { client.destroy() } catch (e) {}
    }
  }

  private safeParse(text: string): YoloHttpResponseShape {
    try {
      const obj: object = JSON.parse(text) as object
      const shaped: YoloHttpResponseShape = obj as YoloHttpResponseShape
      return shaped
    } catch (e) {
      const empty: YoloHttpResponseShape = {}
      return empty
    }
  }

  private trim(s: string, maxLen: number): string {
    if (s.length <= maxLen) return s
    return s.substring(0, maxLen)
  }
}
