# ncnn 集成指南

## ✅ 已完成的工作

### 1. C++ 层
- ✅ 创建 `ncnn_detector.cpp`（stub 模式，等待 ncnn 库）
- ✅ 修改 `hello.cpp` 注册 ncnn 导出函数
- ✅ 修改 `CMakeLists.txt` 支持 ncnn 库链接

### 2. TypeScript 层
- ✅ 添加 `RecogEngineType.OFFLINE_NCNN = 4`
- ✅ 已有 `NcnnRecognitionService.ets`（完整实现）
- ✅ 更新 `RecognitionFactory` 支持 ncnn
- ✅ 更新 `LibEntryBridge` 添加 ncnn API

## 📋 下一步：集成真实 ncnn 库

### 步骤 1：下载/编译 ncnn for HarmonyOS

```bash
# 克隆 ncnn 仓库
git clone https://github.com/Tencent/ncnn.git
cd ncnn

# 使用 HarmonyOS NDK 编译
mkdir build-harmonyos && cd build-harmonyos

cmake -DCMAKE_TOOLCHAIN_FILE=$OHOS_NDK_HOME/native/build/cmake/ohos.toolchain.cmake \
      -DOHOS_ARCH=arm64-v8a \
      -DCMAKE_BUILD_TYPE=Release \
      -DNCNN_VULKAN=OFF \
      -DNCNN_BUILD_EXAMPLES=OFF \
      -DNCNN_BUILD_TOOLS=OFF \
      ..

make -j4
```

### 步骤 2：复制 ncnn 库到项目

```
car/third_party/ncnn/
├── include/
│   ├── net.h
│   ├── mat.h
│   └── ...
└── lib/
    └── arm64-v8a/
        └── libncnn.a
```

### 步骤 3：取消注释 C++ 代码

在 `ncnn_detector.cpp` 中：
1. 取消注释 `#include "net.h"` 和 `#include "mat.h"`
2. 取消注释 `static ncnn::Net g_net;`
3. 取消注释 `LoadNcnnModel` 和 `DetectNcnn` 中的真实推理代码

### 步骤 4：准备模型文件

将 YOLO 模型转换为 ncnn 格式：

```bash
# 使用 ncnn 工具转换 ONNX 模型
./onnx2ncnn yolov8n.onnx yolov8n.param yolov8n.bin
```

放置到：
```
car/entry/src/main/resources/rawfile/ncnn_models/
├── yolov8n.param
└── yolov8n.bin
```

### 步骤 5：测试

在 Page2 中选择 "NCNN" 引擎，触发识别任务。

## 🔧 当前状态

- **框架层**：✅ 完成（stub 模式可编译运行）
- **ncnn 库**：⏳ 待集成
- **模型文件**：⏳ 待转换

## 📝 API 接口

### C++ 导出函数

```cpp
// 加载模型（从 ArrayBuffer）
bool loadNcnnModel(string modelName, ArrayBuffer paramBuf, ArrayBuffer binBuf)

// 推理（返回 JSON 字符串）
string detectNcnn(string modelName, ArrayBuffer rgba, int w, int h, double conf, double nms)

// 获取错误信息
string getNcnnLastError()
```

### TypeScript 使用

```typescript
import { RecogEngineType } from './RecognitionConfig'

// 设置引擎为 ncnn
recogStore.setRecogEngineType(RecogEngineType.OFFLINE_NCNN)

// 自动调用 NcnnRecognitionService
const result = await recognitionService.recognize(pixelMap)
```

## ⚠️ 注意事项

1. **ncnn 库必须针对 HarmonyOS ARM64 编译**
2. **模型文件必须是 ncnn 格式（.param + .bin）**
3. **当前代码是 stub 模式，返回模拟数据**
4. **集成真实库后需要实现 YOLOv8 输出解析和 NMS**

## 🎯 优势

相比 MS/ONNX：
- ✅ 纯 C++ 实现，不依赖系统库
- ✅ 体积更小（~2MB vs 20MB+）
- ✅ 性能更好（ARM NEON 优化）
- ✅ 模型生态丰富（YOLO 全系列）
- ✅ 跨平台兼容性强
