/**
 * 代码指南：
 * 文件： services/recognition/CarTaskSnapshotArchiveService.ets
 * 用途： 识别流程（引擎抽象、任务调度、结果转换与上报）。
 * 何时修改： 新增/移除模型后端、任务规则或推理调度策略时。
 * 相关文件： state/RecogStore.ets、services/source/*、展示识别输出结果的页面。
 */
import fs from '@ohos.file.fs'
import mediaLibrary from '@ohos.multimedia.mediaLibrary'
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl'
import type common from '@ohos.app.ability.common'
import image from '@ohos.multimedia.image'
type PixelMap = image.PixelMap

import { RecognitionSubtype } from './RecognitionTask'

export class CarTaskSnapshotArchiveService {
  async save(taskId: string, subtype: RecognitionSubtype, pm: PixelMap): Promise<string> {
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) return ''

    const granted: boolean = await this.ensureMediaPermission(ctx)
    if (!granted) return ''

    const lib: mediaLibrary.MediaLibrary = mediaLibrary.getMediaLibrary(ctx)
    const displayName: string = `car_task_${Date.now()}_${this.safeText(taskId)}_${subtype}.jpg`

    let fd: number = -1
    let packer: image.ImagePacker | undefined = undefined
    try {
      const imageRoot: string = await lib.getPublicDirectory(mediaLibrary.DirectoryType.DIR_IMAGE)
      const asset: mediaLibrary.FileAsset =
        await lib.createAsset(mediaLibrary.MediaType.IMAGE, displayName, imageRoot)
      fd = await asset.open('rw')

      packer = image.createImagePacker()
      const packed: ArrayBuffer = await packer.packing(pm, { format: 'image/jpeg', quality: 90 })
      await fs.write(fd, packed)
      await fs.fsync(fd)
      await asset.close(fd)
      fd = -1
      return asset.uri
    } catch (e) {
      void e
      return ''
    } finally {
      if (packer) {
        try { await packer.release() } catch (e) {}
      }
      if (fd >= 0) {
        try { await fs.close(fd) } catch (e) {}
      }
      try { await lib.release() } catch (e) {}
    }
  }

  private getUiContext(): common.UIAbilityContext | undefined {
    const ctx = globalThis.abilityContext as common.UIAbilityContext
    if (!ctx) return undefined
    return ctx
  }

  private async ensureMediaPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
    const legacyPerms: Array<Permissions> = [
      'ohos.permission.READ_MEDIA' as Permissions,
      'ohos.permission.WRITE_MEDIA' as Permissions
    ]
    return await this.requestPermissionPair(atManager, ctx, legacyPerms)
  }

  private async requestPermissionPair(
    atManager: abilityAccessCtrl.AtManager,
    ctx: common.UIAbilityContext,
    perms: Array<Permissions>
  ): Promise<boolean> {
    try {
      const result = await atManager.requestPermissionsFromUser(ctx, perms)
      for (let i: number = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) return false
      }
      return true
    } catch (e) {
      void e
      return false
    }
  }

  private safeText(v: string): string {
    const s: string = v.trim()
    if (s.length <= 0) return 'task'
    return s.replace(/[^0-9A-Za-z_-]/g, '_')
  }
}

