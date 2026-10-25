# 2026-10-25 integration review and validation

The user authorized fixing all five premerge findings, testing and independently reviewing the combined changes, then merging into `main` if clean. The integration starts from `main` at `dd82bce` and retains the original feature commit history; no source branch or failed CI run is deleted or rewritten.

## Included feature heads

| PR | Reviewed source head |
| --- | --- |
| #2 | `6ed9a18` |
| #3 | `86121ef` |
| #4 | `1e27315` |
| #7 | `0ba6895` |
| #8 | `36dc5d8` |
| #9 | `9c37b5b` |
| #10 | `dfe4f00` |
| #11 | `b1129cf` |
| #12 | `bf29adc` |
| #13 | `d70f255` |
| #14 | `1788497` |

The exploratory refresh-diagnosis branch is superseded by the scoped implementation in #14. The approved material blur implementation from #5 is retained, including its legacy fallback. Distribution output remains untracked.

## Findings and fixes

- Campus authentication stages cookie rotations and scoped deletions within each identity attempt. Only a matching account and valid bearer token may publish the staged changes after cancellation/generation checks. Rejected, incomplete, canceled and superseded attempts discard their staging; concurrent subsystems have separate staging objects.
- Trusted HTTP default/80 destinations upgrade to HTTPS before dispatch and cookie selection. HTTPS permits only default/443; credentials, fragments, foreign hosts and other ports remain rejected.
- Selected-course invalidation belongs inside the owning load-gate action. A refresh joining that action waits without invalidating its in-flight enrolled-course response.
- The selected filter shows the independent catalog failure and retry action while preserving readable, read-only selected/history results. It uses the existing status notice above the filter-specific result branch.
- E-card read recovery classifies HTTP 401 and exact trusted login redirects as authentication failures. Other redirects and 403 retain their HTTP error. Payment mutations remain single-send, with uncertain results retaining and reconciling the original order.

## Failure provenance

- Campus local executable: 40 PASS / 12 FAIL against the original implementation, then 56 campus API assertions pass. Related campus suites total 198 passing Swift assertions.
- E-card response classification: nine local behavioral failures, then all 20 payment API assertions pass; 87 payment-model assertions also pass.
- Actual production selected load/gate extraction: the original implementation compiles and loses the completed snapshot after a joined refresh. The fixed source passes four ownership/completion assertions. Existing enrolled-course and elective-state suites pass 38 and 27 assertions respectively.
- [40185871324](https://github.com/54zhien/ccsut/actions/runs/40185871324) preserves the first integrated native source failure. Three old expectations differed from the newer contracts: post-dispatch business rejection now conservatively retains/reconciles the original order, and authentication timeout includes its actual stage. The updated tests preserve exactly-one-debit and original-order-query assertions. Other executed source suites passed; the app build step was skipped, so this run is not build evidence.
- [40185871758](https://github.com/54zhien/ccsut/actions/runs/40185871758) preserves a UI-test compilation failure caused by launch-helper code accidentally inserted into test methods during integration. The helper repair preserves test-specific arguments and assertions. This is not behavioral RED evidence.
- [40186240704](https://github.com/54zhien/ccsut/actions/runs/40186240704) is the genuine native catalog-error RED after the test compiler repair: nine tests executed, three expected catalog notice/retry failures, six existing tests passing. The passing checks include multi-page/empty refresh, complete/history results, read failure and large-text/dark appearance. The failure run is preserved and is not rerun or canceled.

## Verified integration checkpoint

At `a8b98c3`, [40186240130](https://github.com/54zhien/ccsut/actions/runs/40186240130) passes all source regressions and the Debug simulator application build: 704 Swift PASS lines, zero FAIL lines, plus the repository and embedded JavaScript tests. This includes real WebKit/CookieJar, all 22 original e-card callback/payment checks, the scoped campus transaction, selected-course ownership and retained material blur.

The same source checkpoint passes the [Release IPA build](https://github.com/54zhien/ccsut/actions/runs/40186243751). Final-revision source/build gates, selected-course/refresh/payment UI gates, screenshot review, independent review and merge verification are tracked with their immutable run links in [PR #15](https://github.com/54zhien/ccsut/pull/15). The checkpoint results alone are not evidence for those later gates.

All tests use synthetic identities, isolated payment journals and offline transports. No real school login, payment, application or attachment upload is performed. Physical-device acceptance and real payment behavior remain separate from these automated checks. The previously disclosed historical PII exposure is outside this integration; repository visibility/history are unchanged.
