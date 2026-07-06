# DevelopmentPlan.md — 开发计划与进度

> 维护规则（用户规定）：每完成一步立即更新本文件，方便其他智能体接力开发。
> 进度标记：☐ 未开始　🔄 进行中　✅ 已完成

**当前进度：阶段七进行中——主界面/大纲页/小节页均已用户过审，待过审：速记弹层；后续动效/性能/双平台打磨**

---

## 总览：共 7 个阶段

| 阶段 | 名称 | 状态 |
|------|------|------|
| 一 | 项目骨架与数据层 | ✅ |
| 二 | 全局灵感速记 | ✅ |
| 三 | 首页创作宇宙 | ✅ |
| 四 | 大纲页铅笔树 | ✅ |
| 五 | 灵感魔毯 | ✅ |
| 六 | 小节页卡堆与编辑器 | ✅ |
| 七 | 打磨联调与双平台适配 | 🔄 |

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
  - 模拟器冒烟（Pixel 7 / Android 36）通过：构建安装启动正常（Impeller/OpenGLES），文字速记端到端落库验证（SQLite 查得 section_id=NULL）。冒烟发现并修复：弹层打开时速记按钮遮挡弹层 → 弹层期间隐藏按钮（captureSheetOpenProvider）

## 阶段三：首页创作宇宙（5 步）

- ✅ 1. 程序化星空背景：星点绘制，亮度参数化（随当前小说灵感数变化，有上下限）
  - 2026-07-02 完成：core/creative_energy.dart（亮度/转速指数饱和曲线，封顶保底，数值待阶段七调优）+ home/starfield.dart（固定种子 180 星点）+ home_page.dart（亮度暂由魔毯灵感数驱动，三·5 换当前小说）。重要教训：widget 测试严禁让 StreamProvider 监听真 drift 流（pending timer 挂死进程），必须 overrideWith 固定流；跑测试一律带超时、超时杀 flutter_tester
- ✅ 2. FragmentShader 星球：球面贴图 + 昼夜光照 + 自转 uniform；接入 NASA 地球纹理
  - 2026-07-02 完成：shaders/planet.frag（正交投影球面反解经纬度采样+Lambert 昼夜光照+边缘抗锯齿）+ home/planet_view.dart（Ticker 驱动自转，静止时停帧省电）；纹理 NASA Blue Marble 缩至 2048×1024 入 assets。模拟器实拍验收通过（真实地球+星空效果符合定稿）
- ✅ 3. 转速联动：零内容静止，灵感越多转速稍快（肉眼可见、封顶）
  - 2026-07-02 完成：planetSpin 曲线（core/creative_energy.dart，零静止/单调/封顶有单测）已接入 PlanetView；模拟器 10 秒间隔截图对比确认可见自转。注意：转速数据源暂为魔毯灵感数，三·5 改"当前小说灵感数+章节数"
- ✅ 4. 环绕灵感文字：2.5D 椭圆轨道（缩放+透明度+星球遮挡），加粗黑楷体+细白描边，只显示最近几条、超长省略
  - 2026-07-02 完成：home/orbiting_inspirations.dart（x-z 圆轨道公转 36s/圈，z 分前后层夹星球实现遮挡，近大远小+近实远虚）；楷体=霞鹜文楷 Medium（OFL，无 Bold 字重，粗度并入可读性待终审项；25MB 字体待阶段七子集化瘦身）。环绕条数暂定 5（待终审）。教训：无限 repeat 动画的组件测试只能定点 pump，严禁 pumpAndSettle
- ✅ 5. 多星球：左右滑动 PageView 切换小说；顶部纯白 "Create Something"（Arabic Typesetting）点击创建新星球（火星/木星/水星等纹理）
  - 2026-07-02 完成：HomePage 重构为 PageView（一页一星球），点标题弹创建对话框、纹理按数量轮换（earth/mars/jupiter/mercury，火星等三张来自 solarsystemscope CC-BY 4.0 NASA 数据）；转速/亮度改按当前小说创作量（watchCreativeCount：章+节+挂靠灵感，魔毯灵感不计入）；空宇宙邀请文案。模拟器实拍验收：创建两颗星球（地球/火星）、滑动切换、环绕灵感全局共享均通过。待终审：Arabic Typesetting 为微软授权字体无法打包，现以衬线斜体近似（有授权字体放 assets/fonts 即可替换）；点星球进大纲页留 TODO 待阶段四

## 阶段四：大纲页铅笔树（4 步）

- ✅ 1. 铅笔树 CustomPainter：细长黑白手绘风树形，随章节数据生成枝丫布局；**树随章节规模成长变老**（小树细嫩→粗干密枝、排线阴影、年轮结疤，2026-07-02 用户补充）
  - 2026-07-02 完成：outline/tree_model.dart（treeAge 指数饱和 + layoutTree 纯函数：章枝左右交替自下而上、节枝长短/角度交替）+ pencil_tree_painter.dart（抖动铅笔线、树龄排线阴影、结疤、**标签碰撞规避**——先占位后避让，5候选位）+ outline_page.dart；首页点星球进入。数据层 watchOutline join 查询 + domain 首个实体 OutlineChapter。模拟器 5 章 12 节实拍验收：标签零重叠
  - 环境修复：模拟器 System UI ANR 根因=AVD 默认关 GPU（hw.gpu.enabled=no）→ 开 host GPU + 4G 内存 + hide_error_dialogs=1 持久设置 + 窗口居中（详见项目记忆 emulator-anr-fix）
- ✅ 2. 玻璃质感＋号（BackdropFilter + 动态高光）：左＋生成章、右＋生成节，含枝丫生长动画
  - 2026-07-02 完成：glass_plus_button.dart（模糊+厚度渐变边+4s 周期斜扫反光）；左＋自动命名（引子→第一章→…，core/chinese_numbers.dart）、右＋挂**最新一章**（假设待终审）+ 空章提示；700ms easeOut 生长动画（新枝从根伸出、六成后标题浮现）。模拟器抓帧验收：生长中间帧/完成帧对比确认。＋号位于两侧偏上（-0.55）避开中部枝端标题
- ✅ 3. 枝丫文字交互：长按弹出编辑/删除；双击进入小节页
  - 2026-07-02 完成：label_layout.dart 把标签几何（含碰撞规避）抽为纯函数，布局/绘制/交互热区共享；透明热区外扩 8px。长按→底部菜单（重命名/剪掉，删除带确认+级联说明）；双击章→重命名对话框、双击节→小节页雏形（section_page.dart，顶部可编辑标题，卡堆阶段六）。测试：标签两两不重叠穷举断言 + 交互链路 6 例。教训：测试页面转场需分帧 pump（一次 pump 只推一帧）
- ✅ 4. 空状态：无干无叶的秃树 + 纯白背景
  - 已随四·1 实现：空大纲时 treeAge=0、无枝无干，painter 仅纯白画布；widget 测试"空大纲渲染秃树页"覆盖

## 阶段五：灵感魔毯（3 步）

- ✅ 1. 魔毯组件：阿拉丁配色，展开/缩球动效（Rive 或程序化补间），驻留大纲页右上角最顶层
  - 2026-07-02 完成：outline/magic_carpet.dart（深红绒面+金织边+紫夜配色，320ms easeOutBack 程序化补间；选程序化而非 Rive，轻量无外部资产）+ core/carpet_constants.dart。教训：容器展开动画中间帧内容会挤压溢出 → clipBehavior + OverflowBox 按最终尺寸布局
- ✅ 2. 展开列表：高度随灵感数伸缩（有上下限），最多显示几条、内部下滑加载更多，按创建时间排序
  - 2026-07-02 完成：carpetHeight 封顶保底（140~340）、ListView 内部滚动、空毯邀请文案；魔毯上任何页面复用灵感池流（新的在前）。教训重现并已修：新组件让页面 watch 新的 drift 流时，该页所有测试必须补 override
- ✅ 3. 拖拽：灵感从魔毯拖到树上章/节 → 归属该节 → 魔毯自动缩球
  - 2026-07-02 完成：CarpetItem 包 LongPressDraggable（长按拖起防滚动冲突，金光浮影卡）；树上标签热区兼任 DragTarget（悬停枝端泛金光）；落节直接挂靠、落章挂到该章最新一节（假设待终审）、无节章提示先长节枝；落点后 GlobalKey 调魔毯 collapse()。教训：测试中长按拖拽需展开动画+水波完全稳定后再拖（隔离实验五步定位）

## 阶段六：小节页卡堆与编辑器（4 步）

- ✅ 1. 小节页框架：顶部可编辑标题 + 主区最新一张灵感卡（纯白卡+3D 黑细框、自适应大小、超长省略）
  - 2026-07-02 完成：inspiration_card.dart（黑细描边+右下纯黑实体投影=3D 感）；主区最新一张=card_order 最大（假设待终审）
- ✅ 2. 卡片包：Dock 式展开全部卡片，下滑浏览
  - 2026-07-02 完成：card_deck_sheet.dart 底部滑出 72% 屏高面板，缩略卡列表滚动浏览、点卡进编辑器；入口=底部"卡片包 N"按钮
- ✅ 3. 长按拖动重排序（card_order 持久化）
  - 2026-07-02 完成：ReorderableListView（onReorderItem 新 API）+ 仓库 reorderCards 事务重写 0..n-1；数据层单测覆盖
- ✅ 4. 全文编辑器：点开单卡编辑，数万字长文本流畅（懒加载渲染）；从小节删卡 → 灵感放回魔毯
  - 2026-07-02 完成：card_editor_page.dart（maxLines:null 无上限，返回自动保存 PopScope；3 万字渲染测试通过，真机流畅性阶段七压测）；"放回魔毯"带确认（生命周期规则三）。阶段收官全量回归 67 例全绿，顺带还清技术债：共享页面新增流后全部既有测试补 override（影响面教训入项目记忆）

## 阶段七：打磨联调与双平台适配（5 步）

- 🔄 1. **UI 视觉终审与打磨**（2026-07-02 用户补充）：所有页面的图片素材与显示效果与用户逐页过审——用户提修改 → 迭代 → 直到实现用户心中的样子为止
  - 主界面二轮修正（2026-07-03 用户反馈）：①零创作星球由"静止"改为**待机微转**（kPlanetSpinIdle=0.008 圈/秒，约 2 分钟一圈；用户观感"不转像坏了"，设计文档已同步）；②纹理升级**五图扇区合成**（每图承担 72° 经度、只采中心优质区、扇区间 smoothstep 渐变——过渡区伪影彻底消除，工具改为命名参数 --out/--width/--circle-ratio/--mirror-south）
  - ✅ 主界面（2026-07-03 用户过审通过）：①星球全部换用户 2D 素材 3D 化——tool/planet_texture_gen.dart 反投影管线（双图拼球：1号正面+2号背面、假透明棋盘底颜色检测、±75° 优质区采样、边缘渐进模糊抗拉丝、混合带 ±26° 渐变；土星单图+南半球镜像）；②五种星球 earth/mars/jupiter/venus/saturn 轮换（水星淘汰）；③土星=3D 自转球+程序化静态光环贴层（SaturnView 三明治：后环-球-前环，用户定稿方案）；④星空=用户 4 张银河图按创作能量四档递增（starfield_1~4，AnimatedSwitcher 800ms 淡切，用户定稿：单本小说灵感/章节越多背景越亮）
  - ✅ 主界面收官（2026-07-03 用户确认）：地球拼接经三轮修正（真实经度+色调统一+平衡混合带）终审通过；五星球+四档星空+待机微转+书名单击重命名全部就绪
  - ✅ 大纲页（魔树/玻璃＋/魔毯，2026-07-05 用户过审通过）
    - 2026-07-04 打磨：魔毯收起时保留展开面板播放 9→1 反向卷回帧，动画结束后再切回小球；补 widget 测试覆盖手动收起与拖拽落点后自动缩球
    - 2026-07-04 五处交互修正：魔毯拖到垃圾桶永久删除、长标签换行、单击小节即进、主区只显一张卡、卡包第一张=当前展示（拖入即置顶）
    - 2026-07-05 四处修正：①小节页整页作落点，魔毯灵感可拖进本节（DragTarget+"松手放入本节"提示层）②章/节标签加粗（章 w700/节 w600）③小节标签下灵感小卡加大内边距防裁④大纲/小节页标题右侧留白避让全局魔毯球
    - 2026-07-05 修窗口模式小节错位：小节内容区起点钳在"章根之下+可见树干之内"（原用带几何顶，首章带顶高过树干致小节飘到树顶魔毯球旁）
    - 2026-07-05 修重复章（两个第一章）：建章/建节改原子事务 + 按新 sort_order 派生默认名，drift 串行化并发事务防连点竞态；以序号为命名索引删章后不复用编号
    - 真机实拍闭环全部通过；全量回归 77 例绿
  - ✅ 小节页（卡片/卡包/编辑器，2026-07-04 用户定稿 iOS 照片级改版）：苹果钱包叠层卡堆、羊皮纸暖调、iOS 极简头部、主区单卡、卡包重排、全文编辑器、拖入落点
  - 待过审：速记弹层
- ☐ 2. 动效细节打磨：环绕灵动度、树生长手感、魔毯质感
- ☐ 3. 性能：长文本编辑、星球 Shader 帧率、低端机适配
- ☐ 4. iOS / Android 双平台差异验证（语音权限、字体、手势）
- ☐ 5. 遗留终审项落定：环绕黑楷体可读性方案、各"最多几条"具体数值、待终审假设清单（魔毯排序方向/删节灵感去向/长按互换/首章命名/右＋挂最新章/拖章挂最新节/Arabic Typesetting 替代字体/楷体字重与瘦身）

---

## 接力开发须知

1. 开工前依次阅读：`PROJECT_RULES.md` → `claude.md` → 本文件 → `docs/CODE_MAP.md`
2. 需求有疑问以 `docs/superpowers/specs/2026-07-02-novel-app-design.md` 为唯一权威
3. 每完成一步：更新本文件进度标记 → 运行 `bash scripts/update_code_map.sh` → git commit（中文提交信息）
