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
- [x] Push the isolated branch; run exact-SHA session/UI and Release IPA workflows. Inspect any failure before changing or rerunning.
- [x] Download IPA, verify ZIP/arm64/bundle/minimum OS and no embedded tests; verify payment files match `2483a48`.
- [x] Report proven checks separately from real-school submission/device acceptance; deliver unsigned IPA. No merge into main.

## Verification record

Code and IPA source: `6d845286defdb1ca68b97a3ba4ad02d300107769`. This closeout only updates documentation.

- Local checks: 150 passed, including 78 native form rules/API/lifecycle assertions. The six Important review findings were reproduced and fixed in one pass; the drag-export regression is a source guard, not a physical-device drag test.
- [macOS session regressions](https://github.com/54zhien/ccsut/actions/runs/40069769456): success at the exact code commit.
- [Native campus UI](https://github.com/54zhien/ccsut/actions/runs/40069769465): six tests, zero failures; light/dark and confirmation screenshots inspected.
- [Release IPA](https://github.com/54zhien/ccsut/actions/runs/40069775082): success; ZIP/arm64/bundle/iOS 26.0/no embedded tests checks passed. SHA256 `74acab86be2d35979089087a8c77e9dc7d41a0222389274db8c12035eb965be4`.
- Four payment files remain identical to `2483a48`. The isolated worktree and branch are preserved, without merging main.
- Development and automation did not submit real school applications or upload real attachments. Real submission, device location and detailed VoiceOver/drag behavior require user/device acceptance.
- Deferred minor: the keyboard does not automatically scroll the current free-text input into view; manual scrolling is available.

## Device regression follow-up — 2026-10-24

The user reported that the delivered form rejected school configuration and that both record lists disappeared after dismissing an application sheet. The earlier fixture-only validation did not establish device acceptance for these cases.

- Authenticated, read-only inspection identified whitespace around the optional attachment flag's hidden value. The original native parser failed on the current metadata; the revised parser passed. Identity and personal records were replaced inside the browser before this probe, and no response/session capture was saved or committed. Only off-by-default hidden flags accept this padding; default-on and reviewer-scope values remain strict.
- On dismissal the view previously replaced the record model while the child read task still had the same selection key. The fix reuses the same account/generation model and refreshes it with existing rows visible. Actual model replacement also changes the child task key so reads restart.
- Preserved RED evidence at `cd150e3`: [config regression](https://github.com/54zhien/ccsut/actions/runs/40071322796) and [native dismissal regression](https://github.com/54zhien/ccsut/actions/runs/40071322821). The latter failed specifically because the prior record was missing after closing the form; its other six tests passed.
- Fixed source commit: `f0e1ed0381b7dd9602ce4177a44ec6e731c19b04`. Local checks: 152 passed. [macOS regression](https://github.com/54zhien/ccsut/actions/runs/40072362087), [seven native UI tests](https://github.com/54zhien/ccsut/actions/runs/40072362149), and [Release IPA](https://github.com/54zhien/ccsut/actions/runs/40072362878) all succeeded at that exact commit. Both pages were opened/dismissed twice; the returned record screenshots were inspected.
- Package checks passed (ZIP, arm64, bundle, iOS 26.0, no embedded tests/probe fixtures). SHA256: `ab52957978b24769cb59dbacec21ed70f34182c081cf5691c386da67578d06a7`. Four payment files remain unchanged against `2483a48`; no merge to main.
- Scoped independent review found no Critical/Important defect. Deferred Minor: the fixture's five-second record-visibility wait cannot distinguish continuous retention from a brief successful refetch. Refresh-failure retention is covered at the model level; detailed native slow/failing-refresh and account-swap frame behavior remain device/coverage limits. Synchronous account-swap rendering predates this fix and was not changed or accepted as zero-frame private rendering.
- No real application or attachment upload was sent. Physical-device acceptance of this replacement IPA and real submission remain unverified.
