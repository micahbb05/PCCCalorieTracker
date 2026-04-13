#!/usr/bin/env python3
"""
Copy official Lucide icons (ISC license, https://github.com/lucide-icons/lucide) into
Calorie Tracker `FoodIcon*.imagesets` as single-color template SVGs (stroke #000).

If `/tmp/lucide-icons` is missing, runs: `git clone --depth 1 https://github.com/lucide-icons/lucide.git /tmp/lucide-icons`
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

# FoodIcon imageset name -> Lucide icons/*.svg basename (without .svg)
LUCIDE_BY_FOOD_ICON: dict[str, str] = {
    "FoodIconApple": "apple",
    "FoodIconBanana": "banana",
    "FoodIconBean": "bean",
    "FoodIconBeer": "beer",
    "FoodIconBottleWine": "bottle-wine",
    "FoodIconBread": "croissant",
    "FoodIconBurger": "hamburger",
    "FoodIconBurrito": "cylinder",
    "FoodIconCake": "cake",
    "FoodIconCakeSlice": "cake-slice",
    "FoodIconCandy": "candy",
    "FoodIconCandyCane": "candy-cane",
    "FoodIconCarrot": "carrot",
    "FoodIconChefHat": "chef-hat",
    "FoodIconCherry": "cherry",
    "FoodIconChicken": "drumstick",
    "FoodIconCitrus": "citrus",
    "FoodIconCoffee": "coffee",
    "FoodIconCookie": "cookie",
    "FoodIconCookingPot": "cooking-pot",
    "FoodIconCupSoda": "cup-soda",
    "FoodIconDonut": "donut",
    "FoodIconEgg": "egg",
    "FoodIconEggFried": "egg-fried",
    "FoodIconFish": "fish",
    # Custom-drawn in-repo fries box glyph; do not sync this from Lucide core.
    "FoodIconGlassWater": "glass-water",
    "FoodIconGrape": "grape",
    "FoodIconHam": "ham",
    "FoodIconHotDog": "sandwich",
    "FoodIconIceCream": "ice-cream-cone",
    "FoodIconIceCreamSandwich": "cookie",
    "FoodIconLollipop": "lollipop",
    "FoodIconMartini": "martini",
    "FoodIconMicrowave": "microwave",
    "FoodIconMilk": "milk",
    "FoodIconNut": "nut",
    "FoodIconPasta": "cooking-pot",
    "FoodIconPizza": "pizza",
    "FoodIconPopsicle": "popsicle",
    "FoodIconPork": "beef",
    "FoodIconProtein": "dumbbell",
    "FoodIconRamen": "soup",
    "FoodIconRefrigerator": "refrigerator",
    "FoodIconRiceBowl": "salad",
    "FoodIconSalad": "salad",
    "FoodIconSandwich": "sandwich",
    "FoodIconShoppingBasket": "shopping-basket",
    "FoodIconShrimp": "shrimp",
    "FoodIconSnail": "snail",
    "FoodIconSoup": "soup",
    "FoodIconSushi": "fish",
    # Temporary fallback per app request: use cylinder glyph for taco.
    "FoodIconTaco": "cylinder",
    "FoodIconUtensils": "utensils",
    "FoodIconUtensilsCrossed": "utensils-crossed",
    "FoodIconVegan": "vegan",
    "FoodIconWheat": "wheat",
    "FoodIconWine": "wine",
    "FoodIconWrap": "sandwich",
}


def normalize_lucide_svg(raw: str) -> str:
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


def main() -> int:
    repo = Path("/tmp/lucide-icons")
    if not (repo / "icons").is_dir():
        print("Cloning lucide-icons/lucide into /tmp/lucide-icons …", file=sys.stderr)
        subprocess.run(
            ["git", "clone", "--depth", "1", "https://github.com/lucide-icons/lucide.git", str(repo)],
            check=True,
        )

    root = Path(__file__).resolve().parents[1]
    assets = root / "Calorie Tracker" / "Assets.xcassets"

    for food_name, lucide_name in sorted(LUCIDE_BY_FOOD_ICON.items()):
        src = repo / "icons" / f"{lucide_name}.svg"
        if not src.is_file():
            print(f"missing lucide icon: {lucide_name}.svg for {food_name}", file=sys.stderr)
            return 1
        dst_dir = assets / f"{food_name}.imageset"
        dst = dst_dir / f"{food_name}.svg"
        if not dst_dir.is_dir():
            print(f"missing imageset: {dst_dir}", file=sys.stderr)
            return 1
        normalized = normalize_lucide_svg(src.read_text())
        dst.write_text(normalized)
        print(f"wrote {dst.relative_to(root)}")

    print("done", len(LUCIDE_BY_FOOD_ICON), "icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
