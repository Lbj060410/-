# HarmonyOS 小车项目 - 离线识别集成现状总结

## 📊 项目背景

**项目**: HarmonyOS ArkTS 小车遥控/自动驾驶 App
**目标**: 实现本地离线图像识别（交通灯、交通标志、形状等）
**工作目录**: `F:\HarmonyOs\car`

---

## 🔴 核心问题

### 问题 1：ONNX Runtime 不可用
- **状态**: ❌ 已尝试集成，失败
- **原因**: ONNX Runtime Android 版本依赖 `libandroid.so`
- **错误**: `dlopen failed: library "libandroid.so" not found`
- **结论**: HarmonyOS 不是 Android，无法使用 Android 版 ONNX Runtime

### 问题 2：MindSpore Lite 不可用
- **状态**: ❌ SDK 中只有 stub 库
- **库大小**: 7KB-28KB（正常应该是 20-50MB）
- **位置**: `F:\HarmonyOs\Sdk\openharmony\9\native\sysroot\usr\lib\`
- **结论**: HarmonyOS SDK 9 不包含完整的 MindSpore Lite 推理引擎

---

## ✅ 已完成的工作

### 1. 代码层面
- ✅ OnnxRecognitionService.ets（ONNX 服务，但无法运行）
- ✅ MindSporeLiteRecognitionService.ets（MindSpore 服务，但库不完整）
- ✅ HttpYoloRecognitionService.ets（HTTP 远程识别，可用但需要网络）
- ✅ NcnnRecognitionService.ets（NCNN 服务，刚创建，待集成）
- ✅ Page2 UI 已支持引擎切换

### 2. 模型文件
- ✅ 17 个 .ms 模型文件（MindSpore 格式，但无法使用）
- ✅ 4 个 .onnx 模型文件（ONNX 格式，但无法使用）
- ❌ 缺少 NCNN 格式模型（.param + .bin）

### 3. 第三方库
- ✅ ONNX Runtime SDK 已安装（但不兼容 HarmonyOS）
- ✅ ZXing-cpp（二维码识别，正常工作）
- ❌ NCNN 库未安装

---

## 🎯 当前方案：集成 NCNN

### 为什么选择 NCNN？
1. ✅ **纯 C++ 实现**，无外部依赖
2. ✅ **支持 ARM64**，性能优秀
3. ✅ **支持 YOLO 模型**
4. ✅ **可编译为 HarmonyOS 原生库**
5. ✅ **社区活跃**，文档完善

### 集成进度
- ✅ 创建了 NcnnRecognitionService.ets（ArkTS 服务层）
- ✅ 创建了目录结构 `third_party/ncnn/`
- ✅ 编写了集成指南 `NCNN_SETUP_GUIDE.md`
- ❌ **待完成**: 下载 NCNN 库
- ❌ **待完成**: 创建 C++ 推理引擎（ncnn_engine.cpp）
- ❌ **待完成**: 修改 CMakeLists.txt
- ❌ **待完成**: 转换模型为 NCNN 格式
- ❌ **待完成**: 更新 RecognitionFactory

---

## 📋 下一步行动

### 立即需要做的（按顺序）

#### 1. 下载 NCNN 库
- **地址**: https://github.com/Tencent/ncnn/releases
- **文件**: ncnn-YYYYMMDD-android-vulkan.zip（最新版本）
- **大小**: 约 10-50MB

#### 2. 复制文件到项目
```
third_party/ncnn/
├── include/ncnn/*.h        ← 从下载包复制
└── lib/arm64-v8a/libncnn.a ← 从下载包复制
```

#### 3. 转换模型
需要把 4 个 ONNX 模型转换为 NCNN 格式：
- honglvdeng.onnx → honglvdeng.param + honglvdeng.bin
- traffic_sign.onnx → traffic_sign.param + traffic_sign.bin
- shape.onnx → shape.param + shape.bin
- Car_plant_more2.onnx → Car_plant_more2.param + Car_plant_more2.bin

#### 4. 我会帮你完成
- 创建 ncnn_engine.cpp（C++ 推理引擎）
- 修改 CMakeLists.txt（链接 NCNN 库）
- 更新 RecognitionFactory.ets（支持 NCNN 引擎）
- 更新 RecognitionConfig.ets（添加 OFFLINE_NCNN 类型）
- 测试编译和运行

---

## 🔧 技术细节

### 当前引擎类型
```typescript
enum RecogEngineType {
  MOCK = 0,           // 模拟引擎
  HTTP_YOLO = 1,      // HTTP 远程识别（可用）
  OFFLINE_MS = 2,     // MindSpore Lite（不可用）
  OFFLINE_ONNX = 3,   // ONNX Runtime（不可用）
  OFFLINE_NCNN = 4    // NCNN（待集成）← 新增
}
```

### 识别流程
```
用户点击识别按钮
    ↓
RecognitionScheduler 调度
    ↓
RecognitionFactory 创建引擎
    ↓
NcnnRecognitionService.recognize()
    ↓
Native Bridge (LibEntryBridge)
    ↓
ncnn_engine.cpp (C++)
    ↓
NCNN 推理
    ↓
返回识别结果
```

---

## 📊 文件清单

### 已创建的文件
1. `NcnnRecognitionService.ets` - NCNN 识别服务（ArkTS）
2. `NCNN_SETUP_GUIDE.md` - NCNN 集成指南
3. `ONNX_ISSUE_SUMMARY.md` - ONNX 问题总结
4. `MINDSPORE_ISSUE.md` - MindSpore 问题分析
5. `MINDSPORE_DOWNLOAD_GUIDE.md` - MindSpore 下载指南
6. `LOCAL_INFERENCE_SOLUTIONS.md` - 本地推理方案对比
7. `ONNX_INTEGRATION.md` - ONNX 集成报告
8. `ONNX_REBUILD_GUIDE.md` - ONNX 重编译指南

### 待创建的文件
1. `ncnn_engine.cpp` - NCNN C++ 推理引擎
2. 更新 `CMakeLists.txt` - 添加 NCNN 链接
3. 更新 `RecognitionFactory.ets` - 支持 NCNN
4. 更新 `RecognitionConfig.ets` - 添加 OFFLINE_NCNN

---

## 💡 关键决策点

### 为什么不用 HTTP YOLO？
- ❌ 需要网络连接
- ❌ 延迟高（100-500ms）
- ❌ 不适合小车实时控制

### 为什么不继续找 MindSpore Lite？
- ❌ 官方下载页面可能没有 OpenHarmony 9 版本
- ❌ 即使找到也可能版本不匹配
- ✅ NCNN 更容易获取和集成

### 为什么不从源码编译 ONNX Runtime？
- ❌ 工作量大（1-3 天）
- ❌ 需要配置 HarmonyOS 工具链
- ❌ 可能遇到兼容性问题

---

## 🎯 预期结果

集成 NCNN 后：
- ✅ 本地离线识别，无需网络
- ✅ 识别速度：50-200ms/帧
- ✅ 支持 4 种模型（交通灯、交通标志、形状、植物）
- ✅ 在 Page2 可以切换到 NCNN 引擎
- ✅ 识别结果正常显示

---

## 📞 当前状态

**等待用户操作**：
1. 下载 NCNN 预编译包
2. 复制文件到项目
3. 告知完成情况

**我会立即完成**：
1. 创建 C++ 推理引擎
2. 修改构建配置
3. 集成到识别系统
4. 测试验证

---

## 📚 参考资料

- NCNN GitHub: https://github.com/Tencent/ncnn
- NCNN 文档: https://github.com/Tencent/ncnn/wiki
- HarmonyOS NDK: https://developer.harmonyos.com/cn/docs/documentation/doc-guides-V3/ndk-development-overview-0000001281201350-V3

---

**总结**: 项目已经完成了大部分代码准备工作，现在只需要下载 NCNN 库和转换模型，就可以实现本地离线识别功能。
