# Cancelled pop and academic home refinement

User feedback: score term strip corners are too pill-shaped; all academic
details' title/buttons drift relative to the page during a cancelled right-swipe;
academic home entries bounce unexpectedly when pulled, sit too near the header,
and leave too much unused lower space. Keep the icon and business logic unchanged.

- Use an 18pt continuous radius for the shared score/exam term surface, retaining
  equal widths and pinned Liquid Glass.
- Reproduce partial/cancelled native interactive pop before changing navigation.
  DEBUG CADisplayLink observes the title's presentation position relative to the
  child page. The test must sample actual interactive frames and require <2pt
  relative drift, then confirm cancellation leaves the detail interactive.
- Place a static inline title/back/refresh header in the child page, retaining
  native UINavigationController pop transitions through its public edge/content
  gesture recognizers. Scope gesture delegates to that child and restore original
  delegates/enabled state on disappearance. Root and child both hide the shared
  system bar, avoiding its independent content interpolation.
- Replace home's automatically inset grouped List with one ScrollView and three
  full-width cards. Top spacing24pt, gaps16pt, card heights128–156pt from viewport;
  optional upcoming exam follows the entries so arrival cannot move them. Disable
  bounce only when content fits. Test the no-reminder case and pull settlement.
- Keep the shared Nagi blur and root title motion. Validate cancelled and completed
  pop for all three pages, ordinary back taps, term pinning, all previous UI tests,
  dark/compact screenshots, native gesture recording and Release packaging.
- No merge; preserve baseline and failed-run provenance, review before delivery.
