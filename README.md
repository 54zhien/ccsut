<p align="center">
  <img src="ios/CCSUT/Assets.xcassets/SchoolEmblemCore.imageset/SchoolEmblemCore.svg" width="88" alt="长工院标识">
</p>

<h1 align="center">长工院</h1>

<p align="center">把课表、教务和校园事务放进一个原生 iOS 应用。</p>

<p align="center">
  <a href="https://github.com/54zhien/ccsut/actions/workflows/session-tests.yml"><img src="https://github.com/54zhien/ccsut/actions/workflows/session-tests.yml/badge.svg?branch=main" alt="会话与业务回归测试"></a>
  <a href="https://github.com/54zhien/ccsut/actions/workflows/ios.yml"><img src="https://github.com/54zhien/ccsut/actions/workflows/ios.yml/badge.svg?branch=main" alt="IPA 构建"></a>
  <img src="https://img.shields.io/badge/iOS-26%2B-black" alt="iOS 26 及以上">
</p>

这是面向长沙工业学院学生的非官方客户端。使用 SwiftUI 构建，连接学校现有的教务、智慧校园与电费服务；需要有效的学校账号及相应业务权限。

## 日常能做什么

| 页面 | 功能 |
| --- | --- |
| 课表 | 按周查看课程、时间和地点 |
| 教务 | 查询成绩与绩点、考试安排、选课列表和已选课程；确认后选课或退课 |
| 校园 | 查看请假与节假日离返校记录，填写请假和离校／留校申请，进入官方返校登记页 |
| 电表缴费 | 选择校区、楼栋与房间，查看电表信息，核对金额后缴费并查询订单结果 |
| 登录 | 复用已有会话；需要验证码等操作时进入认证流程 |

<p align="center">
  <img src="docs/images/academic-light.png" width="280" alt="教务页：课程、考试与成绩入口">
  <img src="docs/images/campus-dark.png" width="280" alt="深色校园页：请假、离返校与电表缴费入口">
</p>

<p align="center"><sub>截图使用模拟器合成数据，不含真实学生记录。</sub></p>

## 安装

需要 **iOS 26 或更新版本**。

1. 打开 [Build IPA](https://github.com/54zhien/ccsut/actions/workflows/ios.yml)，选择 `main` 分支上成功完成的构建。
2. 在该次运行的 **Artifacts** 中下载 `CCSUT-ipa`，解压得到 `CCSUT-unsigned.ipa`。下载可能需要登录 GitHub，产物也可能因保留期限到期而不可用。
3. 使用你自己的签名方式签名并安装，或按下方说明通过 Xcode 构建。

> [!NOTE]
> Actions 提供的是**未签名 IPA**，不能直接点开安装。构建成功也不等于所有学校业务已在真机验收。

## 从源码构建

需要 macOS、Xcode 26 或更新版本，以及对应 iOS SDK。打开已有工程即可，不需要生成工程或安装根目录的 Node 依赖。

```bash
git clone https://github.com/54zhien/ccsut.git
cd ccsut
open ios/CCSUT.xcodeproj
```

在 Xcode 中选择 `CCSUT` scheme 和目标设备。真机运行前，在 **Signing & Capabilities** 中设置自己的 Team，必要时调整 Bundle Identifier。模拟器可使用合成预览数据；真实业务仍需要学校账号。

开发说明、模块边界和测试命令见 [iOS 开发指南](ios/README.md)。

## 数据与使用边界

- 登录状态由学校服务决定。应用尝试恢复有效会话，但不承诺永久免登录。
- 请假、选退课与付款会改变真实业务数据，请核对确认内容。网络超时可能意味着服务端已经处理，结果未知时应先查记录或订单。
- Cookie 和认证令牌属于凭证。不要把抓包、登录状态、个人记录或含敏感信息的日志放进 issue 或提交到仓库。
- 一卡通余额与消费流水尚未作为独立功能接入。学校接口或认证流程变化可能影响可用性。

## 仓库结构

```text
ios/                    原生 iOS 工程、业务代码和离线测试
.github/workflows/      macOS 回归测试、模拟器验证与 IPA 构建
docs/                   设计说明、审查记录与截图
design/                 品牌及界面设计素材
tools/                  早期协议调查工具
shell/                  早期 Flutter WebView 原型
```

`shell/`、`tools/` 和根目录 `_*.mjs` 属于历史实验，不是 iOS 应用的构建依赖。其中有脚本会调用真实选退课接口，不应作为自动化测试直接运行。当前维护与验证以 `ios/` 为中心。
