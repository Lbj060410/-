// @ts-nocheck
import ServiceExtensionAbility from '@ohos.app.ability.ServiceExtensionAbility'
import resourceManager from '@ohos.resourceManager'
import rpc from '@ohos.rpc'
import * as libentry from 'libentry.so'

const NCNN_IPC_DESCRIPTOR: string = 'com.example.car.ncnn.ipc'
const NCNN_IPC_TRANS_DETECT: number = 1

class NcnnRpcStub extends rpc.RemoteObject {
  private readonly owner: NcnnInferServiceExtAbility

  constructor(owner: NcnnInferServiceExtAbility) {
    super(NCNN_IPC_DESCRIPTOR)
    this.owner = owner
  }

  async onRemoteRequest(code: number, data: rpc.MessageParcel, reply: rpc.MessageParcel): Promise<boolean> {
    const token: string = data.readInterfaceToken()
    if (token !== NCNN_IPC_DESCRIPTOR) {
      reply.writeInt(-10)
      reply.writeString('bad interface token')
      return true
    }

    if (code !== NCNN_IPC_TRANS_DETECT) {
      reply.writeInt(-11)
      reply.writeString(`unsupported trans code=${code}`)
      return true
    }

    try {
      const modelName: string = data.readString()
      const w: number = data.readInt()
      const h: number = data.readInt()
      const conf: number = Number(data.readString())
      const nms: number = Number(data.readString())
      const rgbaList: Array<number> = data.readByteArray()
      const rgba: ArrayBuffer = new Uint8Array(rgbaList).buffer

      await this.owner.ensureModelLoaded(modelName)
      const json: string = libentry.detectNcnn(modelName, rgba, w, h, conf, nms)
      const nativeErr: string = (typeof libentry.getLastError === 'function') ? String(libentry.getLastError()) : ''
      if (nativeErr.length > 0) {
        reply.writeInt(-2)
        reply.writeString(nativeErr)
        return true
      }

      reply.writeInt(0)
      reply.writeString(json)
      return true
    } catch (e) {
      reply.writeInt(-1)
      reply.writeString(e instanceof Error ? e.message : String(e))
      return true
    }
  }
}

export default class NcnnInferServiceExtAbility extends ServiceExtensionAbility {
  private stub?: NcnnRpcStub
  private loadedModels: Set<string> = new Set<string>()

  onCreate(want: Object): void {
    console.info(`[ncnn-ipc] service create: ${JSON.stringify(want)}`)
  }

  onConnect(want: Object): rpc.RemoteObject {
    console.info(`[ncnn-ipc] service connect: ${JSON.stringify(want)}`)
    if (!this.stub) {
      this.stub = new NcnnRpcStub(this)
    }
    return this.stub
  }

  onDisconnect(want: Object): void {
    console.info(`[ncnn-ipc] service disconnect: ${JSON.stringify(want)}`)
  }

  onDestroy(): void {
    console.info('[ncnn-ipc] service destroy')
  }

  async ensureModelLoaded(modelName: string): Promise<void> {
    const name: string = String(modelName ?? '').trim()
    if (name.length <= 0) throw new Error('empty model name')
    if (this.loadedModels.has(name)) return

    const rm: resourceManager.ResourceManager = this.context.resourceManager
    if (!rm) {
      throw new Error('resourceManager unavailable in ncnn service')
    }

    const paramFileName: string = `${name}.param`
    const binFileName: string = `${name}.bin`
    const paramBuf: ArrayBuffer = await this.loadRawFile(rm, paramFileName)
    const binBuf: ArrayBuffer = await this.loadRawFile(rm, binFileName)
    const ok: boolean = libentry.loadNcnnModel(name, paramBuf, binBuf)
    if (!ok) {
      const nativeErr: string = (typeof libentry.getLastError === 'function') ? String(libentry.getLastError()) : ''
      throw new Error(`loadNcnnModel failed: model=${name}, err=${nativeErr}`)
    }
    this.loadedModels.add(name)
    console.info(`[ncnn-ipc] model loaded: ${name}`)
  }

  private async loadRawFile(rm: resourceManager.ResourceManager, fileName: string): Promise<ArrayBuffer> {
    const candidates: string[] = [fileName, `ncnn_models/${fileName}`]
    let lastErr: Object | string = ''
    for (let i: number = 0; i < candidates.length; i++) {
      try {
        const rawObj: Object = await rm.getRawFileContent(candidates[i])
        return this.toArrayBuffer(rawObj, fileName)
      } catch (e) {
        lastErr = e
      }
    }
    throw new Error(`rawfile not found: ${fileName}, last=${String(lastErr)}`)
  }

  private toArrayBuffer(dataObj: Object | undefined | null, fileName: string): ArrayBuffer {
    if (dataObj === undefined || dataObj === null) {
      throw new Error(`rawfile empty: ${fileName}`)
    }
    const maybeArrayBuffer = dataObj as ArrayBuffer
    if (maybeArrayBuffer instanceof ArrayBuffer) {
      return maybeArrayBuffer.slice(0)
    }

    const maybeBytes = dataObj as Uint8Array
    const rawObj = maybeBytes.buffer as Object | undefined
    if (rawObj) {
      const raw: ArrayBuffer = rawObj as ArrayBuffer
      const byteOffsetNum: number = Number(maybeBytes.byteOffset)
      const byteLengthNum: number = Number(maybeBytes.byteLength)
      if (Number.isFinite(byteOffsetNum) && Number.isFinite(byteLengthNum) && byteLengthNum > 0) {
        return raw.slice(byteOffsetNum, byteOffsetNum + byteLengthNum)
      }
    }

    const mapObj = dataObj as Record<string, Object>
    const nestedData: Object | undefined = mapObj['data']
    if (nestedData !== undefined) {
      return this.toArrayBuffer(nestedData, fileName)
    }

    const keys: string[] = Object.keys(mapObj)
    throw new Error(`invalid rawfile content: ${fileName}, keys=${keys.join(',')}`)
  }
}

