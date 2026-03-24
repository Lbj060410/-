# .glb 模型接入完整指南

## 一、准备工作

### 1.1 下载 tinygltf 库

**方式 1：手动下载（推荐）**
```bash
# 访问 GitHub 下载单头文件
https://github.com/syoyo/tinygltf/blob/release/tiny_gltf.h

# 保存到项目
third_party/tinygltf/tiny_gltf.h
```

**方式 2：使用 git submodule**
```bash
cd third_party
git submodule add https://github.com/syoyo/tinygltf.git
```

### 1.2 放置 .glb 模型文件

```
entry/src/main/resources/rawfile/models/
├── car_model_1.glb  # 第一个小车模型
└── car_model_2.glb  # 第二个小车模型
```

**注意**：
- HarmonyOS rawfile 目录下的文件会打包到 HAP，运行时可通过资源管理器读取
- 模型文件大小建议 < 5MB（避免加载时间过长）
- 支持 glTF 2.0 规范（.glb 是二进制格式）

---

## 二、已完成的代码

### 2.1 C++ 层

**已创建文件**：
- `glb_loader.h` — GLB 加载器头文件
- `glb_loader.cpp` — GLB 加载器实现
- `scene3d_renderer.cpp` — 已更新，支持两个模型

**核心功能**：
- ✅ 从 rawfile 加载 .glb 文件
- ✅ 解析顶点/索引/纹理数据
- ✅ 上传到 OpenGL ES（VAO/VBO/EBO）
- ✅ 支持两个模型实例
- ✅ 运行时切换模型

### 2.2 ArkTS 层

**已更新文件**：
- `Scene3DNativeApi.ets` — 添加 `switchCarModel()` 接口

**已更新构建配置**：
- `CMakeLists.txt` — 添加 glb_loader.cpp + tinygltf 头文件路径

---

## 三、使用方法

### 3.1 在 Page3View 中切换模型

```typescript
import { Scene3DNativeApi } from '../../services/render3d/Scene3DNativeApi'
import { page3Store } from './Page3Store'

@Component
export struct Page3View {
  private nativeApi: Scene3DNativeApi = new Scene3DNativeApi()

  build() {
    Column() {
      // XComponent 渲染表面
      XComponent({
        id: 'scene3d',
        type: 'surface',
        libraryname: 'entry'
      })
        .onLoad((context) => {
          this.nativeApi.init(context.width, context.height)
          // 模型会在 init 时自动加载
        })
        .width('100%')
        .height('70%')

      // 模型切换按钮
      Row({ space: 12 }) {
        Button('模型 1')
          .onClick(() => {
            this.nativeApi.switchCarModel(0)
            page3Store.scene.activeCarModel = 0
          })

        Button('模型 2')
          .onClick(() => {
            this.nativeApi.switchCarModel(1)
            page3Store.scene.activeCarModel = 1
          })
      }
      .margin({ top: 12 })
    }
  }
}
```

### 3.2 自动切换模型（根据状态）

在 `Page3Coordinator.ets` 中根据小车状态自动切换：

```typescript
private syncToNative(): void {
  if (!this.store.nativeReady) return

  // 根据速度切换模型（示例）
  const speed = this.page1.telemetry.speed
  const newModelIndex = (speed > 50) ? 1 : 0  // 高速用模型2，低速用模型1

  if (this.store.scene.activeCarModel !== newModelIndex) {
    this.nativeApi.switchCarModel(newModelIndex)
    this.store.scene.activeCarModel = newModelIndex
  }

  // ... 其他同步逻辑
}
```

---

## 四、模型要求与优化

### 4.1 模型规范

**支持的格式**：
- glTF 2.0 二进制格式（.glb）
- 包含 Mesh、Material、Texture

**推荐规范**：
- 顶点数：< 10,000（移动端性能考虑）
- 纹理分辨率：512×512 或 1024×1024
- 材质：PBR（Metallic-Roughness）
- 动画：暂不支持（后续可扩展）

### 4.2 模型优化建议

**Blender 导出设置**：
```
File → Export → glTF 2.0 (.glb)
- Format: glTF Binary (.glb)
- Include: Selected Objects
- Transform: +Y Up
- Geometry: Apply Modifiers
- Compression: Draco (可选，减小文件大小)
```

**优化工具**：
- [gltf-pipeline](https://github.com/CesiumGS/gltf-pipeline) — 压缩/优化 glTF
- [Draco](https://github.com/google/draco) — 几何压缩

---

## 五、调试与验证

### 5.1 验证模型加载

**查看日志**：
```bash
hdc shell hilog | grep Scene3D
```

**预期输出**：
```
[INFO][Scene3D] Loaded car_model_1.glb
[INFO][Scene3D] Loaded car_model_2.glb
[GLBLoader] Loaded model: 3 meshes, 2 materials
[GLBLoader] Uploaded 3 meshes to OpenGL
```

### 5.2 常见问题

**Q1: 模型不显示？**
- 检查 rawfile 路径是否正确（`models/car_model_1.glb`）
- 检查 EGL 是否初始化成功
- 检查 shader 是否编译成功
- 查看 hilog 错误日志

**Q2: 模型显示异常（拉伸/变形）？**
- 检查模型坐标系（glTF 使用右手坐标系，Y 轴向上）
- 调整 Model 矩阵的缩放/旋转
- 验证顶点数据是否正确解析

**Q3: 纹理丢失？**
- 确认 .glb 文件包含嵌入纹理（不是外部引用）
- 检查 `LoadTexture()` 是否成功创建 OpenGL 纹理
- 验证 shader 是否绑定纹理采样器

**Q4: 性能差/卡顿？**
- 减少顶点数（使用 LOD）
- 降低纹理分辨率
- 启用 Draco 压缩
- 检查是否每帧重复上传数据（应只上传一次）

---

## 六、扩展功能

### 6.1 支持动画

tinygltf 支持解析 glTF 动画，可扩展：
```cpp
// 解析动画
for (const auto& animation : gltfModel->animations) {
    // 提取关键帧数据
    // 实现骨骼动画插值
}
```

### 6.2 支持多个模型实例

当前支持两个模型，可扩展为数组：
```cpp
struct Scene3DState {
    std::vector<Model> carMo // 多个模型
    int activeCarModel = 0;
};
```

### 6.3 支持材质切换

可在运行时切换材质颜色：
```cpp
static napi_value Scene3DSetCarColor(napi_env env, napi_callback_info info) {
    // 修改 material.baseColorFactor
    // 无需重新加载模型
}
```

---

## 七、完整文件清单

### 已创建/修改的文件

**C++ 层**：
- ✅ `cpp/glb_loader.h` — GLB 加载器头文件
- ✅ `cpp/glb_loader.cpp` — GLB 加载器实现
- ✅ `cpp/scene3d_renderer.cpp` — 更新渲染器支持 GLB
- ✅ `cpp/hello.cpp` — 注册 Scene3D 模块
- ✅ `cpp/CMakeLists.txt` — 添加 glb_loader.cpp + tinygltf

**ArkTS 层**：
- ✅ `services/render3d/Scene3DNativeApi.ets` — 添加 switchCarModel()
- ✅ `pages/page3/Page3Store.ets` — 添加 activeCarModel 状态
- ✅ `pages/page3/Page3Coordinator.ets` — 数据同步协调器

**待完成**：
- ⏳ `third_party/tinygltf/tiny_gltf.h` — 需手动下载
- ⏳ `resources/rawfile/models/car_model_1.glb` — 需放置模型文件
- ⏳ `resources/rawfile/models/car_model_2.glb` — 需放置模型文件
- ⏳ `pages/page3/Page3View.ets` — 需更新 UI（添加 XComponent）

---

## 八、下一步

1. **下载 tinygltf**：
   ```bash
   cd third_party
   mkdir tinygltf
   # 下载 tiny_gltf.h 到该目录
   ```

2. **放置模型文件**：
   ```bash
   mkdir -p entry/src/main/resources/rawfile/models
   # 复制 car_model.glb 和 car_model_2.glb 到该目录
   ```

3. **更新 Page3View**：
   - 添加 XComponent
   - 添加模型切换按钮
   - 绑定生命周期回调

4. **编译测试**：
   ```bash
   # DevEco Studio 中点击 Build → Make Module 'entry'
   # 查看编译日志，确认无错误
   ```

5. **运行验证**：
   - 切换到 Page3
   - 查看 3D 模型是否正常显示
   - 点击切换按钮，验证模型切换

---

## 九、参考资料

- [tinygltf GitHub](https://github.com/syoyo/tinygltf)
- [glTF 2.0 规范](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
- [HarmonyOS XComponent 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/arkts-common-components-xcomponent-V5)
- [OpenGL ES 3.2 规范](https://registry.khronos.org/OpenGL/specs/es/3.2/es_spec_3.2.pdf)

---

## 十、技术支持

遇到问题可查看：
- `docs/Page3_3D_Integration_Checklist.md` — 3D 接入总体清单
- HarmonyOS 官方论坛
- tinygltf Issues
