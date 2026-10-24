# 校园服务内部页面 UI 重构

用户要求重构请假、节假日离返校、电表缴费内部 UI，允许参考外部 idea，但不能偏离现有 App 风格。延续本会话直接实施、不再确认流程的要求；以下视觉细节由实现者选择，并非用户逐项指定。

## 方向与取舍

选择「现有 Nagi 页面外壳 + 更清晰的原生分组内容」。保留 SF 系统字体、现有蓝色、语义背景、28pt 圆角、玻璃按钮、明暗模式和底部导航。内容卡片使用实色，玻璃集中于导航与操作。

考虑过：全量改成系统 List/Form（原生但会影响已有滚动与页面外壳），或大面积彩色钱包卡片（辨识度强但与现有 App 差异较大）；均不采用。参考 Apple Materials/Adopting Liquid Glass 的功能层与内容层分离，以及钱包/日历的主次信息组织，不复制品牌元素。

## 页面

- 请假：保留申请入口；记录卡片以类型、状态、起止时间为主，时长、事由、申请时间降为辅助层，减少逐字段纵向堆叠。未知状态不猜测业务含义。
- 离返校：保留原有分段切换；突出假期、状态、时间、去向，交通与备注次级展示。保留全部已有记录字段及分页/刷新行为。
- 原生表单/核对页：统一分组标题、控件行、输入区、信息摘要和主操作；明确选择器标签；输入框聚焦后滚动到键盘上方。保留 SecureField、号码遮蔽、全部条件字段和确认流程。
- 电表缴费：突出余额与对应房间，房间选择与缴费金额清晰分组；快捷金额使用原有蓝色选择态；确认页与结果页统一摘要风格。付款入口、免密扣款说明、未知结果查询保持语义和行为。

## 边界

- 复用当前独立工作树；不合并 main，不改其他页面外壳。
- 本次允许修改 EcardPaymentView 展示；EcardAPI、EcardTokenBridge、EcardPaymentModel 保持字节不变。
- CampusAPI、CampusFormsAPI、CampusFormRules、CampusFormModel、CampusRecordsModel 不改业务逻辑。
- 不加载/打印/提交个人抓包；预览和自动化全部使用合成数据，不调用真实提交、支付或附件上传。
- Dynamic Type、44pt 触达、横屏、小屏、iPad、深色与减少动态效果均纳入检查。沿用系统语义颜色与原有导航动画。

## 验证

Foundation 覆盖日期格式与隐私回退；原生 UI 覆盖既有表单与返回记录回归、键盘可见性、电费金额输入/快捷选择、确认与结果展示。macOS 编译、截图检查与未签名 IPA 包检查分开记录；真实支付和真机验收不由合成测试代替。

参考：https://developer.apple.com/design/human-interface-guidelines/materials ，https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
