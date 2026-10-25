"""Run offline payments; macOS also tests callbacks against real WebKit.
Windows runs production API/model code with explicit unavailable-platform stubs.
No production Swift source is rewritten. All browser loads are intercepted.
"""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
windows = sys.platform == "win32"
if windows:
    common = [
        "ios/CCSUT/EcardAPI.swift", "ios/CCSUT/WebSessionCookies.swift",
        "ios/CCSUT/EcardPaymentPersistence.swift", "ios/CCSUT/EcardPaymentModel.swift",
        "ios/Tests/EcardPaymentPlatformStubs.swift",
    ]
    suites = ["EcardPaymentAPITests", "EcardPaymentModelTests"]
else:
    common = [
        "ios/CCSUT/Session.swift", "ios/CCSUT/API.swift", "ios/CCSUT/APIResponse.swift",
        "ios/CCSUT/Models.swift", "ios/CCSUT/EnrolledCourses.swift", "ios/CCSUT/ElectiveState.swift",
        "ios/CCSUT/AcademicAPI.swift", "ios/CCSUT/AcademicCalendar.swift",
        "ios/CCSUT/SchedulePresentation.swift", "ios/CCSUT/EcardAPI.swift",
        "ios/CCSUT/EcardTokenBridge.swift", "ios/CCSUT/WebSessionCookies.swift",
        "ios/CCSUT/EcardSSOClient.swift", "ios/CCSUT/EcardSSOSession.swift",
        "ios/Tests/Support/EcardWebKitDouble.swift",
    ]
    suites = ["EcardRegressionTests"]

with tempfile.TemporaryDirectory(prefix="ccsut-ecard-tests-") as directory:
    for suite in suites:
        binary = pathlib.Path(directory) / (suite + (".exe" if windows else ""))
        command = ["swiftc"] if windows else ["xcrun", "swiftc"]
        sources = [str(root / name) for name in common + [f"ios/Tests/{suite}.swift"]]
        subprocess.run(command + ["-parse-as-library"] + sources + ["-o", str(binary)], check=True)
        result = subprocess.run([str(binary)], timeout=60)
        if result.returncode < 0 and sys.platform == "darwin":
            subprocess.run(["lldb", "--batch", "-o", "run", "-k", "thread backtrace all", "--", str(binary)], timeout=45)
        if result.returncode:
            sys.exit(result.returncode)
