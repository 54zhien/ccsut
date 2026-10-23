# Content-fitting web login and reliable teaching-week state

Current user scope:
- SMS failure report was withdrawn: the user installed the preceding IPA.
  Keep authentication JavaScript and SMS/account input spacing unchanged.
- Web login uses a content-sized native Liquid Glass sheet and glass controls,
  top-left close, top-right refresh, bottom-right Safari, default symbol colors.
  Remove pull-to-refresh entirely. Single fixed-at-content-height detent capped
  naturally by the system; longer pages remain scrollable.
- Remove the newly addedbar material that device feedback identifies as a white
  block. Keep the shared native safeAreaBar and soft scroll-edge implementation.
- Move the login group up by anchoring the credential form at the screen center,
  measuring brand/form heights; constrained/keyboard layouts scroll normally.
- Profile identity group centered in the sheet; compact logout. Profile/course
  close icons use ButtonRole.close with native sizing and colors. Account entry
  reuses the profile avatar at28pt inside its48pt glass control.
- Teaching-week API must not turn an absent/malformed response into week1.
  Decode string or integer, validate, cache a verified week/account/term/date,
  and advance cached weeks by Shanghai calendar weeks. Without verified data,
  show an unknown-week notice and do not label week1 as current.

Evidence: read-only public CAS DOM viaagent-browser shows the existing selectors
still match the SMS tab, both text fields and send button. No phone/account was
entered and no SMS request was sent. Native SMS report was explicitly withdrawn.
API.currentTeachingWeek currently returns1 for nil or non-integerxlzc, and the
view also silently ignores errors withtry?. These are distinct false-week paths.

Apple documentation checked: ButtonRole.close; presentationDetents/.height;
Liquid Glass sheet adaptivity and nativeglass button style. No custom full-sheet
glass overlay. User's no-app-tests instruction persists; only source review,
Release compilation and artifact inspection. Keep draftPR2 unmerged.

- [ ] Implementation and source review.
- [ ] Release compilation/package and IPA integrity/metadata/hash inspection.
