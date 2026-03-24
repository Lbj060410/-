/**
 * 代码指南：
 * 文件：config/TencentAsrConfig.ets
 * 用途：page4 语音输入的腾讯 ASR 凭证和运行时选项。
 * 何时修改：轮换凭证或调整引擎参数时。
 */
export const TENCENT_ASR_APP_ID: string = '1413487017'
export const TENCENT_ASR_SECRET_ID: string = 'AKIDcYUCfuugHfoESmskWEl4GKEvRksoZ8Ve'
export const TENCENT_ASR_SECRET_KEY: string = '1rmaBZnz1seGUedOwKnJeR22qRp18A89'

// 腾讯极速 ASR 引擎，例如 16k_zh / 16k_en / 16k_zh_video。
export const TENCENT_ASR_ENGINE_MODEL_TYPE: string = '16k_zh'

// 腾讯 API 使用的音频格式枚举。1 表示常见腾讯 ASR 配置中的 pcm。
export const TENCENT_ASR_VOICE_FORMAT: number = 1
export const TENCENT_ASR_FLASH_VOICE_FORMAT: string = 'pcm'

// page4 按住说话的录音配置。
export const TENCENT_ASR_SAMPLE_RATE: number = 16000
export const TENCENT_ASR_READ_CHUNK_SIZE: number = 6400

// 实时 websocket 选项。
export const TENCENT_ASR_NEED_VAD: number = 0
export const TENCENT_ASR_FILTER_DIRTY: number = 0
export const TENCENT_ASR_FILTER_MODAL: number = 0
export const TENCENT_ASR_FILTER_PUNC: number = 0
export const TENCENT_ASR_REALTIME_RESULT_TIMEOUT_MS: number = 4500
