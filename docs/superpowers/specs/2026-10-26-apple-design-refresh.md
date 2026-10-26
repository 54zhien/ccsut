# 长工院界面重设计

本轮按用户明确要求重做三个主页面、详情页、电表、网页登录刷新按钮，并修复记录加载位置、真实姓名和底栏动效；同时审查影响正常使用的风险。实现起点为上一版 `d50b437`（含尚未进入 main 的认证及控件修复），不从旧 main 覆盖这些修复。

## 设计决定

- 使用系统字体、SF Symbols、语义颜色与原生菜单/滚轮/Sheet。以留白、对齐、字号和分组表达层级。Liquid Glass 限于导航与重要操作；数据表、记录和金额使用清晰的实体内容表面。
- 保留三个标签：课表、教务、校园。首页入口仅保留标题，不重新加入用户删掉的说明文字。教务和校园以明确分组、统一行结构呈现入口；下一场考试保留真实数据。
- 课表突出所选周、学期与当天日期，保留完整周网格、冲突课程选择和横向大字滚动；课程配色稳定、详情信息更易扫描。
- 详情页采用共同的内容边距、章节标题、信息行和中性关闭/筛选控件。成绩概览以绩点为主，考试的日期、时间、地点清楚区分，选课保留关闭通道和历史只读状态。
- 电费页按房间、余额、金额、确认组织。保留原生三个数字滚轮与 10 元最低值、服务端限额、付款确认及待确认订单保护；取消多层金属描边与深浅硬编码，使用语义色浅色/深色表面。
- 首次加载/空态使用真实可视区域布局。请假/离返校标题和分段选择固定在顶部；主状态位于屏幕中心附近，增添按钮保留右下方主题色玻璃及公开圆角几何。
- 底栏在导航协调器中渐隐并下移 20pt；返回反向播放，侧滑取消复原，减少动态效果关闭位移。20pt 是此次交互设计决定，不声称是 Apple 固定参数。
- 网页认证使用相同尺寸的圆形原生按钮；刷新不再通过 resizable 字形改变系统按钮度量。
- 姓名是可选显示信息，不能依赖选课开放，也不能改变可靠登录判定和跨账号隔离。

## 取舍

采用现有原生 SwiftUI/UIKit 架构和统一内容组件；不引入第三方 UI 框架。未采用所有卡片玻璃化（破坏内容层级）或全部替换导航容器（增加现有手势和安全区回归风险）。保留既有高斯顶栏与品牌资产。

## 官方依据（2026-10-26 核对）

- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/tab-bars
- https://developer.apple.com/design/human-interface-guidelines/motion
- https://developer.apple.com/design/human-interface-guidelines/buttons
- https://developer.apple.com/videos/play/wwdc2025/356/
- https://developer.apple.com/videos/play/wwdc2025/219/
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator

## 验证边界

本机 Windows 运行纯 Swift/Node 回归；iOS 通过 macOS CI 构建、原生模拟器交互和截图验证。覆盖浅/深色、大字体、横屏、减少动态效果、加载/空态、返回及取消、金额约束。模拟器和编译不等于真机视觉验收或真实学校接口验收。审查不发起真实申请、支付或选课提交。
