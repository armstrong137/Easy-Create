# Task 2：补齐实时 3D 启动诊断与兼容路径

## 目标

任何目标浏览器都必须明确报告实时 3D 启动到哪一步；正常环境进入 Three.js，失败环境保留完整错误并进入同源降级，禁止 8 秒后静默切图。

## 必须实现

1. Flutter 侧建立可测试的启动阶段：`iframeLoading / webglCreating / modelLoading / firstFrame / ready / failed / timedOut`。
2. `TreeSceneController` 保存最新启动阶段、失败消息和诊断 payload，并通知监听者。
3. JS 在 WebGL context 创建前后、模型下载前后、KTX2 初始化后、首帧后分别发送启动事件。
4. `scene.error` payload 至少包含阶段、错误文本、WebGL2 可用性、UA、模型 URL；不得吞掉。
5. 8 秒超时只生成 `timedOut` 诊断，随后可以进入降级，但不得覆盖已经收到的明确错误。
6. 兼容 GLB 加载失败与 WebGL2 不可用；业务页面仍可创建章/节。
7. JS 源码修改后必须 `npm run build` 同步到 `assets/tree_scene/dist`。
8. 只在 debug/test 暴露诊断信息，不污染正式 UI。

## TDD

先写失败测试：

- controller 收到每个 boot 事件后阶段推进正确。
- 明确 `scene.error` 会保存 payload 并激活降级。
- timeout 不覆盖已有错误；ready 会取消 timeout 并清空旧失败。
- JS 单测验证 boot payload 规范和错误规范。
- Web fallback 测试验证源码存在阶段事件而不只检查 `scene.error` 字符串。

## 主要文件

- `lib/presentation/outline/tree_scene/tree_scene_controller.dart`
- `lib/presentation/outline/tree_scene/tree_scene_web.dart`
- `lib/presentation/outline/tree_scene/tree_scene_protocol.dart`
- `tools/tree_scene/src/main.js`
- `tools/tree_scene/src/MagicTreeScene.js`
- 对应 Dart/Node 测试和构建产物

## 验证

```powershell
flutter test test/presentation/tree_scene_controller_test.dart test/presentation/tree_scene_web_fallback_test.dart --reporter expanded
cd tools/tree_scene
npm test
npm run build
```

## 提交

提交信息：`补齐实时3D启动诊断与兼容路径`

完整红绿测试与文件清单写入 `.superpowers/sdd/task-2-report.md`。
