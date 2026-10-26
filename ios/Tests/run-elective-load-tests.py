"""Exercise ElectiveView's actual load orchestration without a SwiftUI runtime.

The production load/fetch methods and PageLoadGate are extracted on every run.
Only the catalog network boundary and account generation are replaced; enrolled
results use the real model. Keep this runner when changing the production methods.
"""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]


def declaration(path, marker):
    source = path.read_text(encoding="utf-8-sig")
    if source.count(marker) != 1:
        raise RuntimeError(f"Expected one {marker!r} in {path}")
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth and end < len(source):
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if depth:
        raise RuntimeError(f"Unclosed declaration in {path}")
    return source[start:end]


with tempfile.TemporaryDirectory(prefix="ccsut-elective-load-tests-") as directory:
    scratch = pathlib.Path(directory)
    load = declaration(root / "ios/CCSUT/ElectiveView.swift", "private func load(force:")
    # The host is a reference type instead of a SwiftUI value view. This capture
    # is the only syntax adaptation; every statement in load stays production.
    load = load.replace("private func load", "func load", 1)
    load = load.replace("await loadGate.run {", "await loadGate.run { [self] in", 1)
    gate = declaration(root / "ios/CCSUT/PageSurface.swift", "final class PageLoadGate")
    harness = (root / "ios/Tests/ElectiveLoadTests.swift").read_text(encoding="utf-8-sig")
    harness = harness.replace("// PRODUCTION_PAGE_LOAD_GATE", "@MainActor\n" + gate)
    harness = harness.replace("// PRODUCTION_ELECTIVE_LOAD", load)
    for marker, placeholder in [
        ("private func fetch(force:", "// PRODUCTION_ELECTIVE_FETCH"),
        ("private func records(for", "// PRODUCTION_ELECTIVE_RECORDS"),
    ]:
        method = declaration(root / "ios/CCSUT/ElectiveView.swift", marker)
        harness = harness.replace(placeholder, method.replace("private func", "func", 1))
    generated = scratch / "ElectiveLoadTests.swift"
    generated.write_text(harness, encoding="utf-8")
    sources = [root / "ios/CCSUT" / name for name in
               ("APIResponse.swift", "Models.swift", "ElectiveState.swift", "EnrolledCourses.swift")]
    binary = scratch / ("elective-load-tests.exe" if sys.platform == "win32" else "elective-load-tests")
    command = ["swiftc"] if sys.platform == "win32" else ["xcrun", "swiftc"]
    subprocess.run(command + ["-swift-version", "5", "-parse-as-library"] +
                   [str(path) for path in sources + [generated]] + ["-o", str(binary)], check=True)
    sys.exit(subprocess.run([str(binary)], timeout=60).returncode)
