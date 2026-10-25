# Black top material, campus entries and re-login recovery

The user reported that the previous package still looked white/gray at the top in dark mode, requested removal of campus entry subtitles, then supplied screenshots of campus re-login failure. Keep the previously requested compile/package delivery and no-full-tests boundary.

## Evidence and scope

- Baseline product source: c8faa25. It explicitly chooses the dark UIKit material, but has no black tint. A system dark material and the requested black surface are different visual results.
- Add a 92% black tint within the existing masked effect view, so the fade profile, bar size and controls remain unchanged. The tint is hidden in light appearance.
- Remove only the three campus home subtitles; preserve titles, symbols, entry frames and navigation.
- Screenshot 1 shows an authentication notice; screenshot 2 shows the exact fixed string emitted by the browser navigation allowlist. A rejected navigation action is proven, while its destination/frame and the native first-read failure require further investigation. Returning successfully to native records proves that opening the browser can change session state; it does not prove the blocked navigation was the login page.

## Validation ledger

- Focused appearance workflow skips presentation regressions, week tests, interactions and the full static catalog. It renders schedule, academic, campus and scores in light, dark after a live switch, and dark after relaunch.
- First baseline dispatch 40201017140 failed at checkout because a short SHA was treated as a ref name; it did not compile or render. Preserve that failure.
- Correct baseline dispatch 40201164098 uses the full source SHA. Candidate appearance dispatch 40201593835 uses b71f385.
- `verify-top-appearance.py` checks rendered top-band pixels away from status labels and controls. Dark target is <=12/255; light target is >=180/255. This is a rendered-color check, not physical-device acceptance.
- Baseline rendering succeeded; its eight dark/live-dark checks fail the black target with medians `[31,31]`. The four light checks pass with medians around `[241,240]`.
- Candidate rendering succeeded at b71f385; all twelve checks pass. All dark/live-dark medians are `[2,2]`, while light samples remain unchanged. Campus light and dark screenshots were inspected visually: entry subtitles are absent; icons, titles, arrow controls and card frames remain intact. The existing gradient, material and top geometry are retained.
- Authentication regressions: 84 PASS / 0 FAIL. A fixture reproduces a stale transaction overlay overriding CAS cookies rotated by another same-account flow. Recovery starts one fresh transaction only after a rejected validation and a changed current CAS fingerprint; unchanged credentials do not trigger another transaction. Both attempts of forced renewal skip validation of the previously rejected bearer. Tests cover the retry limit, discarded overlays, and account-generation cancellation.
- Browser policy regressions cover blocked subframes/popups without global failure, cancellation of HTTP subframes without replacing the top document, safe default-port upgrade of the main document, and continued rejection of foreign hosts/non-default ports. Successful navigation clears old error state; old completion/failure callbacks check navigation identity.
- The device's rejected URL/frame remains unknown. Anonymous read-only school probes confirm the original serverName parameter and initial CAS service URL match the public flow; XHR/document headers had equivalent anonymous responses. Neither fragments nor headers were established as the device root cause, and the allowlist was not expanded.
- Fixed authentication stage/outcome/credential-change diagnostics exist only in `CampusClient` memory and are not yet displayed by the record UI. They contain no URLs, account IDs, tokens, cookies, response bodies, or hashes. The concurrent-rotation regression proves a code defect, not that it is the sole cause of the reported device symptom.
- Product Swift syntax and whitespace checks passed. Release compilation (including WebKit typechecking) and packaging passed at b1cc6f4646787c6c4ebb6ea14ea03043dedd9dd7, run 40203020944. Physical-device re-login/cold-start acceptance remains open. No full test suite was run.

## Delivered package

- Artifact 12602123603, unsigned IPA, 5,821,218 bytes.
- SHA-256: `ba955b4f056ad3afab29f6c1dee5738a3d4af75eef2fed9297af9ca1e407d549`.
- ZIP CRC valid; display name 长工院, bundle identifier `com.imzhien.ccsut`, minimum iOS 26.0, arm64 Mach-O.
- Appearance evidence is pinned to b71f385 (the later product changes touch authentication only). Authentication evidence is 84 targeted PASS assertions; the package contains both changes.
