# App detail fixes

Scope follows the user's 2026-10-25 correction. Implement directly in the current session; no full test run or merge. Base: origin/main fe11d41.

- [x] TopBarMaterialBackground: explicitly propagate SwiftUI colorScheme to UIKit and select the corresponding system material. Preserve the fade profile and geometry.
- [x] EnrolledCoursesModel: publish only official xkfs=选课 records after validating all result pages. Keep closed-batch online/offline courses and term selection; exclude 配课. Verify mixed-source results with a failing then passing model regression.
- [x] ElectiveView / EnrolledCourseView: remove selected green outlines and the read-only explanation line, retaining action permission checks.
- [x] AcademicView: remove entry subtitles/count summaries; keep service names, icons and navigation.
- [x] PageSurface: optional explicit refresh haptic, enabled on scores/exams/electives/leave/travel/electricity, disabled on the academic home. Fire once when a user refresh begins, never during automatic reads.
- [x] EcardPaymentModel / View: add an awaited read-only refresh preserving selected room, payment journal and pending receipt. Never send a payment from refresh.
- [x] CampusAPI: classify JSON code=401 before returning read responses so bounded CAS renewal runs. Verify both record endpoints, numeric/string codes, permanent rejection, and forbidden responses. Do not retry write requests.
- [x] LoginView: reserve the text's footprint, center the spinner, disable state-change transitions and pressed fading on this button.
- [x] Run only targeted regressions, Swift parsing and diff review. Push a dedicated branch with skip-ci; explicitly dispatch ios.yml for Release compilation/package. Inspect downloaded IPA metadata/CRC/architecture and deliver a usable download link.

Review focus: dark mode switched while mounted; mixed assigned/elective results; expired business bearer with valid CAS; account changes during renewal; pull refresh during payment/room reads. Actual device visuals, haptic strength and campus-session behavior remain device acceptance items.

Validation so far: CampusAPI business-401 regression failed before the fix (five assertions), then passed; elective-scope regression failed twice before the fix, then 40 assertions passed. Payment model targeted suite passed 91 assertions including meter refresh and pending-journal preservation; campus form reads and elective load ownership checks passed. UI sources parse successfully; no simulator or physical-device acceptance is claimed. Release packaging passed at f0e31fa121033f087bd894a59a24f5c9da0c5b6a, run 40200013092.

Delivery verification: artifact 12600998347, IPA SHA-256 2c3954151b738a9a878c31447fa00a020924669767bdfdc596aa548686e2e9e2. ZIP CRC valid; display name and bundle identity preserved; minimum iOS 26.0; arm64 Mach-O. Targeted checks: CampusAPI 62, enrolled-course model 40, payment model 91, campus form API 45, elective load ownership 4 assertions passed. No full CI or UI suite ran. Existing UI expectations were updated for elective-only history, title-only home entries and removed home refresh, and syntax-parsed only. Skill search did not return relevant dark-mode entries; theming follows the existing native system material implementation and supplied requirement.
