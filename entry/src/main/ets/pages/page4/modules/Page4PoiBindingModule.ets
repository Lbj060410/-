import fs from '@ohos.file.fs'
import { Page4Keywords } from '../config/Page4Keywords'
import { Page4ReplyText } from '../config/Page4ReplyText'

export type Page4PlaceRole = 'home' | 'company'

export interface Page4PlaceBindingPayload {
  homeNodeId?: string
  companyNodeId?: string
  homeAlias?: string
  companyAlias?: string
  updateTsMs?: number
  updateSeq?: number
  source?: string
}

export interface Page4PlaceBindingPlan {
  role: Page4PlaceRole
  placeText: string
}

export interface Page4AliasItem {
  name: string
  destNodeId: string
  tsMs: number
}

export class Page4PoiBindingModule {
  static mapPoiNameToNode(
    input: string,
    mappings: Array<{ node: string, aliases: Array<string> }>,
    normalizePlaceInput: (text: string) => string
  ): string {
    const raw: string = input.trim()
    if (raw.length <= 0) return ''
    const normalized: string = normalizePlaceInput(raw)
    for (let i: number = 0; i < mappings.length; i++) {
      const one = mappings[i]
      for (let j: number = 0; j < one.aliases.length; j++) {
        const alias: string = one.aliases[j]
        if (raw.indexOf(alias) >= 0 || normalized.indexOf(normalizePlaceInput(alias)) >= 0) {
          return one.node.trim().toUpperCase()
        }
      }
    }
    return ''
  }

  static buildPoiMappingSummaryText(
    mappings: Array<{ node: string, aliases: Array<string> }>,
    aliasDict: Array<Page4AliasItem>,
    isValidNode: (id: string) => boolean,
    formatPlaceBinding: (role: Page4PlaceRole) => string
  ): string {
    const merged: Record<string, Array<string>> = {}
    for (let i: number = 0; i < mappings.length; i++) {
      const one = mappings[i]
      const node: string = one.node.trim().toUpperCase()
      if (!isValidNode(node)) continue
      if (!merged[node]) merged[node] = []
      for (let j: number = 0; j < one.aliases.length; j++) {
        const alias: string = one.aliases[j].trim()
        if (alias.length <= 0) continue
        if (merged[node].indexOf(alias) < 0) merged[node].push(alias)
      }
    }
    const nodes: Array<string> = Object.keys(merged).sort()
    const lines: Array<string> = []
    for (let i: number = 0; i < nodes.length; i++) lines.push(`${nodes[i]}: ${merged[nodes[i]].join(' / ')}`)

    const dynamicAliases: Array<string> = []
    for (let i: number = 0; i < aliasDict.length; i++) {
      const one: Page4AliasItem = aliasDict[i]
      if (!isValidNode(one.destNodeId)) continue
      if (one.name === Page4Keywords.PLACE_NAME_HOME || one.name === Page4Keywords.PLACE_NAME_COMPANY) continue
      dynamicAliases.push(`${one.name}->${one.destNodeId}`)
    }
    return Page4ReplyText.poiMappingSummary(lines, formatPlaceBinding('home'), formatPlaceBinding('company'), dynamicAliases)
  }

  static exportPoiMappingsToFile(
    exportPath: string,
    homeNodeId: string,
    companyNodeId: string,
    mappings: Array<{ node: string, aliases: Array<string> }>,
    aliases: Array<Page4AliasItem>
  ): { ok: boolean, path: string, error: string } {
    let f: fs.File | undefined = undefined
    try {
      const payload: Record<string, Object | string | number | boolean | Array<Object | string | number | boolean>> = {
        generatedAtMs: Date.now(),
        homeNodeId,
        companyNodeId,
        mappings: mappings as unknown as Array<Object>,
        aliases: aliases as unknown as Array<Object>
      }
      const txt: string = JSON.stringify(payload, null, 2)
      try { fs.unlinkSync(exportPath) } catch (_) {}
      f = fs.openSync(exportPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
      fs.writeSync(f.fd, txt)
      return { ok: true, path: exportPath, error: '' }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : 'write failed'
      return { ok: false, path: exportPath, error: msg }
    } finally {
      if (f) {
        try { fs.closeSync(f.fd) } catch (_) {}
      }
    }
  }

  static parsePlaceRoleToken(raw: string): '' | Page4PlaceRole {
    const x: string = raw.trim().toLowerCase()
    if (x.indexOf('home') >= 0 || x.indexOf(Page4Keywords.PLACE_NAME_HOME) >= 0) return 'home'
    if (
      x.indexOf('company') >= 0 ||
      x.indexOf(Page4Keywords.PLACE_NAME_COMPANY) >= 0 ||
      x.indexOf(Page4Keywords.PLACE_NAME_COMPANY_ALT) >= 0
    ) return 'company'
    return ''
  }

  static placeRoleText(role: '' | Page4PlaceRole): string {
    return Page4ReplyText.placeRoleText(role)
  }

  static parsePlaceBindingRequest(text: string): { role: Page4PlaceRole, placeText: string } | undefined {
    const src: string = text.trim()
    const roleFirst: RegExpMatchArray | null = src.match(Page4Keywords.buildPlaceBindingRoleFirstRegex())
    if (roleFirst && roleFirst.length >= 3) {
      const roleRaw: string = String(roleFirst[1] ?? '')
      const placeText: string = String(roleFirst[2] ?? '').trim()
      const role: '' | Page4PlaceRole = this.parsePlaceRoleToken(roleRaw)
      if (!role || placeText.length <= 0) return undefined
      return { role, placeText }
    }

    const placeFirst: RegExpMatchArray | null = src.match(Page4Keywords.buildPlaceBindingPlaceFirstRegex())
    if (!placeFirst || placeFirst.length < 3) return undefined
    const placeText: string = String(placeFirst[1] ?? '').trim()
    const roleRaw: string = String(placeFirst[2] ?? '')
    const role: '' | Page4PlaceRole = this.parsePlaceRoleToken(roleRaw)
    if (!role || placeText.length <= 0) return undefined
    return { role, placeText }
  }

  static wantsPlaceBindingQuery(rawLower: string, containsAny: (text: string, keys: Array<string>) => boolean): { askHome: boolean, askCompany: boolean } | undefined {
    if (containsAny(rawLower, Page4Keywords.PLACE_BINDING_SETTERS)) {
      return undefined
    }
    const ask: boolean = containsAny(rawLower, Page4Keywords.PLACE_BINDING_QUERY_ROLES) &&
      containsAny(rawLower, Page4Keywords.PLACE_BINDING_QUERY_VERBS)
    if (!ask) return undefined
    const askHome: boolean = containsAny(rawLower, Page4Keywords.PLACE_BINDING_QUERY_HOME) ||
      !containsAny(rawLower, Page4Keywords.PLACE_BINDING_QUERY_COMPANY)
    const askCompany: boolean = containsAny(rawLower, Page4Keywords.PLACE_BINDING_QUERY_COMPANY) ||
      !containsAny(rawLower, Page4Keywords.PLACE_BINDING_QUERY_HOME)
    return { askHome, askCompany }
  }

  static formatPlaceBinding(role: Page4PlaceRole, node: string, isValidNode: (id: string) => boolean): string {
    const up: string = node.trim().toUpperCase()
    return Page4ReplyText.formatPlaceBinding(role, up, isValidNode(up))
  }
}
