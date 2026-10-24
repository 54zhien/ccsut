"""Preserve the supplied artwork as native assets; split seal animation layers."""
import copy
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "ios/CCSUT/Assets.xcassets"
ICON = ROOT / "ios/CCSUT/AppIcon.icon"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def seal(name, layers):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    entries = []
    config = json.loads((ICON / "icon.json").read_text(encoding="utf-8"))
    for dark in [False, True]:
        root = ET.Element(f"{{{SVG}}}svg", {
            "width": "512", "height": "512", "viewBox": "61.989 66.073 508 508",
        })
        for stem in layers:
            source = ET.parse(ICON / "Assets" / f"{stem}.svg").getroot()
            color = None
            if dark:
                layer = next(x for x in config["groups"][0]["layers"] if x["name"] == stem)
                fill = next(x for x in layer["fill-specializations"] if x.get("appearance") == "dark")
                values = fill["value"]["solid"].removeprefix("srgb:").split(",")
                color = "#" + "".join(f"{round(float(x)*255):02x}" for x in values[:3])
            for child in source:
                node = copy.deepcopy(child)
                if color:
                    for e in node.iter():
                        for attr in ["fill", "stroke"]:
                            if e.get(attr) and e.get(attr) != "none":
                                e.set(attr, color)
                root.append(node)
        filename = f"{name}{'-dark' if dark else ''}.svg"
        (folder / filename).write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))
        entry = {"filename": filename, "idiom": "universal"}
        if dark:
            entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        entries.append(entry)
    contents = {"images": entries, "info": {"author": "xcode", "version": 1},
                "properties": {"preserves-vector-representation": True}}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


seal("SchoolEmblemRing", ["01-seal"])
seal("SchoolEmblemCore", ["02-rings", "03-mark", "04-sparks", "05-facets"])
folder = ASSETS / "SchoolSignature.imageset"
folder.mkdir(parents=True, exist_ok=True)
shutil.copyfile(ROOT / "design/brand-source/logo-white-full.png", folder / "SchoolSignature.png")
(folder / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "SchoolSignature.png", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"template-rendering-intent": "template"},
}, indent=2) + "\n", encoding="utf-8")
print("Preserved school seal paths and original signature PNG in adaptive native assets")
