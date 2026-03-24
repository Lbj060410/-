/**
 * 代码指南：
 * 文件： services/diagnostics/FrameLogService.ets
 * 用途： 提供诊断信息与数据帧日志记录功能。
 * 何时修改： 日志持久化、格式或过滤逻辑发生变更时。
 * 相关文件： Page1 诊断面板及协议相关服务。
 */
// entry/src/main/ets/services/diagnostics/FrameLogService.ets

import fs from '@ohos.file.fs'
import { commStore } from '../../state/CommStore'

export enum LogDirStrategy {
  // ✅ 默认：模块 files 目录（模拟器可用）
  ENTRY_FILES = 0
}

export class FrameLogService {
  private static inited: boolean = false
  private static enabled: boolean = false
  private static logPath: string = ''
  private static lines: number = 0

  // 仅用于避免频繁 statSync
  private static lastStatAtMs: number = 0
  private static lastSizeBytes: number = 0

  static initIfNeeded(): void {
    if (FrameLogService.inited) return
    FrameLogService.inited = true

    const baseDir: string = FrameLogService.pickBaseDir(LogDirStrategy.ENTRY_FILES)
    FrameLogService.ensureDir(baseDir)

    FrameLogService.logPath = `${baseDir}/car_diag_frames.jsonl`
    FrameLogService.lines = 0
    FrameLogService.lastSizeBytes = 0

    commStore.setLogInfo(FrameLogService.logPath, 0, 0)
  }

  static setEnabled(enabled: boolean): void {
    FrameLogService.initIfNeeded()
    FrameLogService.enabled = enabled
    commStore.setLogEnabled(enabled)

    // 关闭/开启都刷新一次文件信息
    FrameLogService.refreshStat(true)
  }

  static isEnabled(): boolean {
    FrameLogService.initIfNeeded()
    return FrameLogService.enabled
  }

  static getPath(): string {
    FrameLogService.initIfNeeded()
    return FrameLogService.logPath
  }

  static appendRx(raw: Uint8Array, frameKind: string, fields: string): void {
    FrameLogService.appendLine('RX', raw, frameKind, fields)
  }

  static appendTx(raw: Uint8Array, tag: string): void {
    FrameLogService.appendLine('TX', raw, tag, '')
  }

  private static appendLine(dir: string, raw: Uint8Array, kind: string, fields: string): void {
    FrameLogService.initIfNeeded()
    if (!FrameLogService.enabled) return

    const ts: number = Date.now()
    const hex: string = FrameLogService.toHex(raw)
    const line: string =
      `{"tsMs":${ts},"dir":"${dir}","kind":"${FrameLogService.escape(kind)}","hex":"${hex}","fields":"${FrameLogService.escape(fields)}"}\n`

    try {
      // ✅ openSync 返回 File，不是 number
      const f: fs.File = fs.openSync(
        FrameLogService.logPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND
      )
      // ✅ try-finally 确保 writeSync 抛异常时 fd 依然被关闭
      try {
        fs.writeSync(f.fd, line)
      } finally {
        fs.closeSync(f.fd)
      }

      FrameLogService.lines += 1
      FrameLogService.refreshStat(false)
    } catch (_) {
      console.info('[DIAG][LOG] write failed')
    }
  }

  private static refreshStat(force: boolean): void {
    const now: number = Date.now()
    if (!force && now - FrameLogService.lastStatAtMs < 500) return
    FrameLogService.lastStatAtMs = now

    let sizeBytes: number = FrameLogService.lastSizeBytes
    try {
      const st = fs.statSync(FrameLogService.logPath)
      sizeBytes = (st.size as number)
    } catch (_) {
      sizeBytes = 0
    }

    FrameLogService.lastSizeBytes = sizeBytes
    commStore.setLogInfo(FrameLogService.logPath, FrameLogService.lines, sizeBytes)
  }

  private static pickBaseDir(strategy: LogDirStrategy): string {
    if (strategy === LogDirStrategy.ENTRY_FILES) {
      return '/data/storage/el2/base/haps/entry/files/diagnostics'
    }
    return '/data/storage/el2/base/haps/entry/files/diagnostics'
  }

  private static ensureDir(dir: string): void {
    try {
      // ✅ mkdirSync 第二参数是 boolean recursive
      fs.mkdirSync(dir)
    } catch (_) {}
  }

  private static toHex(data: Uint8Array): string {
    let s: string = ''
    for (let i: number = 0; i < data.length; i++) {
      const v: number = data[i] & 0xff
      const part: string = v.toString(16).toUpperCase().padStart(2, '0')
      s = s.length === 0 ? part : (s + ' ' + part)
    }
    return s
  }

  private static escape(s: string): string {
    return s
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\r')
  }
}
