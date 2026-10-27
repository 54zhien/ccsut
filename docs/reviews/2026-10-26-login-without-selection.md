# Login must not depend on an open elective channel

## Report and root cause

User's device displays `接口返回错误 [-1] 没有可选的教学班` on the native SMS
login screen. Both `SessionStore.verifySession()` and `loadProfile()` used elective
initialization `/admin/xsd/xk/listV2`. Its business rejection prevented WebKit cookie
adoption and cold-start validation even after school authentication succeeded.
The screenshot does not independently prove that every school's elective channel
is closed; the verified bug is treating elective availability as an authentication
requirement.

## Evidence boundary

- The existing project probe `_tk.mjs` records the previously observed protected
  `/admin/` entry redirect to the student portal with `username`, `enc`, `dbname`.
  That script was inspected, not executed; its raw credential logging must not be
  reused in production or diagnostics.
- Current anonymous control on 2026-10-26: `/admin/` returns 303 `/admin/login`.
- Current anonymous `/admin/api/getXlzc` returns `ret:0` calendar data. It is public
  and is **not** an authentication or identity probe.
- Current public official `xkPage/js/index.js` uses listV2 for elective setup and
  optional name/number rendering; it is not an independent session contract.
- A dedicated official browser was opened. User could not log in on the computer
  now; it was closed. No fresh authenticated school request was made this turn.
  The alternative redirect contract therefore still needs physical-device/live
  acceptance, and no school-wide channel closure or session lifetime is claimed.

## Fix

- `APIClient.authenticatedProfile()` uses a navigation-style, fixed HTTPS GET to
  the protected `/admin/` entry with a matching TLS cookie and captured generation.
  It inspects the first redirect without fetching the public landing page.
- `StudentIdentity` accepts only the protected initial origin/path and exact known
  HTTPS student portal target, with unique nonempty `username` and `enc`. It rejects
  arbitrary 200 pages, login pages, foreign hosts, userinfo, nondefault ports,
  fragments, ambiguous identities and control characters. It stores only the
  student number, never the query proof. `URL.path` trailing-slash normalization
  is handled for `/admin/`; the actual request URL is fixed.
- All existing transport callers retain their prior redirect-following behavior.
  Cancellation/generation checks and staged cookie updates precede redirect parsing.
- Session adoption, cold bootstrap and renewal publish the generation-bound
  verified identity before exposing logged-in UI. Cached names are reused only for
  the same account; silent verification rejects a different server account.
- `loadProfile()` reuses same-generation verified identity. Elective initialization
  only enriches the name when its student number matches; failure is ignored for
  authentication. The timetable consumer uses the same independent identity.
- Remember-me, campus authentication, UI and payment/application behavior remain
  otherwise unchanged.

## Verification and preserved provenance

- RED run `40261605894` at `f671467`: production code compiled; the scripted closed
  elective response produced 6 expected semantic failures for login/adoption and
  cold start. Existing negative cases stayed rejected.
- Focused GREEN run `40262971568` at `e578a8f`: 18 native production login/session
  assertions passed, plus 25 identity-parser boundary assertions. No real school
  requests were used. The production source tree equals product `dac5ea0`.
- The new workflow name initially could not dispatch because it was absent from
  the default branch. Focused verification was moved into the existing workflow.
- Run `40262180831` was cancelled by the old shared build concurrency group. The
  login/package groups are now separate; cancellation is not counted as success.
- Release run `40262183882` failed on the outdated timetable return-type consumer;
  `ScheduleView` was corrected. The failed run remains available.
- Superseded run `40262217688` passed its login and parser portions, then was
  stopped while an additional broader session runner was pending on the older
  source/fixtures. Its three log files were retained, including the empty pending
  session log. No broader session-suite pass is claimed. Legacy valid-identity
  fixtures were migrated and syntax-parsed; the final focused run is the current
  runtime evidence. No full test suite or simulator UI suite was run for this fix.

## Delivery

- Product source: `dac5ea080575250cebbf540ed33652b26d39a6a3`.
- Release Compile & Package: `40262546174`, success. IPA artifact `12624827527`.
- 5,882,822 bytes; SHA-256
  `c11c04c071bfb3ab70ef9b53cd942193be4758670cf46d5c1128c78ba8cd59db`.
- ZIP CRC, arm64 Mach-O, display name 长工院, bundle `com.imzhien.ccsut` and iOS 26.0
  verified. Device login with the current school's authenticated redirect remains
  the final acceptance item.
