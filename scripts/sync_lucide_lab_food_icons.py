#!/usr/bin/env python3
"""
Import selected food-relevant Lucide Lab icons into Calorie Tracker assets as
single-color template SVGs (stroke #000).

Source package: https://unpkg.com/@lucide/lab@0.1.2/icons/<icon>.svg
"""
from __future__ import annotations

import json
import re
import subprocess
import urllib.request
from pathlib import Path

LUCIDE_LAB_BY_FOOD_ICON: dict[str, str] = {
    "FoodIconAvocado": "avocado",
    "FoodIconBacon": "bacon",
    "FoodIconBarbecue": "barbecue",
    "FoodIconBowlChopsticks": "bowl-chopsticks",
    "FoodIconCheese": "cheese",
    "FoodIconCoconut": "coconut",
    "FoodIconCoffeeBean": "coffee-bean",
    "FoodIconCoffeeMaker": "coffeemaker",
    "FoodIconCupToGo": "cup-to-go",
    "FoodIconEggCup": "egg-cup",
    "FoodIconFruit": "fruit",
    "FoodIconKebab": "kebab",
    "FoodIconLemon": "lemon",
    "FoodIconMealBox": "meal-box",
    "FoodIconMugTeabag": "mug-teabag",
    "FoodIconOlive": "olive",
    "FoodIconOnion": "onion",
    "FoodIconPancakes": "pancakes",
    "FoodIconChiliPepper": "pepper-chilli",
    "FoodIconPie": "pie",
    "FoodIconPineapple": "pineapple-ring",
    "FoodIconSausage": "sausage",
}


def normalize_svg(raw: str) -> str:
    raw = raw.replace('stroke="currentColor"', 'stroke="#000"')
    raw = re.sub(r"\s*width=\"24\"\s*\n", "\n", raw)
    raw = re.sub(r"\s*height=\"24\"\s*\n", "\n", raw)
    inner = re.search(r"<svg[^>]*>(.*)</svg>", raw, re.DOTALL)
    if not inner:
        raise ValueError("unparseable svg")
    body = inner.group(1).strip()
    lines = [ln.strip() for ln in body.splitlines() if ln.strip()]
    indented = "\n".join(f"  {ln}" for ln in lines) + "\n"
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" '
        'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">\n'
        f"{indented}</svg>\n"
    )


def fetch_svg(icon_name: str) -> str:
    url = f"https://unpkg.com/@lucide/lab@0.1.2/icons/{icon_name}.svg"
    result = subprocess.run(
        ["curl", "-fsSL", url],
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout


def ensure_imageset(imageset_dir: Path, filename: str) -> None:
    imageset_dir.mkdir(parents=True, exist_ok=True)
    contents = {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "preserves-vector-representation": True,
            "template-rendering-intent": "template",
        },
    }
    (imageset_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    assets = root / "Calorie Tracker" / "Assets.xcassets"

    for food_name, lab_name in sorted(LUCIDE_LAB_BY_FOOD_ICON.items()):
        raw = fetch_svg(lab_name)
        normalized = normalize_svg(raw)

        imageset_dir = assets / f"{food_name}.imageset"
        svg_name = f"{food_name}.svg"
        ensure_imageset(imageset_dir, svg_name)
        (imageset_dir / svg_name).write_text(normalized)
        print(f"wrote {imageset_dir.relative_to(root)}/{svg_name} <- {lab_name}.svg")

    print(f"done {len(LUCIDE_LAB_BY_FOOD_ICON)} Lucide Lab icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
