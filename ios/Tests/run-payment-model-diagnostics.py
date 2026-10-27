"""Preserve a failing exit and collect macOS diagnostics; never retry into green."""
import os
import subprocess
import sys

binary = sys.argv[1]
repetitions = int(os.environ.get("CCSUT_PAYMENT_REPETITIONS", "1"))
for attempt in range(1, repetitions + 1):
    print(f"Payment model process {attempt}/{repetitions}", flush=True)
    result = subprocess.run([binary], timeout=90)
    if result.returncode:
        if result.returncode < 0 and sys.platform == "darwin":
            try:
                subprocess.run(["lldb", "--batch", "-o", "run", "-k", "thread backtrace all",
                                "--", binary], timeout=90, check=False)
            except (OSError, subprocess.SubprocessError) as error:
                print(f"Debugger unavailable; retaining original crash: {error}", flush=True)
        sys.exit(result.returncode if result.returncode > 0 else 128 - result.returncode)
