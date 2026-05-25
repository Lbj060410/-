/**
 * 表演文件：车辆控制协议处理 - 清晰版流程示例
 * 用途：演示 0x01/0x02/0x03/0x04/0x05 指令从接收到执行的完整链路（非正式业务逻辑）
 */

import { AStarPathPlanner } from './WavefrontDiffusion'

export enum CommandType {
  HEARTBEAT = 0x01,
  OBSTACLE_DETECTION = 0x02,
  PATH_REPLAN = 0x03,
  EMERGENCY_STOP = 0x04,
  STATUS_REPORT = 0x05
}

export interface CommandFrame {
  type: CommandType
  timestamp: number
  data: any
}

export type SpecialRoadType = 'PEANUT_FIELD' | 'CONSTRUCTION' | 'WATER_HAZARD' | 'STEEP_SLOPE'

export interface SpecialRoadSegment {
  location: string
  type: SpecialRoadType
  confidence: number
  imageId: string
  timestamp: number
}

export interface ReviewResult {
  segmentId: string
  detectedType: string
  confidence: number
  recommendation: string
  affectsPathPlanning: boolean
}

interface RotationFrame {
  timestamp: number
  sensorData: {
    distance: number
  }
}

interface CameraFrame {
  timestamp: number
  resolution: string
  format: string
  data: string
}

interface RecognitionResult {
  detectedType: SpecialRoadType | 'UNKNOWN'
  confidence: number
  boundingBox: {
    x: number
    y: number
    w: number
    h: number
  }
  modelVersion: string
}

interface ReplanData {
  reason: string
  obstacles: Array<any>
  blockedNodes: Array<string>
  priority: 'LOW' | 'MEDIUM' | 'HIGH'
}

interface CloudUploadTask {
  data: any
  timestamp: number
  status: 'PENDING' | 'DONE' | 'FAILED'
}

interface VehicleStatus {
  timestamp: number
  position: string
  target: string
  battery: number
  temperature: number
  autoNavigationEnabled: boolean
  specialRoadsCount: number
  queuedCommands: number
  logCount: number
}

interface AvoidanceDecision {
  action: 'TURN_LEFT' | 'TURN_RIGHT' | 'SLOW_DOWN' | 'STOP'
  angle: number
  speed: number
}

export class VehicleControlProtocol {
  private commandQueue: Array<CommandFrame> = []
  private specialRoadsDetected: Array<SpecialRoadSegment> = []
  private reviewResults: Array<ReviewResult> = []
  private cloudUploadQueue: Array<CloudUploadTask> = []
  private systemLogs: Array<string> = []

  private currentPath: Array<string> = []
  private currentTarget: string = 'G7'
  private lastHeartbeatAt: number = 0
  private autoNavigationEnabled: boolean = true

  private readonly pathPlanner: AStarPathPlanner = new AStarPathPlanner()

  /**
   * 主入口：处理收到的协议帧
   */
  processCommand(frame: CommandFrame): void {
    this.logSystemEvent(`[RX] 收到指令 0x${frame.type.toString(16).toUpperCase()}`)
    this.dispatchCommand(frame)
    this.consumeQueuedCommands()
  }

  private dispatchCommand(frame: CommandFrame): void {
    switch (frame.type) {
      case CommandType.HEARTBEAT:
        this.handleHeartbeat(frame)
        return
      case CommandType.OBSTACLE_DETECTION:
        this.handleObstacleDetection(frame)
        return
      case CommandType.PATH_REPLAN:
        this.handlePathReplan(frame)
        return
      case CommandType.EMERGENCY_STOP:
        this.handleEmergencyStop(frame)
        return
      case CommandType.STATUS_REPORT:
        this.handleStatusReport(frame)
        return
      default:
        this.logSystemEvent(`[WARN] 未知指令类型: 0x${frame.type}`)
        return
    }
  }

  private consumeQueuedCommands(): void {
    let guard = 0
    while (this.commandQueue.length > 0 && guard < 16) {
      const next = this.commandQueue.shift()
      if (!next) {
        break
      }
      this.logSystemEvent(`[QUEUE] 处理排队指令 0x${next.type.toString(16).toUpperCase()}`)
      this.dispatchCommand(next)
      guard += 1
    }
  }

  /**
   * 0x01 心跳：只做状态刷新
   */
  private handleHeartbeat(frame: CommandFrame): void {
    this.lastHeartbeatAt = frame.timestamp > 0 ? frame.timestamp : Date.now()
    this.logSystemEvent(`[HEARTBEAT] 心跳正常，lastHeartbeatAt=${this.lastHeartbeatAt}`)
  }

  /**
   * 0x02 障碍检测：
   */
  private handleObstacleDetection(frame: CommandFrame): void {
    this.logSystemEvent('=== 0x02 障碍检测流程开始 ===')
    //障碍方法
    this.barrier(frame)
    this.logSystemEvent('[0x02] Step2 检测到障碍，进入识别')
    //2.若检测到障碍
    const cameraFrame = this.captureCamera()
    const recognitionResult = this.invokeRecognitionModel(cameraFrame)
    //3.识别结果为花生地、施工路段等特殊路况
    this.logSystemEvent(
      `[0x02] Step3 识别结果 type=${recognitionResult.detectedType}, confidence=${recognitionResult.confidence}`
    )
    //4.系统[记录]日志、将信息[上传]云端
    if (this.jilu(recognitionResult)){
      this.shangchuan(recognitionResult,cameraFrame)
    }


    this.logSystemEvent('[0x02] Step5 上传障碍事件到云端队列')
    this.uploadToCloud({
      type: 'OBSTACLE_DETECTION',
      recognitionResult: recognitionResult,
      specialRoads: this.specialRoadsDetected,
      reviewResults: this.reviewResults,
      timestamp: Date.now()
    })
    //5.投递路径重规划指令
    this.replan(recognitionResult)
    this.triggerPathReplan(recognitionResult)
    this.logSystemEvent('=== 0x02 障碍检测流程结束 ===')
  }

  /**
   * 0x03 路径重规划：
   * 1. 解析重规划上下文
   * 2. 确定起终点和阻塞节点
   * 3. 调用扩散路径规划
   * 4. 更新路径并恢复自动导航
   */
  private handlePathReplan(frame: CommandFrame): void {
    this.logSystemEvent('=== 0x03 路径重规划流程开始 ===')

    const replanData = this.normalizeReplanData(frame.data)
    this.logSystemEvent(`[0x03] Step1 重规划原因: ${replanData.reason}`)

    const currentPos = this.getCurrentLocation()
    const targetPos = this.getTargetLocation()
    const blockedNodes = this.collectBlockedNodes(replanData)

    this.logSystemEvent(
      `[0x03] Step2 起点=${currentPos}, 终点=${targetPos}, 阻塞节点=${blockedNodes.length > 0 ? blockedNodes.join(',') : '无'}`
    )

    const newPath = this.replanPathWithDiffusion(currentPos, targetPos, blockedNodes)
    if (newPath.length <= 0) {
      this.logSystemEvent('[0x03] Step3 重规划失败，保持原路径')
      return
    }

    this.updatePath(newPath)
    this.resumeAutoNavigation()

    this.logSystemEvent('[0x03] Step4 路径更新完成，已恢复自动导航')
    this.logSystemEvent('=== 0x03 路径重规划流程结束 ===')
  }

  /**
   * 0x04 紧急停止
   */
  private handleEmergencyStop(frame: CommandFrame): void {
    this.logSystemEvent('!!! 收到 0x04 紧急停止指令 !!!')
    this.stopVehicle()
    this.disableAutoNavigation()
    this.uploadCriticalLog()
  }

  /**
   * 0x05 状态上报
   */
  private handleStatusReport(frame: CommandFrame): void {
    this.logSystemEvent('[0x05] 状态上报请求')
    const status = this.collectSystemStatus()
    this.sendStatusToCloud(status)
  }

  private normalizeRotationFrame(data: any): RotationFrame {
    const timestamp = Number(data?.timestamp) > 0 ? Number(data.timestamp) : Date.now()
    const distance = Number(data?.sensorData?.distance)

    return {
      timestamp: timestamp,
      sensorData: {
        distance: Number.isFinite(distance) ? distance : Number.MAX_SAFE_INTEGER
      }
    }
  }

  private normalizeReplanData(data: any): ReplanData {
    const reason = typeof data?.reason === 'string' && data.reason.length > 0
      ? data.reason
      : '障碍触发重规划'

    const obstacles = Array.isArray(data?.obstacles) ? data.obstacles : []
    const blockedNodes = Array.isArray(data?.blockedNodes) ? data.blockedNodes : []
    const priority = (data?.priority === 'LOW' || data?.priority === 'MEDIUM' || data?.priority === 'HIGH')
      ? data.priority
      : 'HIGH'

    return {
      reason: reason,
      obstacles: obstacles,
      blockedNodes: blockedNodes,
      priority: priority
    }
  }

  /**
   * 障碍检测：示例中用前向距离阈值判断
   */
  private detectObstacle(rotationFrame: RotationFrame): boolean {
    return rotationFrame.sensorData.distance < 100
  }

  /**
   * 拍照抓帧：表演模拟
   */
  private captureCamera(): CameraFrame {
    this.logSystemEvent('[VISION] 捕获摄像头画面')
    return {
      timestamp: Date.now(),
      resolution: '1920x1080',
      format: 'JPEG',
      data: 'camera_frame_data'
    }
  }

  /**
   * 识别推理：表演模拟
   */
  private invokeRecognitionModel(cameraFrame: CameraFrame): RecognitionResult {
    this.logSystemEvent('[VISION] 调用识别模型进行推理')
    return {
      detectedType: 'PEANUT_FIELD',
      confidence: 0.92,
      boundingBox: { x: 100, y: 100, w: 500, h: 400 },
      modelVersion: '1.2.3'
    }
  }

  private jilu(recognitionResult: RecognitionResult): boolean {
    const specialTypes: Array<SpecialRoadType> = ['PEANUT_FIELD', 'CONSTRUCTION', 'WATER_HAZARD', 'STEEP_SLOPE']
    return specialTypes.includes(recognitionResult.detectedType as SpecialRoadType) && recognitionResult.confidence > 0.8
  }

  private shangchuan(recognitionResult: RecognitionResult, cameraFrame: CameraFrame): void {
    this.logSystemEvent('[0x02] Step4 识别到特殊路段，执行特殊处理')

    const imageId = this.saveToSystemAlbum(cameraFrame, recognitionResult)

    const specialSegment: SpecialRoadSegment = {
      location: this.getCurrentLocation(),
      type: recognitionResult.detectedType as SpecialRoadType,
      confidence: recognitionResult.confidence,
      imageId: imageId,
      timestamp: Date.now()
    }
    this.specialRoadsDetected.push(specialSegment)

    const reviewResult = this.performReview(specialSegment)
    this.reviewResults.push(reviewResult)

    this.logSystemEvent(`[0x02] Step4 完成特殊路段处理，imageId=${imageId}`)
  }

  private saveToSystemAlbum(cameraFrame: CameraFrame, recognitionResult: RecognitionResult): string {
    this.logSystemEvent('[MEDIA] 保存画面到系统相册')
    return this.buildId('IMG')
  }

  private performReview(specialSegment: SpecialRoadSegment): ReviewResult {
    this.logSystemEvent(`[REVIEW] 复盘分析: ${specialSegment.type}`)

    return {
      segmentId: specialSegment.imageId,
      detectedType: specialSegment.type,
      confidence: specialSegment.confidence,
      recommendation: `避开 ${specialSegment.type} 区域，建议绕行`,
      affectsPathPlanning: true
    }
  }

  private uploadToCloud(data: any): void {
    this.cloudUploadQueue.push({
      data: data,
      timestamp: Date.now(),
      status: 'PENDING'
    })
    this.logSystemEvent('[CLOUD] 数据已加入上传队列')
  }

  private replan(recognitionResult: RecognitionResult): void {
    const avoidanceDecision: AvoidanceDecision = {
      action: 'TURN_LEFT',
      angle: 45,
      speed: 0.5
    }
    this.logSystemEvent(
      `[0x02] Step6 避障决策: ${avoidanceDecision.action}, angle=${avoidanceDecision.angle}, speed=${avoidanceDecision.speed}`
    )
  }

  private triggerPathReplan(recognitionResult: RecognitionResult): void {
    const replanFrame: CommandFrame = {
      type: CommandType.PATH_REPLAN,
      timestamp: Date.now(),
      data: {
        reason: `检测到${recognitionResult.detectedType}`,
        obstacles: [recognitionResult],
        blockedNodes: [],
        priority: 'HIGH'
      }
    }

    this.commandQueue.push(replanFrame)
    this.logSystemEvent('[0x02] Step7 已投递路径重规划指令到队列')
  }

  private collectBlockedNodes(replanData: ReplanData): Array<string> {
    const nodes: Array<string> = []

    for (let node of replanData.blockedNodes) {
      if (typeof node === 'string' && node.length > 0) {
        nodes.push(node.toUpperCase())
      }
    }

    for (let obstacle of replanData.obstacles) {
      if (typeof obstacle?.nodeId === 'string' && obstacle.nodeId.length > 0) {
        nodes.push(obstacle.nodeId.toUpperCase())
      }
    }

    // 去重
    const unique = Array.from(new Set(nodes))
    return unique
  }

  /**
   * 重规划调用扩散路径算法（对应你的表演规划器）
   */
  private replanPathWithDiffusion(start: string, goal: string, blockedNodes: Array<string>): Array<string> {
    this.logSystemEvent(`[PLANNER] 扩散策略规划: ${start} -> ${goal}`)

    const result = this.pathPlanner.plan(start, goal, blockedNodes)
    if (!result.success || result.path.length <= 0) {
      this.logSystemEvent('[PLANNER] 规划失败：无可行路径')
      return []
    }

    this.logSystemEvent(
      `[PLANNER] 规划成功: pathLen=${result.path.length}, cost=${result.cost}, expanded=${result.expandedNodes}`
    )

    return result.path
  }

  private updatePath(newPath: Array<string>): void {
    this.currentPath = [...newPath]
    this.logSystemEvent(`[PATH] 路径已更新: ${newPath.join(' -> ')}`)
  }

  private resumeAutoNavigation(): void {
    this.autoNavigationEnabled = true
    this.logSystemEvent('[NAV] 自动导航已恢复')
  }

  private stopVehicle(): void {
    this.logSystemEvent('[CAR] 车辆已停止')
  }

  private disableAutoNavigation(): void {
    this.autoNavigationEnabled = false
    this.logSystemEvent('[NAV] 自动导航已禁用')
  }

  private uploadCriticalLog(): void {
    this.logSystemEvent('[CLOUD] 上传关键日志')
  }

  private collectSystemStatus(): VehicleStatus {
    return {
      timestamp: Date.now(),
      position: this.getCurrentLocation(),
      target: this.getTargetLocation(),
      battery: 85,
      temperature: 45,
      autoNavigationEnabled: this.autoNavigationEnabled,
      specialRoadsCount: this.specialRoadsDetected.length,
      queuedCommands: this.commandQueue.length,
      logCount: this.systemLogs.length
    }
  }

  private sendStatusToCloud(status: VehicleStatus): void {
    this.logSystemEvent(`[CLOUD] 状态上报: ${JSON.stringify(status)}`)
  }

  private getCurrentLocation(): string {
    if (this.currentPath.length > 0) {
      return this.currentPath[0]
    }
    return 'D4'
  }

  private getTargetLocation(): string {
    return this.currentTarget
  }

  private buildId(prefix: string): string {
    const randomSuffix = Math.random().toString(36).slice(2, 10)
    return `${prefix}_${Date.now()}_${randomSuffix}`
  }

  private logSystemEvent(message: string): void {
    const logEntry = `[${new Date().toISOString()}] ${message}`
    this.systemLogs.push(logEntry)
    console.log(logEntry)
  }

  getSystemLogs(): Array<string> {
    return this.systemLogs
  }

  getSpecialRoads(): Array<SpecialRoadSegment> {
    return this.specialRoadsDetected
  }

  getReviewResults(): Array<ReviewResult> {
    return this.reviewResults
  }

  getCloudUploadQueue(): Array<any> {
    return this.cloudUploadQueue
  }
  private barrier(frame:CommandFrame){
    const rotationFrame = this.normalizeRotationFrame(frame.data)
    this.logSystemEvent(`[0x02] Step1 接收回传帧 ts=${rotationFrame.timestamp}`)
    const obstacleDetected = this.detectObstacle(rotationFrame)
    if (!obstacleDetected) {
      this.logSystemEvent('[0x02] Step2 未检测到障碍，流程结束')
      return
    }
  }
}
