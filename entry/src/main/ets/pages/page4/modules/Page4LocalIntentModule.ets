import { GridIdCodec } from '../../page1/app/PathPlannerAStar'
import { Page4AliasItem } from './Page4PoiBindingModule'

export class Page4LocalIntentModule {
  static containsAny(text: string, keys: Array<string>): boolean {
    const x: string = text.toLowerCase()
    for (let i: number = 0; i < keys.length; i++) {
      if (x.indexOf(keys[i].toLowerCase()) >= 0) return true
    }
    return false
  }

  static learnAliasFromText(text: string, aliasDict: Array<Page4AliasItem>): { message: string, aliasDict: Array<Page4AliasItem> } {
    const src: string = text.trim()
    if (src.length <= 0) return { message: '', aliasDict }
    const patterns: Array<RegExp> = [
      /(?:把|将)\s*([^，。；;,\s]{1,16})\s*(?:记为|设为|设置为|定义为)\s*([A-Ga-g]\d{1,2})/,
      /^([^，。；;,\s]{1,16})\s*(?:是|等于)\s*([A-Ga-g]\d{1,2})$/
    ]
    for (let i: number = 0; i < patterns.length; i++) {
      const m: RegExpMatchArray | null = src.match(patterns[i])
      if (!m || m.length < 3) continue
      const name: string = m[1].trim()
      const destNodeId: string = m[2].trim().toUpperCase()
      if (!GridIdCodec.isValidId(destNodeId)) return { message: `"${destNodeId}" 不是合法点位，别名学习失败。`, aliasDict }
      if (name.length <= 0) return { message: '别名为空，学习失败。', aliasDict }
      let replaced: boolean = false
      const next: Array<Page4AliasItem> = []
      for (let k: number = 0; k < aliasDict.length; k++) {
        const cur: Page4AliasItem = aliasDict[k]
        if (cur.name === name) {
          replaced = true
          next.push({ name, destNodeId, tsMs: Date.now() })
        } else next.push(cur)
      }
      if (!replaced) next.push({ name, destNodeId, tsMs: Date.now() })
      return { message: replaced ? `已更新别名：${name} -> ${destNodeId}` : `已学习别名：${name} -> ${destNodeId}`, aliasDict: next }
    }
    return { message: '', aliasDict }
  }

  static resolveAliasNode(text: string, aliasDict: Array<Page4AliasItem>, normalizePlaceInput: (text: string) => string): string {
    const src: string = text.trim()
    if (src.length <= 0) return ''
    for (let i: number = 0; i < aliasDict.length; i++) {
      const item: Page4AliasItem = aliasDict[i]
      if (item.name.length <= 0) continue
      if (src.indexOf(item.name) >= 0) return item.destNodeId
      if (normalizePlaceInput(src).indexOf(normalizePlaceInput(item.name)) >= 0) return item.destNodeId
    }
    return ''
  }

  static resolveContextDestNode(input: string, lastDestNodeId: string): string {
    const x: string = input.trim()
    if (x.length <= 0) return ''
    if (!GridIdCodec.isValidId(lastDestNodeId)) return ''
    if (this.containsAny(x, ['那里', '那儿', '刚才那个点', '上一目的地', '上一个目的地', '原目的地'])) return lastDestNodeId
    return ''
  }
}
