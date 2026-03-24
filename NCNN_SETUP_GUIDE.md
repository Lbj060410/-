# NCNN 集成指南

## 📥 步骤 1：下载 NCNN

### 方法 A：下载预编译版本（推荐，最快）

访问：https://github.com/Tencent/ncnn/releases

下载：
- **ncnn-YYYYMMDD-android-vulkan.zip** (选择最新版本)
- 或 **ncnn-android-lib.zip**

### 方法 B：从源码编译（完整控制）

```bash
# 克隆仓库
git clone https://github.com/Tencent/ncnn.git
cd ncnn
git submodule update --init

# 编译 Android 版本（可用于 HarmonyOS）
mkdir build-android && cd build-android
cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI="arm64-v8a" \
      -DANDROID_PLATFORM=android-21 \
      -DCMAKE_BUILD_TYPE=Release \
      -DNCNN_VULKAN=OFF \
      ..
make -j4
```

## 📦 步骤 2：复制文件到项目

下载/编译完成后，复制以下文件：

### 目录结构
```
third_party/ncnn/
├── include/
│   ├── ncnn/
│   │   ├── allocator.h
│   │   ├── benchmark.h
│   │   ├── blob.h
│   │   ├── cpu.h
│   │   ├── datareader.h
│   │   ├── gpu.h
│   │   ├── layer.h
│   │   ├── mat.h
│   │   ├── modelbin.h
│   │   ├── net.h
│   │   ├── option.h
│   │   ├── paramdict.h
│   │   └── platform.h
└── lib/
    ├── arm64-v8a/
    │   └── libncnn.a  (约 2-5MB)
    ├── armeabi-v7a/
    │   └── libncnn.a
    └── x86_64/
        └── libncnn.a
```

### 从预编译包复制
```bash
# 解压下载的文件
unzip ncnn-YYYYMMDD-android-vulkan.zip

# 复制头文件
cp -r ncnn-android-vulkan/arm64-v8a/include/ncnn F:/HarmonyOs/car/third_party/ncnn/include/

# 复制库文件
cp ncnn-android-vulkan/arm64-v8a/lib/libncnn.a F:/HarmonyOs/car/third_party/ncnn/lib/arm64-v8a/
cp ncnn-android-vulkan/armeabi-v7a/lib/libncnn.a F:/HarmonyOs/car/third_party/ncnn/lib/armeabi-v7a/
cp ncnn-android-vulkan/x86_64/lib/libncnn.a F:/HarmonyOs/car/third_party/ncnn/lib/x86_64/
```

## 🔄 步骤 3：转换模型

NCNN 需要 `.param` 和 `.bin` 格式的模型。

### 从 ONNX 转换

```bash
# 下载 NCNN 工具
# 在 ncnn/build/tools/onnx/ 目录下

# 转换模型
./onnx2ncnn model.onnx model.param model.bin

# 优化模型（可选）
./ncnnoptimize model.param model.bin model-opt.param model-opt.bin 0
```

### 需要转换的模型
```
honglvdeng.onnx → honglvdeng.param + honglvdeng.bin
traffic_sign.onnx → traffic_sign.param + traffic_sign.bin
shape.onnx → shape.param + shape.bin
Car_plant_more2.onnx → Car_plant_more2.param + Car_plant_more2.bin
```

转换后放到：
```
entry/src/main/resources/rawfile/
├── honglvdeng.param
├── honglvdeng.bin
├── traffic_sign.param
├── traffic_sign.bin
└── ...
```

## 🎯 下一步

完成上述步骤后，告诉我，我会：
1. 创建 NCNN 推理服务代码
2. 修改 CMakeLists.txt
3. 集成到识别系统

## 📝 快速检查清单

- [ ] 下载 NCNN 预编译包
- [ ] 复制头文件到 `third_party/ncnn/include/`
- [ ] 复制库文件到 `third_party/ncnn/lib/arm64-v8a/`
- [ ] 转换 ONNX 模型为 NCNN 格式
- [ ] 复制 .param 和 .bin 文件到 rawfile

完成后告诉我，我会继续下一步！
