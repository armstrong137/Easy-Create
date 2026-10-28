# Easy Create

面向小说创作者的 Flutter 应用：用星球管理作品，用魔树整理章节，用灵感卷轴收集文字，在小节中编辑完整正文。

**当前为开发版本，整体视觉、动画和手机平台验收尚未完成，尚未发布正式安装包。**

## 下载与运行

点击仓库页面 **Code → Download ZIP** 下载源码。默认分支包含最新开发代码，main 保留较早历史。后续安装包将在 **Releases** 发布；下载源码不等于下载安装应用。

接手基线：Flutter **3.44.4**、Dart **3.12.2**、Node **24.15.0**、CodeGraph **1.2.0**。保留锁文件，不主动升级依赖。

```powershell
git clone https://github.com/armstrong137/Easy-Create.git
cd Easy-Create
flutter doctor -v
flutter pub get
npm ci --prefix tools/tree_scene
flutter run -d chrome
```

```powershell
flutter analyze --no-pub
flutter test --no-pub --timeout 2m
npm test --prefix tools/tree_scene
flutter build web --release --no-pub
dart scripts/serve_web.dart 8788
```

Web 预览地址为 http://localhost:8788。手机预览需要相同局域网、电脑局域网 IP 和防火墙允许该端口。Android 构建需要 JDK 和 Android SDK；iOS 构建需要 macOS 与 Xcode。

## 接手开发

依次阅读 [项目规约](PROJECT_RULES.md)、[架构与最新决策](AGENTS.md)、[开发进度及已知失败](DevelopmentPlan.md)、[代码地图](docs/CODE_MAP.md) 和 [迁移说明](电脑迁移包/新电脑Codex先读我.md)。正式表现采用高质量二维材质与空间动效，实时 3D 保留为实验能力。

代码修改后更新进度，提交前运行代码地图脚本，中文提交并推送。测试通过不能代替真实页面、动效与真机验收。

## 数据与资料

创作内容使用本地 SQLite，无账号或后端同步。Web 数据按浏览器和站点来源隔离，更换主机或端口不会自动带走小说。**Git 保存源码和受版本管理的资源，不等于备份个人创作数据库。** 私人迁移备份不公开上传。

第三方素材与字体授权见各资源目录的说明及许可证。公开访问源码不表示所有代码和素材均可无限制商用或再分发。
