# Payment recovery repair

The user authorized fixing the confirmed payment recovery, lost order number,
and payment-model state bugs, with regression tests. Other UI and features are
out of scope. Base: `0ba689544a1bd0a3edb0f2ae80e2cd70008c6c22`.

Keep the existing view and confirmation flow. Atomically record a pending
receipt, scoped to the account, after obtaining a usable order and before
dispatching payment. If recording fails, do not dispatch payment. Migrate old
UserDefaults receipts without dropping unreadable records. An unresolved or
unreadable receipt blocks another payment. Completion can clear only that
order's record; stale tasks must not clear a newer order or publish across
accounts/generations.

After a payment request, preserve its order number for uncertain transport or
business responses and query that original order without resubmitting. No
service contract proving business failures have no side effects is available,
so prefer pending over enabling another debit. Definitive errors before payment
remain ordinary errors.

Inject session/client/persistence boundaries into the existing model for offline
tests. On startup invalidation, end both background-login and initial-data
waiting states with a recoverable error. A replacement startup supersedes old
tasks; an old completion must not overwrite its state. Preserve pending orders
while rebuilding authentication and querying results.

An atomic file journal is chosen over UserDefaults-only storage because the
record must be written before payment, not merely queued for later defaults
flushing. Existing UI renders the current receipt/error states unchanged.

Verification: offline HTTP fixtures and isolated temporary journals, real model
and API code, no real school requests, RED then GREEN. macOS CI must compile and
run the model with actual WebKit dependencies and build the iOS app. No merge,
real payment, or physical-device acceptance is implied.
