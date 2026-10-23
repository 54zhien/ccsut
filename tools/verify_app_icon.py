"""Verify the compiled primary icon, including actual light/dark vector fills."""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = json.loads((root / "ios/CCSUT/AppIcon.icon/icon.json").read_text())
catalog = json.loads(Path(sys.argv[1]).read_text())
colors = {a["Name"]: a for a in catalog if a.get("AssetType") == "Color"}
gradients = {a["Name"]: a for a in catalog if a.get("AssetType") == "Named Gradient"}


def fill_colors(layer):
    name = layer.get("LayerGradientColorName", layer.get("Name"))
    if name in colors:
        c = colors[name]["Color components"]
        return [c if len(c) == 4 else [c[0]] * 3 + [c[1]]]
    return [fill_colors({"Name": n})[0] for n in gradients[name]["Gradient Colors"]]


report = {}
for appearance, variant in [("UIAppearanceLight", 0), ("UIAppearanceDark", 1)]:
    stacks = [a for a in catalog if a.get("AssetType") == "IconImageStack"
              and a.get("Name") == "AppIcon" and a.get("Appearance") == appearance]
    assert len(stacks) == 1, (appearance, "Missing primary icon stack")
    stack = stacks[0]
    assert stack["CanvasWidth"] == stack["CanvasHeight"] == 1024
    groups = [a for a in stack["Layers"] if a.get("AssetType") == "IconGroup"]
    assert len(groups) == 1
    group = groups[0]
    actual = {a["Name"].rsplit("/", 1)[-1]: a for a in group["Layers"]}
    assert len(actual) == 5
    fills = {}
    for layer in source["groups"][0]["layers"]:
        compiled = actual[layer["name"]]
        assert compiled["AssetType"] == "Vector"
        assert compiled["LayerHasLightingEffects"]
        expected = [float(x) for x in layer["fill-specializations"][variant]["value"]["solid"].split(":")[1].split(",")]
        found = fill_colors(compiled)
        assert all(all(round(a * 255) == round(b * 255) for a, b in zip(c, expected)) for c in found), (layer["name"], found)
        fills[layer["name"]] = found
    background = next(a for a in stack["Layers"] if a.get("AssetType") != "IconGroup")
    bg = fill_colors(background)
    assert len(bg) >= 2, "Expected system default background gradient"
    luminance = sum(sum(c[:3]) / 3 for c in bg) / len(bg)
    assert luminance > 0.8 if variant == 0 else luminance < 0.25, (appearance, bg)
    report[appearance] = {"fills": fills, "background": bg,
                          "shadowStyle": group.get("LayerShadowStyle"),
                          "shadowOpacity": group.get("LayerShadowOpacity")}
assert "shadow" not in source["groups"][0], "Use the system default shadow"
print(json.dumps({"state": "PASS", "appearances": report}, indent=2))
