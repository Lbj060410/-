# Page3 3D 模型接入准备清单

## 已完成 ✅

### 1. 架构设计
- [x] Page3Store.ets — 3D 场景状态管理
- [x] Page3Coordinator.ets — 数据同步协调器（page1/recog → 3D）
- [x] Scene3DNativeApi.ets — NAPI 桥接层
- [x] scene3d_renderer.cpp — Native 渲染器骨架
- [x] CMakeLists.txt — 添加 OpenGL ES / EGL 链接
- [x] hello.cpp — 注册 Scene3D NAPI 模块

---

## 待完成 TODO

### 2. Native 层实现（C++）

#### 2.1 EGL 初始化（高优先级）
**文件**：`scene3d_renderer.cpp`

**任务**：
- [ ] 从 XComponent 获取 NativeWindow
- [ ] 完整 EGL 初始化流程（display/config/surface/context）
- [ ] 错误处理与日志

**参考**：
```cpp
// XComponent 回调获取 NativeWindow
OH_NativeXComponent_Callback callback;
callback.OnSurfaceCreated = [](OH_NativeXComponent* component, void* window) {
    // window 即 NativeWindow*
    InitEGL(window);
};
```

#### 2.2 着色器编译（高优先级）
**文件**：`scene3d_renderer.cpp`

**任务**：
- [ ] 顶点着色器（MVP 变换）
- [ ] 片段着色器（纯色/纹理）
- [ ] Shader 编译/链接错误处理

#### 2.3 几何体生成（中优先级）
**文件**：`scene3d_renderer.cpp` 或新建 `geometry_builder.cpp`

**任务**：
- [ ] 简单立方体（代表小车）
- [ ] 地面网格（5×5 节点）
- [ ] 路径线（LineStrip）
- [ ] 障碍物标记（红色圆柱）

#### 2.4 MVP 矩阵计算（高优先级）
**依赖**：GLM 数学库（需添加到 third_party）

**任务**：
- [ ] Model 矩阵：根据 carX/carY/carHeading 计算
- [ ] View 矩阵：根据 cameraMode 计算（跟随/鸟瞰/自由）
- [ ] Projection 矩阵：透视投影

**GLM 集成**：
```cmake
# CMakeLists.txt
set(GLM_INCLUDE_DIR "${PROJECT_ROOT_PATH}/third_party/glm")
include_directories(${GLM_INCLUDE_DIR})
```

#### 2.5 模型加载（低优先级，可选）
**依赖**：Assimp 库

**任务**：
- [ ] 加载 .obj / .fbx 小车模型
- [ ] 纹理加载
- [ ] 骨骼动画（可选）

**初期替代方案**：用简单几何体（立方体 + 圆锥表示车头方向）

---

### 3. ArkTS 层实现

#### 3.1 更新 Page3View（高优先级）
**文件**：`pages/page3/Page3View.ets`

**任务**：
- [ ] 添加 XComponent（3D 渲染表面）
- [ ] 绑定 XComponent 生命周期回调
- [ ] 创建 Page3Coordinator 实例
- [ ] 添加相机控制 UI（切换模式/缩放/旋转）
- [ ] 添加渲染选项开关（网格/路径/障碍物）

**示例代码**：
```typescript
XComponent({
  id: 'scene3d',
  type: 'surface',
  libraryname: 'entry'
})
  .onLoad((context) => {
    // 初始化 Native 渲染器
    this.nativeApi.init(context.width, context.height)
    this.coordinator.onNativeReady()
  })
  .onDestroy(() => {
    this.coordinator.onNativeDestroy()
    this.nativeApi.destroy()
  })
  .width('100%')
  .height('60%')
```

#### 3.2 实现 Scene3DNativeApi（高优先级）
**文件**：`services/render3d/Scene3DNativeApi.ets`

**任务**：
- [ ] 替换所有 `// TODO` 为真实 NAPI 调用
- [ ] 导入 libentry 模块
- [ ] 错误处理

**示例**：
```typescript
import libentry from 'libentry.so'

init(width: number, height: number): void {
  libentry.scene3dInit(width, height)
}
```

#### 3.3 Page3Coordinator 启动/停止（中优先级）
**文件**：`pages/page3/Page3View.ets`

**任务**：
- [ ] 在 `aboutToAppear()` 启动 coordinator
- [ ] 在 `aboutToDisappear()` 停止 coordinator

---

### 4. 依赖库集成

#### 4.1 GLM 数学库（必需）
**下载**：https://github.com/g-truc/glm/releases

**集成步骤**：
1. 解压到 `third_party/glm/`
2. CMakeLists.txt 添加 include 路径
3. 验证：`#include <glm/glm.hpp>`

#### 4.2 Assimp 模型加载（可选）
**下载**：https://github.com/assimp/assimp

**集成步骤**：
1. 编译 HarmonyOS 版本（需交叉编译）
2. 放到 `third_party/assimp/`
3. CMakeLists.txt 链接 libassimp.a

**初期替代**：手写简单 .obj 解析器或用几何体

---

### 5. 测试与调试

#### 5.1 渲染验证（高优先级）
- [ ] 纯色清屏（验证 EGL 正常）
- [ ] 绘制单个立方体（验证 shader/VAO/VBO）
- [ ] 立方体旋转动画（验证 MVP 矩阵）

#### 5.2 数据同步验证（高优先级）
- [ ] Page1 移动小车 → Page3 立方体跟随
- [ ] Page1 规划路径 → Page3 显示路径线
- [ ] Page1 添加障碍 → Page3 显示红色标记

#### 5.3 性能测试（中优先级）
- [ ] FPS 监控（目标 30+ FPS）
- [ ] 内存泄漏检查（EGL/OpenGL 资源释放）
- [ ] 多次切换 Page1/Page3 稳定性

---

## 开发顺序建议

### 阶段 1：最小可行渲染（1-2 天）
1. 完成 EGL 初始化
2. 编译简单 shader
3. 绘制纯色立方体
4. 验证 XComponent 生命周期

### 阶段 2：数据同步（1 天）
1. 实现 Scene3DNativeApi NAPI 调用
2. Page3Coordinator 启动/停止
3. 验证 page1Store → Native 数据流

### 阶段 3：场景元素（2-3 天）
1. 地面网格
2. 路径线
3. 障碍物标记
4. 小车模型（简单几何体）

### 阶段 4：相机控制（1 天）
1. 鸟瞰模式
2. 跟随模式
3. 缩放/旋转

### 阶段 5：优化与美化（可选）
1. 加载真实 3D 模型
2. 纹理/光照
3. 阴影
4. 粒子效果

---

## 常见问题 FAQ

### Q1: XComponent 黑屏？
**A**: 检查 EGL 初始化是否成功，查看 hilog 错误日志。

### Q2: 数据不同步？
**A**: 确认 Page3Coordinator 已启动，检查 `nativeReady` 标志。

### Q3: 性能差/卡顿？
**A**:
- 降低同步频率（100ms → 200ms）
- 减少顶点数（LOD）
- 使用 VBO/VAO 缓存

### Q4: 编译错误 "undefined reference to glXXX"？
**A**: 检查 CMakeLists.txt 是否链接 GLESv3 和 EGL。

---

## 参考资料

- [HarmonyOS XComponent 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/arkts-common-components-xcomponent-V5)
- [OpenGL ES 3.2 规范](https://registry.khronos.org/OpenGL/specs/es/3.2/es_spec_3.2.pdf)
- [GLM 文档](https://github.com/g-truc/glm/blob/master/manual.md)
- [Assimp 文档](https://assimp-docs.readthedocs.io/)

---

## 联系与支持

遇到问题可查看：
- HarmonyOS 官方论坛
- OpenGL ES 社区
- 项目 MEMORY.md 记录的已知问题
