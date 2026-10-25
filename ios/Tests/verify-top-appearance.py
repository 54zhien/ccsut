"""Check rendered top-band pixels, including appearance switched while mounted.

Use only synthetic simulator captures from UI preview's appearance-screens scope.
The two sample regions avoid the island, status labels and header controls.
"""
import argparse
import json
import pathlib
import statistics

from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("screenshots", type=pathlib.Path)
args = parser.parse_args()
results = []
for page in ("schedule", "academic", "campus", "scores"):
    for mode in ("light", "dark", "dark-live"):
        path = args.screenshots / f"{page}-{mode}.png"
        with Image.open(path).convert("RGB") as image:
            w, h = image.size
            medians = []
            for left, right in ((0.05, 0.09), (0.91, 0.95)):
                region = image.crop((int(w * left), int(h * 0.04), int(w * right), int(h * 0.065)))
                medians.append(statistics.median(max(pixel) for pixel in region.getdata()))
        passed = min(medians) >= 180 if mode == "light" else max(medians) <= 12
        results.append({"page": page, "mode": mode, "top_medians": medians, "passed": passed})
        print(f"{'PASS' if passed else 'FAIL'} {page} {mode}: top band {medians}")
(args.screenshots / "top-appearance-verification.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
raise SystemExit(0 if all(row["passed"] for row in results) else 1)
