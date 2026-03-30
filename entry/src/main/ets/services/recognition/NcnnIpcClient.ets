// @ts-nocheck
import Want from '@ohos.app.ability.Want'
import common from '@ohos.app.ability.common'
import rpc from '@ohos.rpc'

const NCNN_IPC_DESCRIPTOR: string = 'com.example.car.ncnn.ipc'
const NCNN_IPC_TRANS_DETECT: number = 1

export class NcnnIpcClient {
  private remote: rpc.IRemoteObject | undefined
  private connecting: Promise<rpc.IRemoteObject> | undefined
  private connectId: number = -1
  private readonly bundleName: string = 'com.example.car'
  private readonly moduleName: string = 'infer'
  private readonly abilityName: string = 'NcnnInferServiceExtAbility'

  async detect(
    modelName: string,
    rgba: ArrayBuffer,
    w: number,
    h: number,
    conf: number,
    nms: number
  ): Promise<string> {
    const remote: rpc.IRemoteObject = await this.ensureConnected()
    const data = rpc.MessageParcel.create()
    const reply = rpc.MessageParcel.create()
    const option = new rpc.MessageOption()
    try {
      data.writeInterfaceToken(NCNN_IPC_DESCRIPTOR)
      data.writeString(modelName)
      data.writeInt(w)
      data.writeInt(h)
      data.writeString(String(conf))
      data.writeString(String(nms))
      data.writeByteArray(Array.from(new Uint8Array(rgba)))
      await remote.sendRequest(NCNN_IPC_TRANS_DETECT, data, reply, option)
      const code: number = reply.readInt()
      const payload: string = reply.readString()
      if (code !== 0) {
        throw new Error(payload.length > 0 ? payload : `ipc detect failed code=${code}`)
      }
      return payload
    } finally {
      try { data.reclaim() } catch (_) {}
      try { reply.reclaim() } catch (_) {}
    }
  }

  disconnect(): void {
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (ctx && this.connectId >= 0) {
      try {
        ctx.disconnectAbility(this.connectId)
      } catch (_) {}
    }
    this.connectId = -1
    this.remote = undefined
    this.connecting = undefined
  }

  private async ensureConnected(): Promise<rpc.IRemoteObject> {
    if (this.remote) return this.remote
    if (this.connecting) return await this.connecting
    this.connecting = this.connectOnce()
    try {
      const remote: rpc.IRemoteObject = await this.connecting
      this.remote = remote
      return remote
    } finally {
      this.connecting = undefined
    }
  }

  private connectOnce(): Promise<rpc.IRemoteObject> {
    const ctx: common.UIAbilityContext | undefined = this.getUiContext()
    if (!ctx) {
      return Promise.reject(new Error('abilityContext unavailable for ncnn ipc connect'))
    }

    const want: Want = {
      bundleName: this.bundleName,
      moduleName: this.moduleName,
      abilityName: this.abilityName
    }

    return new Promise<rpc.IRemoteObject>((resolve, reject): void => {
      let settled: boolean = false
      const done = (fn: () => void): void => {
        if (settled) return
        settled = true
        fn()
      }

      const options: common.ConnectOptions = {
        onConnect: (_element, remote): void => {
          done((): void => {
            this.remote = remote
            resolve(remote)
          })
        },
        onDisconnect: (): void => {
          this.remote = undefined
          this.connectId = -1
        },
        onFailed: (_code): void => {
          done((): void => reject(new Error('connect ncnn service extension failed')))
        }
      }

      try {
        this.connectId = ctx.connectAbility(want, options)
      } catch (e) {
        done((): void => reject(new Error(String(e))))
      }
    })
  }

  private getUiContext(): common.UIAbilityContext | undefined {
    const ctx = globalThis.abilityContext as common.UIAbilityContext | undefined
    return ctx
  }
}

let singleton: NcnnIpcClient | undefined

export function getNcnnIpcClient(): NcnnIpcClient {
  if (!singleton) singleton = new NcnnIpcClient()
  return singleton
}
