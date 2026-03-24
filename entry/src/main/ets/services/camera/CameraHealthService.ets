/**
 * 代码指南：
 * 文件： services/camera/CameraHealthService.ets
 * 用途： Camera device discovery/health/http service integrations.
 * 何时修改： camera source config, detection, or request handling changes.
 * 相关文件： pages/page2/* and services/source/*.
 */
export type HealthState = 'ONLINE' | 'DEGRADED' | 'OFFLINE'

export interface HealthInfo {
  state: HealthState
  consecutiveFail: number
  lastOkAtMs: number
  lastFailAtMs: number
  suggestionIntervalMs: number
  tip: string
}

export class CameraHealthService {
  private consecutiveFail: number = 0
  private lastOkAtMs: number = 0
  private lastFailAtMs: number = 0

  private readonly degradedThreshold: number = 5
  private readonly offlineThreshold: number = 15

  onOk(): HealthInfo {
    this.consecutiveFail = 0
    this.lastOkAtMs = Date.now()
    return this.build()
  }

  onFail(): HealthInfo {
    this.consecutiveFail += 1
    this.lastFailAtMs = Date.now()
    return this.build()
  }

  getInfo(): HealthInfo {
    return this.build()
  }

  private build(): HealthInfo {
    let state: HealthState = 'ONLINE'
    let interval: number = 200
    let tip: string = '摄像头在线'

    if (this.consecutiveFail >= this.offlineThreshold) {
      state = 'OFFLINE'
      interval = 1200
      tip = '摄像头离线：降低请求频率，等待恢复'
    } else if (this.consecutiveFail >= this.degradedThreshold) {
      state = 'DEGRADED'
      interval = 500
      tip = '网络不稳：降频运行（稳定优先）'
    }

    return {
      state,
      consecutiveFail: this.consecutiveFail,
      lastOkAtMs: this.lastOkAtMs,
      lastFailAtMs: this.lastFailAtMs,
      suggestionIntervalMs: interval,
      tip
    }
  }
}
