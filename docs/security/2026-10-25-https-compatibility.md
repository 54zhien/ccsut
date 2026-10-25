# Scoped authentication transport compatibility

Base: `9c37b5b5fb024da16f1d0c93f03f90830fd80cc7` (PR #9).
User scope: fix the two confirmed HTTP-to-HTTPS compatibility failures, preserve
security checks and WebView fallback policy, add regressions, open a separate
draft PR without merging. No UI, payment-model or other feature changes.

## Evidence and boundary

The earlier investigation reproduced `APIError.notLoggedIn` for an HTTP academic
CAS hop and `EcardSSOError.untrustedRedirect` for HTTP SSO hops. The bridge treats
the latter as terminal. Anonymous live probes on 2026-10-25 observed HTTPS on the
academic entry, ecard entry and gateway CAS configuration; the academic auth page
disconnected. No authenticated live HTTP redirect was captured. This patch fixes
the demonstrated conditional behavior, not a claimed universal live outage.

Only an outer transport URL is upgraded, before cookie matching or dispatch:

- Academic HTTP: exactly `tls.ccsut.cn` and `auth.ccsut.cn`.
- Ecard HTTP: the existing `ecard.ccsut.cn`, `zts.ccsut.cn`, `auth.ccsut.cn` list.
- HTTP default port or explicit 80 becomes HTTPS default port. Other HTTP ports
  are rejected; HTTPS uses default port or 443. Userinfo and fragments are rejected.
- Path, encoded query, tickets and nested `service`/`targetUrl` values are not
  rewritten. Ecard nested URLs still require the existing HTTPS/path/parameter
  contract. A nested HTTP service is still rejected rather than silently changing
  the service to which a CAS ticket may be bound.
- Existing HTTPS academic school-domain policy remains; HTTP upgrade does not
  extend to arbitrary school subdomains. Existing business/authentication gating,
  POST forwarding prohibition, time budgets, account generations and cancellation
  remain active. The academic normalizer also rejects userinfo, fragments and
  nonstandard HTTPS ports instead of forwarding credentials to ambiguous URLs.
- Ecard `resolve` and configured login URL parsing use the narrow normalizer,
  then retain existing route, query, redirect-edge and identity checks. Token POST
  redirects are still rejected. `EcardTokenBridge.swift` is unchanged.

## Verification

- RED commit: `aa53000ca1e9b6de3086bdd2d8983904920781dd`.
- Native RED run: https://github.com/54zhien/ccsut/actions/runs/40167079583
  compiled successfully and reproduced two academic and two ecard behavior
  failures (default port and explicit 80). The failed run is retained.
- Added coverage: successful full native renewal/SSO with upgraded redirects and
  config, Secure-cookie selection, original ticket/service bytes, authorization
  scoping, rejection boundaries, redirect limits and account-generation changes.
- Existing bridge regressions continue to require untrusted redirects and account
  mismatches to terminate without launching WebView.
- Exact final SHA, full native workflow and simulator-build results are recorded
  in the draft PR after execution. No live login, payment or school write is run.

UI and real-device behavior are not newly validated by these synthetic protocol
fixtures. The known historical PII exposure remains outside this change; the user
has explicitly chosen to keep the repository public.
