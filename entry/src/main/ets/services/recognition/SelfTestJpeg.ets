/**
 * 代码指南：
 * 文件： services/recognition/SelfTestJpeg.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
// entry/src/main/ets/services/recognition/SelfTestJpeg.ets

export class SelfTestJpeg {
  // 1x1 white JPEG (generated offline), hex string
  private static readonly HEX: string =
    'ffd8ffe000104a46494600010100000100010000ffdb00430006040405040406' +
      '0505050606060607080d08080707070f0a0b090d13100f1212110f11111a1415' +
      '17181919180f131b1d1b171d15181818ffdb0043010606060807080f08080f18' +
      '11111118181818181818181818181818181818181818181818181818181818' +
      '1818181818181818181818181818181818ffc000110800010001030122000211' +
      '01031101ffc4001f000001050101010101010000000000000000010203040506' +
      '0708090a0bffc400b5100002010303020403050504040000017d010203000411' +
      '05122131410613516107227114328191a1082342b1c11552d1f0243362728209' +
      '0a161718191a25262728292a3435363738393a434445464748494a5354555657' +
      '58595a636465666768696a737475767778797a838485868788898a9293949596' +
      '9798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2' +
      'd3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffc400' +
      '1f0100030101010101010101010000000000000102030405060708090a0bff' +
      'c400b51100020102040403040705040400010277000102031104052131061241' +
      '510761711322328108144291a1b1c109233352f0156272d10a162434e125f117' +
      '18191a262728292a35363738393a434445464748494a5455565758595a636465' +
      '666768696a737475767778797a82838485868788898a92939495969798999aa2' +
      'a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6' +
      'd7d8d9dae2e3e4e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda000c030100021103' +
      '11003f00f7fa28a2803fffd9'

  static getJpegArrayBuffer(): ArrayBuffer {
    const hex: string = SelfTestJpeg.HEX
    const byteLen: number = Math.floor(hex.length / 2)
    const out: Uint8Array = new Uint8Array(byteLen)

    let i: number = 0
    let j: number = 0
    while (i + 1 < hex.length && j < byteLen) {
      const part: string = hex.substring(i, i + 2)
      const v: number = Number.parseInt(part, 16)
      out[j] = Number.isFinite(v) ? v : 0
      i += 2
      j += 1
    }
    return out.buffer
  }
}
