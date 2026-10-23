"""Derive Icon Composer layers from the supplied outlined school seal.

Path geometry is preserved; only color, layer grouping and canvas change.
Run from the repository root. No third-party packages are needed.
"""
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "design/icon-source/school-emblem.svg"
OUTPUT = ROOT / "ios/CCSUT/AppIcon.icon"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def srgb(hex_color):
    rgb = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return "srgb:" + ",".join(f"{v:.8f}" for v in [*rgb, 1])


def generate():
    original = ET.parse(SOURCE).getroot()
    by_id = {e.get("id"): e for e in original.iter() if e.get("id")}
    center = by_id["central-emblem"]
    ring_nodes = [e for e in center if any(c.get("id") in
                  {"emblem-teal-ring", "emblem-navy-ring"} for c in e)]
    oranges = [by_id["emblem-orange-top"], by_id["emblem-orange-bottom"]]
    layers = [
        ("01-seal", [by_id[k] for k in ["outer-border-and-dots", "chinese-name", "english-name"]], "#126D9F", "#6CC4F2"),
        ("02-rings", ring_nodes, "#17468F", "#348FCA"),
        ("03-mark", [by_id["emblem-left-glyph"], by_id["emblem-right-glyph"]], "#0878B7", "#62C2F5"),
        ("04-sparks", [e[0] for e in oranges], "#FF9F18", "#FFAD33"),
        ("05-facets", [e[1] for e in oranges], "#FFC16A", "#FFD18A"),
    ]
    config = json.loads((ROOT / "design/icon-source/nagi-icon.json").read_text(encoding="utf-8"))
    config.pop("fill", None)
    config["fill-specializations"] = [{"value": "system-light"},
                                        {"appearance": "dark", "value": "system-dark"}]
    group = config["groups"][0]
    template = copy.deepcopy(group["layers"][0])
    # Inherit default neutral shadow and automatic specular from Icon Composer.
    group.pop("shadow", None)
    group["translucency"] = {"enabled": False, "value": 0.5}
    group["layers"] = []
    (OUTPUT / "Assets").mkdir(parents=True, exist_ok=True)
    source_paths = sorted(e.get("d") for e in original.iter(f"{{{SVG}}}path"))
    derived_paths = []
    for name, elements, light, dark in layers:
        root = ET.Element(f"{{{SVG}}}svg", {
            "width": "1024", "height": "1024",
            # Optically center the supplied seal without altering path geometry.
            "viewBox": "-4.011 0.073 640 640",
        })
        for element in elements:
            element = copy.deepcopy(element)
            for e in element.iter():
                if "fill" in e.attrib and e.get("fill") != "none":
                    e.set("fill", light)
                if "stroke" in e.attrib and e.get("stroke") != "none":
                    e.set("stroke", light)
            root.append(element)
        derived_paths.extend(e.get("d") for e in root.iter(f"{{{SVG}}}path"))
        ET.ElementTree(root).write(OUTPUT / "Assets" / f"{name}.svg", encoding="utf-8", xml_declaration=True)
        layer = copy.deepcopy(template)
        layer.update({"name": name, "image-name": f"{name}.svg", "opacity": 1,
                      "position": {"scale": 1, "translation-in-points": [0, 0]},
                      "fill-specializations": [
                          {"value": {"solid": srgb(light)}},
                          {"appearance": "dark", "value": {"solid": srgb(dark)}},
                      ]})
        group["layers"].append(layer)
    assert sorted(derived_paths) == source_paths, "School seal path geometry was lost or duplicated"
    # The only original non-path shapes are the outer circle and its two dots.
    assert sum(len(list(ET.parse(OUTPUT / "Assets" / f"{n}.svg").getroot().iter(f"{{{SVG}}}circle")))
               for n, *_ in layers) == 3
    (OUTPUT / "icon.json").write_bytes((json.dumps(config, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    print(f"Preserved {len(source_paths)} outlined paths and three circles in five vector layers")


if __name__ == "__main__":
    generate()
