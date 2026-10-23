# Native chrome, glass sheets and school-blue refinement

User-directed scope: remove week trailing animation; port Nagi's native top bar
instead of the custom blur overlay; enlarge academic card corners; revise course
and account medium sheets; use school blue for theme accents; revise login input
and capsule buttons, monochrome seal and brand spacing; use Chinese failure text.
Score/exam semester strips must wait until the next strip is very close to the
current pinned strip before becoming glass.

Nagi source inspected locally at9f5cd1a in Seidoku Local Reader. LibraryView uses
safeAreaBar and soft scroll-edge effects, while SearchView contains the older
masked material. The previous CCSUT implementation combined that SearchView
overlay with its own style overrides. Port the actual LibraryView native top-bar
structure, including the scroll-edge treatment, and back its full safe area with
an adaptive system background. Do not keep the extra custom material overlay.

- [x] Remove WeekCapsuleTrail/history/display link/visual transforms. Keep normal
  horizontal scrolling, independent glass capsules and default selected centering.
- [x] Native Nagi top bar on both roots and academic details; preserve static
  detail title and UIKit-owned return transitions.
- [x] Academic entry cards:28pt continuous corners, same compact height.
- [x] Shared glass sheet surface and consistent44pt dismiss control. Course
  details use centered course identity and native labeled rows; medium only.
  Profile uses centered avatar, name, student number and a centered logout button.
- [x] Theme accent from emblem mark#0878B7; dark counterpart#62C2F5. Apply to
  interactive and decorative accents, retaining semantic failure/warning colors.
- [x] Login:28pt input group, capsule filled buttons, no login arrow,48pt brand
  separation; template monochrome seal. Keep keyboard/CAS flow unchanged.
- [x] Launch label:登陆中. Loading failures show加载失败，请重试, without raw
  transport/server English. Preserve internal errors and business control flow.
- [x] Shared semester header tracker compares visible surface frames with the
  actual scroll viewport and top inset. A pinned strip is glass; its successor
  becomes glass only within8pt. Cache geometry without observation and publish
  only threshold changes, retaining18pt corners and equal widths.
- [ ] User's no-test instruction persists: source review and Release packaging
  only, then artifact integrity/bundle metadata inspection. No app-test claim.
