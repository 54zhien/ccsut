# Journal recovery entry implementation plan

> Execute inline with the executing-plans workflow; independent read-only review at completion.

Goal: implement the user-approved first recovery phase without clearing records or
adding manual unlock. Base dfe4f0020bf90871e1a12d7006ca985d1d6ebcad, separate draft PR.

Approved design: distinguish temporary read failure, unsupported version and
corrupt content; retry local reading; show an exception card instead of the payment
form/bar and a scoped sheet explaining how to verify the original order. Normal
payment, confirmation and receipt UI remain unchanged. No new school write APIs.

- [ ] Add store/model regressions, observe RED, retain evidence.
- [ ] In EcardPaymentPersistence.swift classify errors before decoding payload;
  only genuine file-not-found permits legacy fallback. Persist an account-scoped
  recovery-block marker after failures so disappearance cannot become no-order.
  Preserve original bytes and old defaults. Keep the existing atomic cleared
  journal and pre-debit checkpoint semantics.
- [ ] In EcardPaymentModel.swift expose typed recovery state; stop initialization
  before authentication when recovery is blocked. Retry under account/generation
  guards; only a recovered pending receipt resumes the existing initialization
  and original-order flow. Nil after an error is not an unlock.
- [ ] In EcardPaymentView.swift add only the approved exception card and explanatory
  sheet; no clearing, order input or manual confirmation action. Hide payment UI
  while blocked. Reset sheet presentation on account/recovery changes.
- [ ] Add native UI regressions and light/dark/large-text screenshots using synthetic
  preview states, then inspect rendered results. Keep normal payment regression.
- [ ] Inspect captured protocol metadata and public official scripts read-only;
  report known fields separately from unverified account/transaction association.
- [ ] Run full native suite/build, independent review, and create an unmerged draft.

Test focus: unknown future schema before payload decode; transient read failure;
corrupt legacy data; original bytes preserved; missing file after error/restart;
retry into same pending order; repeated retry never creates/pays; stale account
cannot read or publish another account; unknown/empty records never unlock.

Evidence and final CI SHA belong in the PR after execution. No claim of real-device
or authenticated server-reconciliation acceptance without corresponding evidence.
