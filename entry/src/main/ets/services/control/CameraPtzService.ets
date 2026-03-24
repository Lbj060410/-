/**
 * 代码指南：
 * 文件： services/control/CameraPtzService.ets
 * 用途： 用于摄像头方向/变焦控制的云台（PTZ）指令接口。
 * 何时修改： 新增云台操作或修改控制接口映射时。
 * 相关文件： pages/page2/components/PtzControlPanel.ets 及摄像头相关服务。
 */
import http from '@ohos.net.http'

export interface PtzResult {
  ok: boolean
  costMs: number
  message: string
}

export class CameraPtzService {
  private queue: Promise<void> = Promise.resolve()

  reset(): void {
    this.queue = Promise.resolve()
  }

  async moveOnce(cameraHost: string, user: string, pass: string, command: number, onestep: number): Promise<PtzResult> {
    let result: PtzResult = { ok: false, costMs: 0, message: 'PTZ not executed' }

    this.queue = this.queue.then(async () => {
      const t0: number = Date.now()
      const url: string = this.buildUrl(cameraHost, user, pass, command, onestep)
      const client: http.HttpRequest = http.createHttp()
      try {
        await client.request(url, {
          method: http.RequestMethod.GET,
          connectTimeout: 3000,
          readTimeout: 3000,
          expectDataType: http.HttpDataType.STRING
        })
        result = { ok: true, costMs: Date.now() - t0, message: `PTZ OK cmd=${command}` }
      } catch (e) {
        result = { ok: false, costMs: Date.now() - t0, message: `PTZ FAIL cmd=${command}` }
      } finally {
        try { client.destroy() } catch (e) {}
      }
    })

    await this.queue
    return result
  }

  private buildUrl(cameraHost: string, user: string, pass: string, command: number, onestep: number): string {
    const parts: Array<string> = []
    const u: string = user.trim()
    const p: string = pass.trim()
    if (u.length > 0) parts.push(`loginuse=${encodeURIComponent(u)}`)
    if (p.length > 0) parts.push(`loginpas=${encodeURIComponent(p)}`)
    parts.push(`command=${command}`)
    parts.push(`onestep=${onestep}`)
    return `http://${cameraHost}/decoder_control.cgi?${parts.join('&')}`
  }
  async up(cameraHost: string, user: string, pass: string): Promise<PtzResult> { return await this.moveOnce(cameraHost, user, pass, 0, 1) }
  async down(cameraHost: string, user: string, pass: string): Promise<PtzResult> { return await this.moveOnce(cameraHost, user, pass, 2, 1) }
  async left(cameraHost: string, user: string, pass: string): Promise<PtzResult> { return await this.moveOnce(cameraHost, user, pass, 4, 1) }
  async right(cameraHost: string, user: string, pass: string): Promise<PtzResult> { return await this.moveOnce(cameraHost, user, pass, 6, 1) }

  async preset(cameraHost: string, user: string, pass: string, command: number): Promise<PtzResult> {
    return await this.moveOnce(cameraHost, user, pass, command, 0)
  }

  async rotate180(cameraHost: string, user: string, pass: string): Promise<PtzResult> {
    // ʹ��Ԥ��λ38��ʵ��180����ת���밲׿�˵�Y4��ť��Ӧ��
    // �������ͷ֧��Ԥ��λ�������ȷ�ķ�ʽ
    return await this.moveOnce(cameraHost, user, pass, 38, 0)
  }
}

