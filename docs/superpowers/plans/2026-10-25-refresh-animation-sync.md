# Timetable refresh animation synchronization

User requirement: other existing refreshable pages must have the timetable's native pull animation, retained loading region and dismissal. Data freshness is not currently known. Keep page content and loading actions.

Implementation:
- Share the timetable's viewport / reader / vertical scroll arrangement on the five other refresh surfaces (travel and leave share one surface).
- Own the system `UIRefreshControl` as a subview of the actual vertical scroll view. Await the existing action before ending it. Detaching cancels the owner; a revision check prevents an old completion ending a newly attached refresh.
- Keep the working timetable implementation, academic load gates, API calls, authentication and writes unchanged. Campus refresh joins a read already in flight, including publication, instead of returning immediately; it sends no additional request. No artificial minimum delay or custom spinner.
- DEBUG-only controlled reads let UI tests capture screenshots before explicitly completing the read. Assert a held gap greater than 40 points and return to the resting position; also exercise empty content, pinned headers and swipe back.

Evidence retained on `codex/refresh-navigation-diagnosis`:
- 40178129369: same-simulator screenshots reproduce the good timetable / collapsed score contrast while both completions are held.
- 40179739102 at cef415b: baseline rendered-position assertion fails with a 0-point gap.
- 40179838441 at 60ad49e: copying only the timetable hierarchy also fails with a 0-point gap. Source similarity alone does not repair the lifecycle.
- 40178591876: independent native subview reference shows the native spinner and retained region; its native ScrollView reference failed separately.
- 40180680701 at 04cb8d7: integrated native-control verification, pending at cleanup.
- 40181418330 at eb6746b: leave and travel in-flight join assertions both fail against the old guard; cancellation and request-count assertions pass. The completion latch fixes these semantics and releases joined refreshes on cancellation.

This branch starts at the user's 0ba6895 source and excludes the exploratory runtime setup, omission flags and deliberately failing experimental tests. Simulator verification is separate from physical-device acceptance.
