# Task 1：修复章节与小节创建闭环

## 目标

真实浏览器和静态回退状态下，用户都能可靠创建章节与小节；创建结果必须立即出现在大纲页，动画失败不能回滚数据。

## 必须实现

1. 在大纲树区域左右两侧分别提供小型、可见、非矩形文字按钮的“新芽 +”图标入口：左侧创建章节，右侧为当前章节创建小节。
2. 保留左右空白区双击快捷方式，但它不再是唯一入口。
3. 入口有稳定语义标签、按下态和 pending 状态；pending 时阻止同类型重复提交。
4. 创建失败时显示中文用户反馈，不允许异常静默丢失。
5. 创建成功后由数据库 stream 驱动页面显示新标签；不等待 3D mutation 完成才更新业务数据。
6. 无章节时，右侧新增小节入口必须不可用且语义明确。
7. 不改变左侧滑动章节、右侧滑动小节的现有规则。
8. 不改数据库表结构，不顺手重构无关页面。

## TDD 要求

先修改/新增测试并亲眼确认失败，再写生产代码：

- 点击左侧新芽入口后创建章节，并验证 stream 推送后的可见标签。
- 连点 pending 中的入口只调用一次创建。
- repository 抛错时出现中文错误反馈，页面可继续操作。
- 无章节时右侧入口不可用；有当前章后点击右侧入口创建小节并出现右侧标签。
- 静态回退模式同样通过以上流程。

保留原双击测试，但增强为不仅查数据库，也查页面可见结果。

## 主要文件

- `lib/presentation/outline/outline_page.dart`
- `lib/presentation/outline/outline_controller.dart`
- `test/presentation/outline_page_test.dart`
- 必要时新增一个极小的共享图标组件，禁止引入新依赖。

## 验证

```powershell
flutter test test/presentation/outline_page_test.dart --reporter expanded
flutter test test/presentation/outline_controller_test.dart --reporter expanded
flutter analyze
```

## 提交规则

- 修改完成后运行相关测试。
- 运行代码地图更新；Windows 无 bash 时记录无法执行，不能手工编辑 `docs/CODE_MAP.md`。
- 提交信息：`修复大纲页章节与小节创建闭环`
- 在 `.superpowers/sdd/task-1-report.md` 写入红灯、绿灯、文件清单、测试输出和自审结论。
