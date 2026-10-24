"""Run offline regressions. Windows replaces only the unavailable WebKit boundary.

On macOS the untouched production sources compile against real WebKit, and the
test subclass intercepts every load and JavaScript request without using a server.
"""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="ccsut-ecard-tests-") as directory:
    scratch = pathlib.Path(directory)
    sources = []
    windows = sys.platform == "win32"
    for name in ("EcardAPI.swift", "EcardTokenBridge.swift"):
        original = root / "ios" / "CCSUT" / name
        if windows:
            content = original.read_text(encoding="utf-8-sig")
            content = content.replace("import WebKit", "")
            content = content.replace("import Foundation", "import Foundation\nimport FoundationNetworking", 1)
            target = scratch / name
            target.write_text(content, encoding="utf-8")
            sources.append(str(target))
        else:
            sources.append(str(original))
    sources += [str(root / "ios/Tests/Support/EcardWebKitDouble.swift"),
                str(root / "ios/Tests/EcardRegressionTests.swift")]
    binary = scratch / ("ecard-tests.exe" if windows else "ecard-tests")
    command = ["swiftc"] if windows else ["xcrun", "swiftc"]
    command += ["-swift-version", "5", "-parse-as-library"]
    if windows:
        command += ["-D", "ECARD_WEBKIT_DOUBLE"]
    subprocess.run(command + sources + ["-o", str(binary)], check=True)
    sys.exit(subprocess.run([str(binary)], timeout=60).returncode)
