# Direct student home rejected after successful CAS login

The user reported that sending an SMS displayed the missing-authentication-form
hint, while opening the web sheet showed the academic-warning notice inside the
authenticated academic site. They also reported the send control's fade returning.

## Confirmed live cause

The user completed a fresh school login in a dedicated browser on 2026-10-26.
A fixed HTTPS GET to `/admin/`, with the same navigation headers as the native
probe, returned HTTP 200 and the server-rendered student home, with no Location
header. This contradicts the preceding implementation's assumption that the
protected entry must redirect to the elective page carrying username/enc.

The home includes hidden `roleId=xs`, xhid and encodeId fields, plus the account
in `.userInfo .admin_name`. The production Swift parser was executed against
the actual response in memory. It accepted the home and its parsed identity
matched the browser account. No password, SMS code, cookie value, account number,
proof, full HTML or private response was saved in this evidence. The dedicated
browser was closed after the read-only checks.

## Changes

- Accept the observed HTTP 200 student home from the fixed, protected HTTPS
  `/admin/` request. Require the student role, unique hidden student context/proof
  fields and a unique valid account in the student header. Preserve the existing
  server-issued elective redirect path. Arbitrary 200/login/public pages,
  query-influenced response URLs, foreign origins and ambiguous identity remain
  rejected. Existing generation/cancellation checks still precede publication.
- Verify a committed academic document without waiting for all its resources.
  Sending SMS or opening web login from an existing portal page first adopts the
  current session. The CAS script recognizes a completed portal navigation and
  returns to native verification instead of reporting missing tabs/forms.
- Keep the send text and spinner mounted at the right edge. Disable content
  transitions and animation across the entire button, including enabled-state
  changes. The hint also uses an identity transition.

## Verification and provenance

- Existing-session RED: the original embedded script failed three portal cases;
  extracted native production actions failed four state-recovery assertions.
- Home-response RED: `ac019cc`, run `40265711129`, compiled and failed exactly
  four native assertions for HTTP 200 probing, adoption, identity and cold start.
- GREEN: product `ad35f0c`, focused run `40266109917`, passed 22 native session
  checks, 25 redirect identity boundaries, 23 student-home boundaries, five
  extracted production action checks and 22 JavaScript/privacy checks.
- Live production-parser check: protected home accepted; parsed account matches
  the freshly logged-in browser account. Credentials/HTML passed only in memory.
- The earlier candidate `9e9fc73` passed package run `40265140345`, but lacks the
  subsequently confirmed home-response fix and is not the final delivery.
- Final Release compile/package: `40266112799` at `ad35f0c`, passed. Artifact
  `12626890223` contains the final IPA (5,891,172 bytes). ZIP CRC, arm64 Mach-O,
  display name, bundle `com.imzhien.ccsut` and iOS 26.0 metadata passed inspection.
  SHA-256: `cf8101442efc27e90e87ce9f859af30a03d5dc53d2b4a827dd2f01e487c34389`.

No full test suite or simulator UI suite was run. Physical iPhone login,
cold-start behavior and the send control's visual transition remain device
acceptance items. No main merge is implied.
