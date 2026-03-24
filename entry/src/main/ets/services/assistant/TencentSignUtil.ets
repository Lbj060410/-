/**
 * 代码指南：
 * 文件： services/assistant/TencentSignUtil.ets
 * 用途： Pure ArkTS HMAC-SHA1 signing helper for Tencent ASR APIs.
 * 何时修改： Tencent signing rule changes.
 */
import util from '@ohos.util'

export class TencentSignUtil {
  private readonly base64: util.Base64Helper = new util.Base64Helper()

  signBase64(message: string, secretKey: string): string {
    const mac: Uint8Array = this.hmacSha1(this.utf8(message), this.utf8(secretKey))
    return this.base64.encodeToStringSync(mac)
  }

  private hmacSha1(message: Uint8Array, key: Uint8Array): Uint8Array {
    const blockSize: number = 64
    let useKey: Uint8Array = key
    if (useKey.length > blockSize) {
      useKey = this.sha1(useKey)
    }
    const paddedKey: Uint8Array = new Uint8Array(blockSize)
    paddedKey.set(useKey.subarray(0, Math.min(useKey.length, blockSize)))

    const ipad: Uint8Array = new Uint8Array(blockSize)
    const opad: Uint8Array = new Uint8Array(blockSize)
    for (let i: number = 0; i < blockSize; i++) {
      ipad[i] = paddedKey[i] ^ 0x36
      opad[i] = paddedKey[i] ^ 0x5c
    }

    const innerInput: Uint8Array = this.concat(ipad, message)
    const innerHash: Uint8Array = this.sha1(innerInput)
    const outerInput: Uint8Array = this.concat(opad, innerHash)
    return this.sha1(outerInput)
  }

  private sha1(data: Uint8Array): Uint8Array {
    const h: Uint32Array = new Uint32Array([
      0x67452301,
      0xefcdab89,
      0x98badcfe,
      0x10325476,
      0xc3d2e1f0
    ])

    const padded: Uint8Array = this.sha1Pad(data)
    const w: Uint32Array = new Uint32Array(80)

    for (let offset: number = 0; offset < padded.length; offset += 64) {
      for (let i: number = 0; i < 16; i++) {
        const idx: number = offset + i * 4
        w[i] = (((padded[idx] << 24) >>> 0) |
          ((padded[idx + 1] << 16) >>> 0) |
          ((padded[idx + 2] << 8) >>> 0) |
          (padded[idx + 3] >>> 0)) >>> 0
      }
      for (let i: number = 16; i < 80; i++) {
        w[i] = this.rol((w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]) >>> 0, 1)
      }

      let a: number = h[0]
      let b: number = h[1]
      let c: number = h[2]
      let d: number = h[3]
      let e: number = h[4]

      for (let i: number = 0; i < 80; i++) {
        let f: number
        let k: number
        if (i < 20) {
          f = ((b & c) | ((~b) & d)) >>> 0
          k = 0x5a827999
        } else if (i < 40) {
          f = (b ^ c ^ d) >>> 0
          k = 0x6ed9eba1
        } else if (i < 60) {
          f = ((b & c) | (b & d) | (c & d)) >>> 0
          k = 0x8f1bbcdc
        } else {
          f = (b ^ c ^ d) >>> 0
          k = 0xca62c1d6
        }
        const temp: number = (this.rol(a, 5) + f + e + k + w[i]) >>> 0
        e = d
        d = c
        c = this.rol(b, 30)
        b = a
        a = temp
      }

      h[0] = (h[0] + a) >>> 0
      h[1] = (h[1] + b) >>> 0
      h[2] = (h[2] + c) >>> 0
      h[3] = (h[3] + d) >>> 0
      h[4] = (h[4] + e) >>> 0
    }

    const out: Uint8Array = new Uint8Array(20)
    for (let i: number = 0; i < 5; i++) {
      out[i * 4] = (h[i] >>> 24) & 0xff
      out[i * 4 + 1] = (h[i] >>> 16) & 0xff
      out[i * 4 + 2] = (h[i] >>> 8) & 0xff
      out[i * 4 + 3] = h[i] & 0xff
    }
    return out
  }

  private sha1Pad(data: Uint8Array): Uint8Array {
    const originalLen: number = data.length
    const bitLenHi: number = Math.floor((originalLen * 8) / 0x100000000)
    const bitLenLo: number = (originalLen * 8) >>> 0
    const padLen: number = ((56 - ((originalLen + 1) % 64)) + 64) % 64
    const totalLen: number = originalLen + 1 + padLen + 8
    const out: Uint8Array = new Uint8Array(totalLen)
    out.set(data, 0)
    out[originalLen] = 0x80
    out[totalLen - 8] = (bitLenHi >>> 24) & 0xff
    out[totalLen - 7] = (bitLenHi >>> 16) & 0xff
    out[totalLen - 6] = (bitLenHi >>> 8) & 0xff
    out[totalLen - 5] = bitLenHi & 0xff
    out[totalLen - 4] = (bitLenLo >>> 24) & 0xff
    out[totalLen - 3] = (bitLenLo >>> 16) & 0xff
    out[totalLen - 2] = (bitLenLo >>> 8) & 0xff
    out[totalLen - 1] = bitLenLo & 0xff
    return out
  }

  private rol(value: number, bits: number): number {
    return ((value << bits) | (value >>> (32 - bits))) >>> 0
  }

  private concat(a: Uint8Array, b: Uint8Array): Uint8Array {
    const out: Uint8Array = new Uint8Array(a.length + b.length)
    out.set(a, 0)
    out.set(b, a.length)
    return out
  }

  private utf8(s: string): Uint8Array {
    return new util.TextEncoder().encodeInto(s)
  }
}
