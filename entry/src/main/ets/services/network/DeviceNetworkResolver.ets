/**
 * 代码指南：
 * 文件： services/network/DeviceNetworkResolver.ets
 * 用途： Device/network environment resolver helpers.
 * 何时修改： gateway/ip detection strategy changes.
 * 相关文件： page coordinators that auto-fill target endpoints.
 */
import wifi from '@ohos.wifi'

import {
  CAR_CAMERA_HTTP_PORT,
  CAR_CAMERA_IP,
  CAR_DEVICE_IP,
  CAR_RTSP_PORT,
  defaultCameraHost,
  defaultRtspUrl
} from '../../config/DeviceNetworkConfig'
import { CameraDiscoveryService } from '../camera/CameraDiscoveryService'

interface WifiIpInfoLike {
  ipAddress?: number
  gateway?: number
}

export class DeviceNetworkResolver {
  private readonly cameraDiscovery: CameraDiscoveryService = new CameraDiscoveryService()

  resolveGatewayIp(): string {
    try {
      const info: WifiIpInfoLike = wifi.getIpInfo() as WifiIpInfoLike
      const gatewayNum: number = typeof info.gateway === 'number' ? info.gateway : 0
      if (gatewayNum > 0) {
        const gatewayIp: string = this.ipv4NumberToString(gatewayNum)
        if (this.isUsableIp(gatewayIp)) {
          return gatewayIp
        }
      }
    } catch (e) {
      void e
    }
    return CAR_DEVICE_IP
  }

  async resolveCameraIp(timeoutMs: number = 1200): Promise<string> {
    try {
      const ip: string | undefined = await this.cameraDiscovery.discoverCameraIp(timeoutMs)
      return ip ?? ''
    } catch (e) {
      void e
      return ''
    }
  }

  buildCameraHost(ip: string): string {
    return ip.length > 0 ? `${ip}:${CAR_CAMERA_HTTP_PORT}` : defaultCameraHost()
  }

  buildRtspUrl(ip: string): string {
    return ip.length > 0 ? `rtsp://${ip}:${CAR_RTSP_PORT}/stream` : defaultRtspUrl()
  }

  private ipv4NumberToString(ipNum: number): string {
    const littleEndian: string = `${ipNum & 0xFF}.${(ipNum >>> 8) & 0xFF}.${(ipNum >>> 16) & 0xFF}.${(ipNum >>> 24) & 0xFF}`
    const bigEndian: string = `${(ipNum >>> 24) & 0xFF}.${(ipNum >>> 16) & 0xFF}.${(ipNum >>> 8) & 0xFF}.${ipNum & 0xFF}`
    return this.preferIpv4Candidate(littleEndian, bigEndian)
  }

  private preferIpv4Candidate(first: string, second: string): string {
    if (this.isSameSubnet(second, CAR_DEVICE_IP)) return second
    if (this.isSameSubnet(second, CAR_CAMERA_IP)) return second
    if (this.isSameSubnet(first, CAR_DEVICE_IP)) return first
    if (this.isSameSubnet(first, CAR_CAMERA_IP)) return first
    if (this.isPrivateIp(second) && !this.isPrivateIp(first)) return second
    return first
  }

  private isSameSubnet(ip: string, target: string): boolean {
    const a: Array<string> = ip.split('.')
    const b: Array<string> = target.split('.')
    if (a.length !== 4 || b.length !== 4) return false
    return a[0] === b[0] && a[1] === b[1] && a[2] === b[2]
  }

  private isPrivateIp(ip: string): boolean {
    const parts: Array<number> = ip.split('.').map((v: string) => Number.parseInt(v, 10))
    if (parts.length !== 4) return false
    if (parts[0] === 10) return true
    if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true
    if (parts[0] === 192 && parts[1] === 168) return true
    return false
  }

  private isUsableIp(ip: string): boolean {
    return ip.length > 0 && ip !== '0.0.0.0'
  }
}

export const deviceNetworkResolver: DeviceNetworkResolver = new DeviceNetworkResolver()

