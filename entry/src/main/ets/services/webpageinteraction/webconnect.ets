/**
 * 代码指南：
 * 文件： 
services/webpageinteraction/webconnect.ets
 * 用途： 
Module webconnect responsibilities
 * 何时修改： related behavior or contracts change.
 */
/**
 * FILE ROLE LOG:
 * 文件： entry/src/main/ets/services/webpageinteraction/webconnect.ets
 * 用途： 网页交互服务，负责与网页端/远端接口的数据通讯。
 * Notes: 修改本文件时请保持与调用方契约一致，避免跨模块行为回归。
 */
import http from '@ohos.net.http'
// @ts-ignore
import { BusinessError } from '@ohos.base'
import hilog from '@ohos.hilog'
import { commStore } from '../../state/CommStore'

const API_URL = 'http://121.40.121.6:8080/adminsystem/car/trajectory/save'
const DEFAULT_CAR_ID = '001'
const SENDWEB_DOMAIN = 0xFF02
const SENDWEB_TAG = 'sendweb'

interface SaveTrajectoryPayload {
  carId: string
  xCoordinate: string
  yCoordinate: string
  interval: number
  speed: number
  status: number
}

function appendWebDiag(status: string, line: string): void {
  commStore.appendDiagWebTxLog({
    tsMs: Date.now(),
    status: status,
    line: line
  })
}

function sanitizeNodeId(nodeId: string): string {
  return nodeId.trim().toUpperCase()
}

function parseNodeCoordinate(nodeId: string): { xCoordinate: string, yCoordinate: string } | undefined {
  const normalized: string = sanitizeNodeId(nodeId)
  if (normalized.length < 2) return undefined
  const xCoordinate: string = normalized[0]
  const yCoordinate: string = normalized.slice(1)
  if (!/^[A-Z]$/.test(xCoordinate)) return undefined
  if (!/^\d+$/.test(yCoordinate)) return undefined
  return { xCoordinate: xCoordinate, yCoordinate: yCoordinate }
}

function buildPayloadByNode(nodeId: string, _intervalMs: number): SaveTrajectoryPayload | undefined {
  const coordinate = parseNodeCoordinate(nodeId)
  if (!coordinate) return undefined
  const safeIntervalMs: number = Math.max(0, Math.trunc(_intervalMs))
  return {
    carId: DEFAULT_CAR_ID,
    xCoordinate: coordinate.xCoordinate,
    yCoordinate: coordinate.yCoordinate,
    interval: safeIntervalMs,
    speed: 0,
    status: 0
  }
}

export async function saveCarTrajectory(payload: SaveTrajectoryPayload): Promise<string> {
  const httpRequest = http.createHttp()
  const payloadText: string = JSON.stringify(payload)
  try {
    hilog.info(SENDWEB_DOMAIN, SENDWEB_TAG, 'send payload: %{public}s', payloadText)
    const requestOptions = {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: payload
    }
    const response = await httpRequest.request(API_URL, requestOptions)
    const resultText: string = String(response.result)
    hilog.info(SENDWEB_DOMAIN, SENDWEB_TAG, 'send success response: %{public}s', resultText)
    console.info(`[WEB_CONNECT] trajectory upload success: ${payloadText}`)
    appendWebDiag('SENT', `payload=${payloadText} response=${resultText}`)
    return resultText
  } catch (err) {
    const message: string = (err as BusinessError).message
    hilog.error(SENDWEB_DOMAIN, SENDWEB_TAG, 'send failed err: %{public}s payload=%{public}s', message, payloadText)
    console.error(`[WEB_CONNECT] trajectory upload failed: ${message}`)
    appendWebDiag('FAILED', `payload=${payloadText} err=${message}`)
    throw err
  } finally {
    httpRequest.destroy()
  }
}

export async function saveCarTrajectoryByNode(nodeId: string, intervalMs: number): Promise<boolean> {
  const safeIntervalMs: number = Math.max(0, Math.trunc(intervalMs))
  const payload = buildPayloadByNode(nodeId, safeIntervalMs)
  if (!payload) {
    console.error(`[WEB_CONNECT] skip upload, bad nodeId=${nodeId}`)
    hilog.warn(SENDWEB_DOMAIN, SENDWEB_TAG, 'skip bad nodeId=%{public}s', nodeId)
    appendWebDiag('SKIP', `bad nodeId=${nodeId}`)
    return false
  }
  await saveCarTrajectory(payload)
  return true
}


