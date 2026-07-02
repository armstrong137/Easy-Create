# DevelopmentPlan.md — 开发计划与进度

> 维护规则（用户规定）：每完成一步立即更新本文件，方便其他智能体接力开发。
> 进度标记：☐ 未开始　🔄 进行中　✅ 已完成

**当前进度：阶段二 · 第 3 步（语音识别）**

---

## 总览：共 7 个阶段

| 阶段 | 名称 | 状态 |
|------|------|------|
| 一 | 项目骨架与数据层 | ✅ |
| 二 | 全局灵感速记 | 🔄 |
| 三 | 首页创作宇宙 | ☐ |
| 四 | 大纲页铅笔树 | ☐ |
| 五 | 灵感魔毯 | ☐ |
| 六 | 小节页卡堆与编辑器 | ☐ |
| 七 | 打磨联调与双平台适配 | ☐ |

---

## 阶段一：项目骨架与数据层（4 步）

- ✅ 1. 初始化 Flutter 工程，建立 core/data/domain/presentation 分层目录与依赖（riverpod、drift、speech_to_text 等）
  - 2026-07-02 完成：Flutter 3.44.4 stable（C:\src\flutter），novel_app 工程（android/ios/web 三平台），依赖 flutter_riverpod/drift/drift_flutter/speech_to_text + dev:drift_dev/build_runner，pub get 通过
- ✅ 2. 用 drift 定义 4 张表（novels/chapters/sections/inspirations）与数据库类
  - 2026-07-02 完成：lib/data/database/{tables,app_database}.dart，外键开启；级联规则：删小说→删章→删节，删节时灵感 section_id 置 NULL 放回魔毯（不陪葬）；build_runner 生成通过、analyze 无告警
- ✅ 3. 实现仓库层：小说/章/节的增删改查 + 灵感生命周期流转（入池、拖入小节、放回、真删）
  - 2026-07-02 完成：lib/data/repositories/{novel,inspiration}_repository.dart。两个待用户终审的假设：①魔毯排序取"新的在前"；②删除小节/小说时灵感放回魔毯（不陪葬）
- ✅ 4. 编写数据层单元测试，验证灵感生命周期规则（含"放回后按创建时间排序"）
  - 2026-07-02 完成：test/data/repositories_test.dart，11 用例全绿（生命周期四规则 + 级联删除 + 编辑不改排序）

## 阶段二：全局灵感速记（3 步）

- ✅ 1. 全局双按钮组件：左下+右下，语音/文字图标，位置可互换（偏好持久化）
  - 2026-07-02 完成：presentation/shared/quick_capture/，MaterialApp.builder 全局注入。交互假设（待终审）：长按任一按钮=左右互换。教训存档：速记层在 Overlay 之上不能用 Tooltip；HapticFeedback 需放在状态变更之后
- ✅ 2. 文字输入弹层：输入 → 存入全局灵感池
  - 2026-07-02 完成：text_capture_sheet.dart，空内容不入库；widget 测试 4 例全绿（含互换持久化、入池 section_id=NULL 断言）
- ✅ 3. 语音识别接入 speech_to_text：识别文本 → 确认 → 入池
  - 2026-07-02 完成：speech_service.dart 薄封装（测试可注入替身）+ voice_capture_sheet.dart 实时识别弹层；双端权限已声明（RECORD_AUDIO+RecognitionService 可见性 / NSMicrophone+NSSpeechRecognition）。教训：Riverpod 3 禁止 dispose 中用 ref，服务存 State 字段。待真机验证系统引擎实际识别

## 阶段三：首页创作宇宙（5 步）

- ☐ 1. 程序化星空背景：星点绘制，亮度参数化（随当前小说灵感数变化，有上下限）
- ☐ 2. FragmentShader 星球：球面贴图 + 昼夜光照 + 自转 uniform；接入 NASA 地球纹理
- ☐ 3. 转速联动：零内容静止，灵感越多转速稍快（肉眼可见、封顶）
- ☐ 4. 环绕灵感文字：2.5D 椭圆轨道（缩放+透明度+星球遮挡），加粗黑楷体+细白描边，只显示最近几条、超长省略
- ☐ 5. 多星球：左右滑动 PageView 切换小说；顶部纯白 "Create Something"（Arabic Typesetting）点击创建新星球（火星/木星/水星等纹理）

## 阶段四：大纲页铅笔树（4 步）

- ☐ 1. 铅笔树 CustomPainter：细长黑白手绘风树形，随章节数据生成枝丫布局
- ☐ 2. 玻璃质感＋号（BackdropFilter + 动态高光）：左＋生成章、右＋生成节，含枝丫生长动画
- ☐ 3. 枝丫文字交互：长按弹出编辑/删除；双击进入小节页
- ☐ 4. 空状态：无干无叶的秃树 + 纯白背景

## 阶段五：灵感魔毯（3 步）

- ☐ 1. 魔毯组件：阿拉丁配色，展开/缩球动效（Rive 或程序化补间），驻留大纲页右上角最顶层
- ☐ 2. 展开列表：高度随灵感数伸缩（有上下限），最多显示几条、内部下滑加载更多，按创建时间排序
- ☐ 3. 拖拽：灵感从魔毯拖到树上章/节 → 归属该节 → 魔毯自动缩球

## 阶段六：小节页卡堆与编辑器（4 步）

- ☐ 1. 小节页框架：顶部可编辑标题 + 主区最新一张灵感卡（纯白卡+3D 黑细框、自适应大小、超长省略）
- ☐ 2. 卡片包：Dock 式展开全部卡片，下滑浏览
- ☐ 3. 长按拖动重排序（card_order 持久化）
- ☐ 4. 全文编辑器：点开单卡编辑，数万字长文本流畅（懒加载渲染）；从小节删卡 → 灵感放回魔毯

## 阶段七：打磨联调与双平台适配（4 步）

- ☐ 1. 动效细节打磨：环绕灵动度、树生长手感、魔毯质感
- ☐ 2. 性能：长文本编辑、星球 Shader 帧率、低端机适配
- ☐ 3. iOS / Android 双平台差异验证（语音权限、字体、手势）
- ☐ 4. 遗留终审项落定：环绕黑楷体可读性方案、各"最多几条"具体数值

---

## 接力开发须知

1. 开工前依次阅读：`PROJECT_RULES.md` → `claude.md` → 本文件 → `docs/CODE_MAP.md`
2. 需求有疑问以 `docs/superpowers/specs/2026-07-02-novel-app-design.md` 为唯一权威
3. 每完成一步：更新本文件进度标记 → 运行 `bash scripts/update_code_map.sh` → git commit（中文提交信息）
