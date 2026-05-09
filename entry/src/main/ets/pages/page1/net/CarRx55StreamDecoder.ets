import { FrameLogService } from '../../../services/diagnostics/FrameLogService'

export interface CarProtoFrame {
  ok: boolean
  raw: Uint8Array
  frameLen: number
  frameKind: string
  header0: number
  header1: number
  len: number
  type: number
  flags: number
  seqH: number
  seqL: number
  seq: number
  data: Uint8Array
  crc: number
  tail: number
}

export class CarProtoStreamDecoder {
  private readonly buf: Array<number> = []
  private readonly header0: number = 0xCC
  private readonly header1: number = 0xF5
  private readonly tail: number = 0xBB

  feedProto(chunk: Uint8Array): Array<CarProtoFrame> {
    const out: Array<CarProtoFrame> = []
    for (let i: number = 0; i < chunk.length; i++) this.buf.push(chunk[i] & 0xff)

    while (this.buf.length >= 10) {
      const headIdx: number = this.findHeader()
      if (headIdx < 0) {
        this.buf.length = 0
        break
      }
      if (headIdx > 0) this.buf.splice(0, headIdx)
      if (this.buf.length < 10) break
      if ((this.buf[0] & 0xff) !== this.header0 || (this.buf[1] & 0xff) !== this.header1) {
        this.buf.shift()
        continue
      }

      const len: number = this.buf[2] & 0xff
      const total: number = 2 + 1 + len + 1 + 1
      if (len < 4) {
        this.buf.shift()
        continue
      }
      if (this.buf.length < total) break

      const tailPos: number = total - 1
      if ((this.buf[tailPos] & 0xff) !== this.tail) {
        this.buf.shift()
        continue
      }

      const raw: Uint8Array = new Uint8Array(this.buf.slice(0, total))
      const type: number = raw[3] & 0xff
      const flags: number = raw[4] & 0xff
      const seqH: number = raw[5] & 0xff
      const seqL: number = raw[6] & 0xff
      const seq: number = ((seqH << 8) | seqL) & 0xffff
      const dataLen: number = len - 4
      const data: Uint8Array = raw.slice(7, 7 + dataLen)
      const crc: number = raw[total - 2] & 0xff
      const tail: number = raw[total - 1] & 0xff
      // CRC range: from Byte1=0xF5 to payload end (exclude 0xCC, CRC, 0xBB).
      const calc: number = this.crc8(raw, 1, total - 2)
      const ok: boolean = calc === crc

      const frame: CarProtoFrame = {
        ok: ok,
        raw: raw,
        frameLen: total,
        frameKind: 'CCF5',
        header0: raw[0] & 0xff,
        header1: raw[1] & 0xff,
        len: len,
        type: type,
        flags: flags,
        seqH: seqH,
        seqL: seqL,
        seq: seq,
        data: data,
        crc: crc,
        tail: tail
      }
      out.push(frame)
      FrameLogService.appendRx(raw, 'CCF5', `type=0x${this.hex(type)} flags=0x${this.hex(flags)} seq=${seq} len=${len} crc=${ok ? 'OK' : 'BAD'}`)
      this.buf.splice(0, total)
    }

    return out
  }

  reset(): void {
    this.buf.length = 0
  }

  getBufferedSize(): number {
    return this.buf.length
  }

  private findHeader(): number {
    for (let i: number = 0; i < this.buf.length; i++) {
      if ((this.buf[i] & 0xff) === this.header0) return i
    }
    return -1
  }

  private crc8(bytes: Uint8Array, start: number, endExclusive: number): number {
    let crc: number = 0x00
    for (let i: number = start; i < endExclusive; i++) {
      crc ^= (bytes[i] & 0xff)
      for (let b: number = 0; b < 8; b++) {
        if ((crc & 0x80) !== 0) crc = ((crc << 1) ^ 0x07) & 0xff
        else crc = (crc << 1) & 0xff
      }
    }
    return crc & 0xff
  }

  private hex(v: number): string {
    return (v & 0xff).toString(16).toUpperCase().padStart(2, '0')
  }
}
