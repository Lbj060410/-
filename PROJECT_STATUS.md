# HarmonyOS 小车项目 - 识别模块迁移状态

**日期**: 2026-03-05
**目标**: 将安卓项目的 TensorFlow Lite 识别能力迁移到 HarmonyOS

---

## ✅ 已完成的工作

### 1. 问题诊断
- **根本原因**: MindSpore Lite 模型加载失败（版本不兼容）
  - 日志显示: `MSLOAD|model=screen1|ok=0|st=-1` (所有设备类型加载失败)
  - 转换器版本: MindSpore Lite 2.0.0 (Windows x64)
  - 运行时库: `libmindspore-lite.huawei.so` 仅 7.2KB (应为 5-10MB)
  - 结论: 转换器是 Windows 版本，HarmonyOS 需要 ARM64 版本

### 2. 参数修复（已完成）
- ✅ **NMS 阈值**: `0.45` → `0.6` (匹配安卓 YoloV5Classifier.mNmsThresh)
  - 文件: `entry/src/main/cpp/infer_engine.cpp:1153`
- ✅ **置信度阈值**: `0.4` → `0.3` (匹配安卓 MINIMUM_CONFIDENCE_TF_OD_API)
  - 文件: `entry/src/main/ets/services/recognition/RecognitionConfig.ets:19`
  - 文件: `entry/src/main/ets/state/RecogStore.ets:39`

### 3. 架构分析
- ✅ HarmonyOS 项目已有完整的 MindSpore Lite 架构
  - `MindSporeLiteRecognitionService.ets` (ArkTS 层)
  - `infer_engine.cpp` (Native C++ 推理引擎)
  - `LibEntryBridge.ets` (Native 桥接)
- ✅ 识别调度器已实现: `RecognitionScheduler` (LIVE + SNAPSHOT 双模调度)
- ✅ 模型标签映射已配置: `RecognitionFactory.ets` (MODEL_LABELS)

### 4. 现有资源
- ✅ 安卓项目模型位置: `F:\Androidcar\ML_lik_car (3)\ML_lik_car\app\src\main\assets`
  - 核心模型: `traffic_sign-fp16.tflite`, `honglvdeng-fp16.tflite`, `Car_plant_*.tflite`
  - 已有 ONNX: `xingzhuang1.onnx` (28MB), `color3.onnx` (28MB)
- ✅ HarmonyOS rawfile 目录: `F:\HarmonyOs\car\entry\src\main\resources\rawfile`
  - 现有 .ms 模型 (不可用): `traffic_sign.ms`, `honglvdeng.ms`, 等

---

## ❌ 未解决的问题

### 核心问题: 模型格式不兼容
**当前状态**:
- MindSpore Lite 模型无法加载 (st=-1 错误)
- 系统使用 fallback 算法 (图像处理，非 ML)
- 实际识别效果: 14 个形状图像一个都检测不到

**原因**:
- MindSpore Lite 2.0.0 (Windows x64) 与 HarmonyOS ARM64 运行时不兼容
- `.ms` 模型文件可能格式错误或版本不匹配

---

## 🎯 下一步行动方案

### 方案 A: 转换为 ONNX 模型（推荐）

**为什么选 ONNX**:
- HarmonyOS 对 ONNX Runtime 支持更好
- 安卓项目已有 ONNX 模型 (xingzhuang1.onnx, color3.onnx)
- 跨平台兼容性强

**需要执行的步骤**:

#### 1. 安装转换工具
```bash
pip install tf2onnx onnx tensorflow
```

#### 2. 转换核心模型 (.tflite → .onnx)
```bash
# 交通标志
python -m tf2onnx.convert \
  --tflite "F:\Androidcar\ML_lik_car (3)\ML_lik_car\app\src\main\assets\traffic_sign-fp16.tflite" \
  --output "F:\HarmonyOs\car\entry\src\main\resources\rawfile\traffic_sign.onnx" \
  --opset 13

# 红绿灯
python -m tf2onnx.convert \
  --tflite "F:\Androidcar\ML_lik_car (3)\ML_lik_car\app\src\main\assets\honglvdeng-fp16.tflite" \
  --output "F:\HarmonyOs\car\entry\src\main\resources\rawfile\honglvdeng.onnx" \
  --opset 13

# 车牌
python -m tf2onnx.convert \
  --tflite "F:\Androidcar\ML_lik_car (3)\ML_lik_car\app\src\main\assets\Car_plant_more2.tflite" \
  --output "F:\HarmonyOs\car\entry\src\main\resources\rawfile\Car_plant_more2.onnx" \
  --opset 13
```

#### 3. 创建 ONNX Runtime 推理服务
**需要实现的文件**:
- `entry/src/main/ets/services/recognition/OnnxRecognitionService.ets`
- `entry/src/main/cpp/onnx_infer_engine.cpp` (或修改现有 infer_engine.cpp)
- 更新 `RecognitionFactory.ets` 添加 `RecogEngineType.OFFLINE_ONNX`

#### 4. 集成到现有架构
- 修改 `RecognitionFactory.create()` 支持 ONNX 引擎
- 更新 `SUBTYPE_MODEL` 映射使用 .onnx 模型
- 测试 Page2/Page4 识别功能

---

## 📋 待转换的模型列表

| 模型名称 | 用途 | 优先级 | 标签文件 |
|---------|------|--------|---------|
| `traffic_sign-fp16.tflite` | 交通标志识别 | ⭐⭐⭐ | no_pass, no_straight, turn_left, go_straight, turn_right, turn_around |
| `honglvdeng-fp16.tflite` | 红绿灯识别 | ⭐⭐⭐ | red, yellow, green |
| `Car_plant_more2.tflite` | 车牌识别（多类） | ⭐⭐⭐ | yellow_plant, blue_plant, green_plant |
| `Car_plant_one.tflite` | 车牌检测 | ⭐⭐ | plant |
| `JT_BZ_mini.tflite` | 交通标志（备用） | ⭐⭐ | turn_around, no_straight, go_straight, no_passing, turn_left, turn_right |
| `car_recongnize-fp16.tflite` | 车辆识别 | ⭐ | cycle, moto, car, truck |
| `wwss-fp16.tflite` | 物体识别 | ⭐ | (需查看 wwss.txt) |
| `screen1-fp16.tflite` | 屏幕定位 | ⭐ | screen, background |

---

## 🔧 技术细节

### 安卓项目识别架构
- **框架**: TensorFlow Lite 2.15.0
- **核心类**: `YoloV5Classifier.java` (本地推理)
- **预处理**: 直接 resize 到 640×640 (不使用 letterbox)
- **后处理**: NMS 阈值 0.6, 置信度阈值 0.3
- **输入格式**: NHWC, RGB, float32, 归一化 [0,1]

### HarmonyOS 项目识别架构
- **当前**: MindSpore Lite (不可用)
- **目标**: ONNX Runtime
- **预处理**: 已实现 `preprocessNhwc()` (640×640 双线性插值)
- **后处理**: 已实现 NMS (已修复为 0.6), 置信度已修复为 0.3
- **Native 桥接**: `LibEntryBridge` → `libentry.so`

---

## 🐛 已知问题

1. **Python 环境问题**: 在 bash 环境中无法执行 Python (exit code 49)
   - 解决方案: 用户需在本地 Windows PowerShell/CMD 中手动执行转换

2. **MindSpore Lite 运行时缺失**: `libmindspore-lite.huawei.so` 仅 7.2KB
   - 解决方案: 放弃 MindSpore Lite, 改用 ONNX Runtime

3. **模型转换工具未安装**: tf2onnx 未安装
   - 解决方案: 用户需执行 `pip install tf2onnx onnx tensorflow`

---

## 📝 下次对话提示词

```
我们正在将安卓项目的 TensorFlow Lite 识别迁移到 HarmonyOS。

当前状态:
1. MindSpore Lite 模型加载失败（版本不兼容，st=-1 错误）
2. 已修复 NMS 阈值（0.6）和置信度阈值（0.3）
3. 决定改用 ONNX Runtime 方案

下一步:
1. 用户需手动转换 .tflite → .onnx（traffic_sign, honglvdeng, Car_plant_more2）
2. 需要创建 OnnxRecognitionService.ets 和对应的 Native C++ 代码
3. 集成到现有 RecognitionFactory

项目路径:
- 安卓模型: F:\Androidcar\ML_lik_car (3)\ML_lik_car\app\src\main\assets
- HarmonyOS: F:\HarmonyOs\car
- rawfile: F:\HarmonyOs\car\entry\src\main\resources\rawfile

请继续帮我完成 ONNX Runtime 推理服务的实现。
```

---

## 📂 关键文件位置

### 需要修改的文件
- `entry/src/main/ets/services/recognition/RecognitionFactory.ets` (添加 ONNX 支持)
- `entry/src/main/cpp/infer_engine.cpp` (添加 ONNX 推理逻辑)
- `entry/src/main/cpp/CMakeLists.txt` (链接 ONNX Runtime 库)

### 参考文件
- `entry/src/main/ets/services/recognition/MindSporeLiteRecognitionService.ets` (架构参考)
- `entry/src/main/ets/services/recognition/HttpYoloRecognitionService.ets` (接口参考)

---

**最后更新**: 2026-03-05 22:30
**状态**: 等待用户完成模型转换
