/**
 * 代码指南：
 * 文件： services/camera/CameraDiscoveryService.ets
 * 用途： Camera device discovery/health/http service integrations.
 * 何时修改： camera source config, detection, or request handling changes.
 * 相关文件： pages/page2/* and services/source/*.
 */
import socket from '@ohos.net.socket'

export class CameraDiscoveryService {
  private readonly localPort: number = 3565
  private readonly serverPort: number = 8600
  private readonly broadcastIp: string = '255.255.255.255'
  private readonly probePayload: Uint8Array = new Uint8Array([68, 72, 1, 1])

  private parseCameraIpFromDhPacket(buf: ArrayBuffer): string | undefined {
    const u8: Uint8Array = new Uint8Array(buf)
    if (u8.length < 2) return undefined
    if (u8[0] !== 68 || u8[1] !== 72) return undefined

    let ip: string = ''
    for (let i: number = 4; i < 22 && i < u8.length; i++) {
      const b: number = u8[i]
      if (b === 0) break
      if (b === 46) ip += '.'
      else if (b >= 48 && b <= 57) ip += String.fromCharCode(b)
    }
    return ip.length > 0 ? ip : undefined
  }

  async discoverCameraIp(timeoutMs: number): Promise<string | undefined> {
    const deadline: number = Date.now() + timeoutMs
    const retryIntervalMs: number = 800

    while (Date.now() < deadline) {
      const remaining: number = deadline - Date.now()
      const oneTryTimeout: number = remaining > retryIntervalMs ? retryIntervalMs : remaining

      const ip: string | undefined = await this.tryOnce(oneTryTimeout)
      if (ip) return ip

      await this.sleep(50)
    }
    return undefined
  }

  private async tryOnce(waitMs: number): Promise<string | undefined> {
    const udp: socket.UDPSocket = socket.constructUDPSocketInstance()
    let resolved: boolean = false

    try {
      await udp.bind({ address: '0.0.0.0', port: this.localPort })

      const ipPromise: Promise<string | undefined> = new Promise((resolve) => {
        const timerId: number = setTimeout(() => {
          if (resolved) return
          resolved = true
          resolve(undefined)
        }, waitMs)

        udp.on('message', (msg: { message: ArrayBuffer }) => {
          if (resolved) return
          const ip: string | undefined = this.parseCameraIpFromDhPacket(msg.message)
          if (ip) {
            resolved = true
            clearTimeout(timerId)
            resolve(ip)
          }
        })
      })

      await udp.send({
        data: this.probePayload.buffer,
        address: { address: this.broadcastIp, port: this.serverPort }
      })

      const ip: string | undefined = await ipPromise
      return ip
    } catch (e) {
      console.error('CameraDiscovery tryOnce failed')
      return undefined
    } finally {
      try { await udp.close() } catch (e) {}
    }
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => setTimeout(() => resolve(), ms))
  }
}
