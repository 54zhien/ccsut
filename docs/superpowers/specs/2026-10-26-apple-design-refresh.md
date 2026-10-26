# 长工院界面重设计

本轮按用户明确要求重做三个主页面、详情页、电表、网页登录刷新按钮，并修复记录加载位置、真实姓名和底栏动效；同时审查影响正常使用的风险。实现起点为上一版 `d50b437`（含尚未进入 main 的认证及控件修复），不从旧 main 覆盖这些修复。

## 设计决定

- 使用系统字体、SF Symbols、语义颜色与原生菜单/滚轮/Sheet。以留白、对齐、字号和分组表达层级。Liquid Glass 限于导航与重要操作；数据表、记录和金额使用清晰的实体内容表面。
- 保留三个标签：课表、教务、校园。首页入口仅保留标题，不重新加入用户删掉的说明文字。教务和校园以明确分组、统一行结构呈现入口；按最新要求移除教务首页的“接下来的考试”和对应的单独数据请求。
- 课表默认展示今日课程，在右上角账号旁点击“今日课程 / 所有课表”切换。今日课程使用独立的中性时间轴，按当前有效教学周和北京时间筛选；周次未知不误报没有课程。所有课表保留原有浮动周次胶囊、完整网格、冲突课程选择和横向大字滚动，撤掉新增的胶囊上方周次大标题。浏览其他周不改变今日课程。
- 详情页采用共同的内容边距、章节标题、信息行和中性关闭/筛选控件。成绩概览以绩点为主，考试的日期、时间、地点清楚区分，选课保留关闭通道和历史只读状态。
- 电费页按用户最后提供的实物照片重做：安静的系统背景中完整展示一只老式机械电表，包括挂耳、厚黑色胶木外壳、带斜面边框的玻璃罩、内嵌铭牌与黑底机械字轮、窄转盘观察缝，以及下方突出的接线盒和封印螺钉。正常竖屏完整表体和缴费键均在初屏内。楼栋/寝室进入铭牌数据窗，余额保留接口原字符串和精度，充值金额是可拨动字轮，缴费压键嵌入下方接线盒。字轮响应真实数值变化，减少动态效果关闭位移；观察盘不虚构实时用电。黑色胶木是用户实物参考指定的材质，面板和周围背景随系统外观适配。返回控件在表体外保留现有原生样式。付款确认、服务端限额、单次提交和待确认订单保护不变。
- 首次加载/空态使用真实可视区域布局。请假/离返校标题和分段选择固定在顶部；主状态位于屏幕中心附近，增添按钮保留右下方主题色玻璃及公开圆角几何。
- 底栏在导航协调器中渐隐并下移 20pt；返回反向播放，侧滑取消复原，减少动态效果关闭位移。20pt 是此次交互设计决定，不声称是 Apple 固定参数。
- 网页认证使用相同尺寸的圆形原生按钮；刷新不再通过 resizable 字形改变系统按钮度量。
- 姓名是可选显示信息，不能依赖选课开放，也不能改变可靠登录判定和跨账号隔离。

## 取舍

采用现有原生 SwiftUI/UIKit 架构和统一内容组件；不引入第三方 UI 框架。未采用所有卡片玻璃化（破坏内容层级）或全部替换导航容器（增加现有手势和安全区回归风险）。保留既有高斯顶栏与品牌资产。

### 电表实物构图

用户明确否定了 `a52392b` 与 `dd6e1f6` 的整页仪表面板方案。最终参考是单个独立实物，不能以测试通过代替视觉方向正确。

颜色以黑胶木 `#202120`、壳体反光 `#525450`、米白铭牌 `#E7DFC5`、金属 `#898B81`、字轮槽 `#11120F` 和深红压键 `#773E32` 为基准。使用系统字体，机械数字等宽；信息排布服从实物结构，控件与对应的数据窗一体。正常竖屏将完整电表置于页面中央，保留四周空间；横屏和最大辅助字号以可达性为先，必要时允许滚动。

```text
       原生返回      电费缴费

                  挂耳
           ┌── 黑胶木壳体 ──┐
           │ ┌─ 玻璃铭牌 ─┐ │
           │ │ 楼栋 / 寝室 │ │
           │ │ 余额机械字轮│ │
           │ │ 转盘观察缝  │ │
           │ │ 充值金额轮  │ │
           │ └────────────┘ │
           └───┬────────┬───┘
               │ 接线盒 │
               │ 缴费键 │
               └────────┘
```

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
- https://developer.apple.com/documentation/swiftui/picker
- https://developer.apple.com/documentation/swiftui/buttonbordershape
- https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)
- https://developer.apple.com/documentation/swiftui/controlsize/large
- https://developer.apple.com/documentation/swiftui/buttonstyle
- https://developer.apple.com/documentation/swiftui/draggesture
- https://developer.apple.com/documentation/swiftui/view/accessibilityadjustableaction(_:)
- https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l
- https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:)
- https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)
- https://developer.apple.com/documentation/swiftui/animation
- https://developer.apple.com/documentation/swiftui/viewthatfits
- https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable
- https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate/gesturerecognizershouldbegin(_:)
- https://developer.apple.com/documentation/uikit/uigesturerecognizer/cancelstouchesinview

长金额和最大辅助字号使用 `ViewThatFits(in: .horizontal)` 在机械字轮与保留完整原始金额的紧凑读数之间选择；不截断真实余额，也不将数据改成可编辑内容。

## 验证边界

本机 Windows 运行纯 Swift/Node 回归；iOS 通过 macOS CI 构建、原生模拟器交互和截图验证。覆盖浅/深色、大字体、横屏、减少动态效果、加载/空态、返回及取消、金额约束。模拟器和编译不等于真机视觉验收或真实学校接口验收。审查不发起真实申请、支付或选课提交。
