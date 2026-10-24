# Campus Native Forms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在原生界面填写并由用户确认提交请假与节假日离校/留校登记，提供新 IPA。

**Architecture:** Foundation 规则与不可变确认快照独立于 SwiftUI；复用 CampusClient 的身份及 Bearer 会话，分别实现可重试读取与不自动重试写入。原生表单用代数/修订号隔离异步候选、附件、定位与提交结果。

**Tech Stack:** Swift 6 Foundation tests, SwiftUI iOS 26, CoreLocation, PhotosUI/UniformTypeIdentifiers, UIKit masked text, GitHub macOS CI.

**Spec:** `docs/superpowers/specs/2026-10-24-campus-native-forms-design.md`（用户已批准，并要求直接实现、打包、不再确认流程）。

## Global Constraints

- 仅当前独立工作树；四个既有电表缴费文件不改动。
- 开发/自动化测试不提交真实申请、不上传真实附件；真实数据不打印、不入库。
- 电话及自由文本号码在输入、展示和辅助功能中脱敏，提交原值仅保存在内存。
- 类型、审批人、附件、定位依学校规则；不伪造身份或必填项。
- 读 401 只重试一次；写入不自动重试、不跟重定向，未知结果先查询记录。
- 延续本会话直接实施方式；全部完成后一次独立整体验证，不再询问执行模式。

## Review Focus

- 候选请求乱序或换号：旧审批人/个人数据不能重新发布。
- 留校切换：必须清空离校专属载荷；中文值和反向离校标记不得猜测。
- 附件/GPS 必填、无权限、配置缺失：明确阻止提交。
- 已确认的快照必须稳定；重复点击、超时不能重复发写请求。
- 原生号码遮蔽不能改变实际提交值或泄露到 AX/错误信息。

### Task 1: Domain rules and immutable submission snapshots

**Files:** Create `ios/CCSUT/CampusFormRules.swift`, `ios/Tests/CampusFormRulesTests.swift`.

**Interfaces:** `CampusFormKind`, `CampusFormDraft`, `CampusFormConfiguration`, `CampusFormChoice`, `CampusApprovers`, `CampusSubmission`, `CampusFormError`; draft validates and creates an immutable submission payload with account/userId/generation.

- [x] Write tests: half-day rounding, invalid dates, official time windows, contact validation, required attachments/location, approver eligibility, retained raw sensitive values, leaveSchool mapping, stay-at-school null fields, immutable snapshot.
- [x] Compile/run before implementation; expect missing types or failing rules.
- [x] Implement minimal Codable/Sendable data and pure rules; no network or persistence.
- [x] Run Foundation tests; expect all assertions pass. Commit scoped files.

### Task 2: Form metadata, uploads and single-attempt writes

**Files:** Create `ios/CCSUT/CampusFormsAPI.swift`, `ios/Tests/CampusFormsAPITests.swift`; modify `CampusAPI.swift` for shared internal identity/read primitives only.

**Interfaces:** `CampusFormServing.loadForm(_:) async throws -> CampusFormConfiguration`, `approvers(type:days:)`, `locate(latitude:longitude:)`, `submit(_:) async throws`, `reconcile(_:) async throws -> Bool`; implemented by the existing `CampusClient` actor. No default retry for mutations.

- [x] Write tests with synthetic transports: decoded configs/types/prefill, account-derived IDs, multipart approver query/upload, 401 read renewal, no bearer leakage, one write on timeout/redirect/401, safe error decoding, explicit success validation, generation switch.
- [x] Run to RED; implement strict minimal envelopes, allowlisted reads, stable JSON/multipart payloads, uploads only during confirmed submission.
- [x] Run new and existing API regressions to GREEN. Commit scoped files.

### Task 3: Native form lifecycle and UI

**Files:** Create `CampusFormModel.swift`, `CampusFormView.swift`, `CampusFormInputs.swift`, `CampusLocation.swift`, `CampusAreas.json`, `CampusFormModelTests.swift`; modify `CampusRecordViews.swift`, project file, Info.plist, preview/UI tests and session workflow.

**Interfaces:** MainActor `CampusFormModel` owns draft/config/approvers/confirmation/state; immutable submission passed only after confirmation. `CampusFormView(kind:account:onSubmitted:)` replaces the two official-form buttons. Returning registration remains existing behavior.

- [x] Write and run lifecycle tests to RED: stale metadata/candidates, changing drafts invalidates confirmation, one submit, unknown outcome queries without resubmission, cancellation and account changes clear data.
- [x] Implement model, masked UIKit editing with separate raw values and redacted AX, conditional SwiftUI inputs, scoped attachment import, real location, minimal resources.
- [x] Add synthetic preview forms and native UI checks for required-field errors, masked contacts/free text and confirmation. Never run write endpoints from fixtures.
- [x] Run Foundation suites and Node privacy suites, wire macOS compilation/UI verification; expect green. Commit scoped files.

### Task 4: Review and IPA

**Files:** Update `ios/README.md` and this plan checklist; review artifacts remain ignored.

- [x] Run one fresh independent review across this feature's commit range. Fix important findings once, with targeted RED→GREEN evidence.
- [ ] Push the isolated branch; run exact-SHA session/UI and Release IPA workflows. Inspect any failure before changing or rerunning.
- [ ] Download IPA, verify ZIP/arm64/bundle/minimum OS and no embedded tests; verify payment files match `2483a48`.
- [ ] Report proven checks separately from real-school submission/device acceptance; deliver unsigned IPA. No merge into main.
