#!/usr/bin/env python3
"""expand_v6.py — fix turkey & gravy → fish misclassification + broad coverage improvements.

Root cause:
  "turkey & gravy" normalizes to "turkey and gravy" before hitting the model.
  FoodIconDrumstick had only ~59 examples with ZERO roasted/whole-turkey dinner
  entries, while FoodIconFish had 161. The model had nothing to anchor
  turkey-dinner phrases to Drumstick, so Fish won by weight.

Fixes:
  1. Add "turkey and gravy" + full roasted/whole-turkey dinner vocabulary → Drumstick
  2. Bulk up FoodIconDrumstick (59 → ~170+) with turkey leg / holiday bird / carving variants
  3. Expand FoodIconFish with specific fish species and preparation styles
  4. Add clearly-unrelated examples that share words with fish (boundary reinforcement)
"""

import csv, pathlib, random

ROOT     = pathlib.Path(__file__).parent
TRAIN_IN = ROOT / "training_data.csv"
VAL_IN   = ROOT / "validation_data.csv"

random.seed(206)


def load(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows.append({"text": r["text"], "label": r["label"]})
    return rows


def save(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["text", "label"])
        w.writeheader()
        w.writerows(rows)


train_rows = load(TRAIN_IN)
val_rows   = load(VAL_IN)

ADDITIONS = []


def add(label, *texts):
    for t in texts:
        ADDITIONS.append({"text": t.strip(), "label": label})


# ─── 1. DRUMSTICK — THE PRIMARY FIX: roasted/whole turkey + turkey dinner ────
#
#  "turkey & gravy" normalizes to "turkey and gravy" — that's the exact form
#  the model sees.  Add it explicitly plus every plausible cafeteria/Thanksgiving
#  turkey-dinner phrase so the class has strong coverage.

add("FoodIconDrumstick",
    # ── The direct fix (normalized form of "turkey & gravy") ──
    "turkey and gravy",
    "turkey with gravy",
    "turkey and gravy station",
    "turkey with brown gravy",
    "turkey and pan gravy",
    "roasted turkey and gravy",
    "sliced turkey and gravy",
    "carved turkey and gravy",
    "turkey dinner with gravy",
    "turkey plate with gravy",
    "turkey entree with gravy",

    # ── Roasted / whole turkey ──
    "roasted turkey",
    "oven roasted turkey",
    "whole roasted turkey",
    "whole turkey",
    "carved turkey",
    "carve turkey",
    "sliced turkey",
    "sliced roasted turkey",
    "thanksgiving turkey",
    "holiday turkey",
    "festive turkey",
    "traditional roast turkey",
    "roast turkey",
    "roast turkey dinner",
    "roast turkey plate",
    "turkey dinner",
    "turkey entree",
    "turkey plate",
    "turkey station",
    "turkey carving station",
    "carved turkey station",
    "turkey carving line",
    "holiday bird",
    "roast bird",
    "herb roasted turkey",
    "garlic herb turkey",
    "garlic herb roasted turkey",
    "brined turkey",
    "smoked whole turkey",
    "maple glazed turkey",
    "maple turkey",
    "citrus roasted turkey",
    "citrus herb turkey",
    "stuffed turkey",
    "stuffed whole turkey",
    "roast turkey with stuffing",
    "turkey with stuffing and gravy",
    "turkey and dressing",
    "turkey and stuffing",
    "oven turkey",
    "golden turkey",
    "slow roasted turkey",
    "slow cooked turkey",
    "spatchcock turkey",
    "spatchcocked turkey",
    "rotisserie turkey",
    "bone in turkey breast",
    "roasted turkey breast",
    "oven roasted turkey breast",
    "herb crusted turkey breast",
    "roasted bone in turkey breast",

    # ── Turkey leg / thigh / quarter (extend existing set) ──
    "turkey leg",
    "turkey legs",
    "smoked turkey leg",
    "roasted turkey leg",
    "glazed turkey leg",
    "honey glazed turkey leg",
    "bbq turkey leg",
    "candied turkey leg",
    "fairground turkey leg",
    "giant turkey leg",
    "fair turkey leg",
    "renaissance turkey leg",
    "seasoned turkey leg",
    "savory turkey leg",
    "slow roasted turkey leg",
    "turkey leg station",
    "turkey drumstick",
    "turkey drumsticks",
    "smoked turkey drumstick",
    "roasted turkey drumstick",
    "turkey thigh",
    "turkey thighs",
    "roasted turkey thigh",
    "smoked turkey thigh",
    "braised turkey thigh",
    "turkey quarter",
    "turkey leg quarter",
    "turkey dark meat",
    "turkey white meat",
    "turkey wing",
    "turkey wings",
    "smoked turkey wing",
    "roasted turkey wing",
    "turkey bone in",

    # ── Other poultry legs / drumsticks (reinforce class breadth) ──
    "duck leg",
    "duck confit",
    "duck leg confit",
    "roasted duck leg",
    "glazed duck leg",
    "crispy duck leg",
    "quail leg",
    "roasted quail",
    "cornish hen",
    "roasted cornish hen",
    "game hen",
    "roasted game hen",
    "pheasant leg",
    "roasted pheasant",
    "guinea hen leg",
)

# ─── 2. FISH — diverse species + preparations (related examples) ───────────────

add("FoodIconFish",
    # ── Cod family ──
    "cod",
    "cod fillet",
    "atlantic cod",
    "pacific cod",
    "baked cod",
    "grilled cod",
    "blackened cod",
    "pan seared cod",
    "lemon cod",
    "garlic cod",
    "cod and chips",
    "battered cod",
    "poached cod",
    "butter basted cod",
    "herb crusted cod",
    "panko cod",

    # ── Salmon ──
    "salmon",
    "salmon fillet",
    "atlantic salmon",
    "sockeye salmon",
    "king salmon",
    "chinook salmon",
    "coho salmon",
    "pink salmon",
    "chum salmon",
    "baked salmon",
    "grilled salmon",
    "pan seared salmon",
    "poached salmon",
    "honey glazed salmon",
    "teriyaki salmon",
    "citrus salmon",
    "cedar plank salmon",
    "blackened salmon",
    "lemon dill salmon",
    "maple glazed salmon",
    "salmon with lemon",
    "herb salmon",

    # ── Trout ──
    "rainbow trout",
    "steelhead trout",
    "lake trout",
    "brown trout",
    "brook trout fillet",
    "pan fried trout",
    "grilled trout",
    "baked trout",
    "almondine trout",
    "trout meuniere",

    # ── Freshwater fish ──
    "walleye",
    "walleye fillet",
    "pan fried walleye",
    "grilled walleye",
    "baked walleye",
    "perch",
    "perch fillet",
    "lake perch",
    "fried perch",
    "yellow perch",
    "catfish",
    "catfish fillet",
    "fried catfish",
    "southern fried catfish",
    "blackened catfish",
    "grilled catfish",
    "bluegill",
    "fried bluegill",
    "crappie fillet",
    "bass fillet",
    "largemouth bass fillet",

    # ── Flatfish ──
    "flounder",
    "flounder fillet",
    "baked flounder",
    "stuffed flounder",
    "sole",
    "sole fillet",
    "dover sole",
    "lemon sole",
    "petrale sole",
    "flatfish",

    # ── Grouper / snapper / bass ──
    "grouper",
    "grouper fillet",
    "grilled grouper",
    "blackened grouper",
    "red snapper fillet",
    "snapper fillet",
    "pan seared snapper",
    "sea bass",
    "sea bass fillet",
    "chilean sea bass",
    "black sea bass",
    "striped bass fillet",
    "branzino",
    "branzino fillet",
    "whole branzino",
    "grilled branzino",

    # ── Tropical / specialty fish ──
    "barramundi",
    "barramundi fillet",
    "arctic char",
    "arctic char fillet",
    "sablefish",
    "black cod sablefish",
    "butterfish",
    "pompano",
    "pompano fillet",
    "wahoo steak",
    "wahoo",
    "amberjack",
    "cobia",

    # ── Tuna ──
    "tuna steak",
    "ahi tuna",
    "ahi tuna steak",
    "seared ahi tuna",
    "seared tuna",
    "bluefin tuna steak",
    "bigeye tuna",
    "grilled tuna steak",
    "pan seared tuna",
    "tuna loin",

    # ── Herring / sardine family ──
    "sardines",
    "fresh sardines",
    "grilled sardines",
    "herring fillet",
    "pickled herring",
    "rollmop herring",
    "smelt",
    "fried smelt",
    "lake smelt",

    # ── Preparations ──
    "fish and chips",
    "beer battered fish",
    "battered fish and chips",
    "fish platter",
    "fish plate",
    "pan fried fish",
    "whole fish",
    "whole grilled fish",
    "blackened fish",
    "ceviche",
    "fish ceviche",
    "lemon fish",
    "herb crusted fish",
    "crispy fish",
    "baked white fish",
    "white fish",
    "whitefish",
    "whitefish fillet",
    "grilled white fish",

    # ── Station names (reinforce existing) ──
    "seafood entree station",
    "fish of the week",
    "fresh fish station",
    "fish bar",
    "fish fry",
    "friday fish fry",
    "lenten fish",
    "fish special",
    "fish feature",
)

# ─── 3. UNRELATED BOUNDARY EXAMPLES ──────────────────────────────────────────
#
#  Words that appear in some fish names but belong to other classes.
#  These prevent the model from pattern-matching on partial token overlap.

add("FoodIconCookingPot",
    # "bass" in non-fish context
    "bass ale",         # beer, not fish
    # General turkey dishes that aren't the roasted bird icon
    "turkey chili con carne",
    "turkey bolognese",
    "ground turkey pasta",
    "ground turkey sauce",
    "turkey meatball",
    "turkey meatballs",
    "turkey meatloaf",
    "turkey stuffed pepper",
    "turkey stuffed peppers",
    "turkey and rice casserole",
    "ground turkey stew",
    "leftover turkey soup",
    "turkey carcass soup",
    "turkey noodle soup",
    "turkey vegetable soup",
    "turkey bean soup",
    "turkey lentil soup",
    "turkey white bean soup",
    "turkey rice soup",
    "day after turkey soup",
)

add("FoodIconHam",
    # Deli turkey — reinforce existing Ham mapping for sliced/processed turkey
    "turkey breast deli sliced",
    "thin sliced turkey",
    "oven roasted deli turkey",
    "smoked deli turkey",
    "honey roasted deli turkey",
    "carved deli turkey",
    "turkey cold cut",
    "turkey cold cuts",
    "turkey lunchmeat",
    "sliced turkey deli meat",
    "pre sliced turkey",
    "turkey sub meat",
    "turkey sandwich meat",
)

add("FoodIconSandwich",
    # Turkey in sandwich context
    "turkey avocado sandwich",
    "turkey club",
    "turkey club sandwich",
    "turkey blt",
    "turkey and cheese sandwich",
    "open faced turkey sandwich",
    "sliced turkey sandwich",
    "turkey sub",
    "turkey hoagie",
    "turkey grinder",
    "turkey panini",
    "turkey wrap sandwich",
    "hot turkey sandwich",
    "turkey melt",
)

add("FoodIconSoup",
    # "catch" in non-fish soup contexts (prevent confusion)
    "clam chowder new england",
    "fish chowder",        # soup not standalone fish
    "cioppino",
    "bouillabaisse",
    "seafood bisque",
    "lobster bisque",
    "shrimp bisque",
    "crab bisque",
    "seafood chowder",
    "fish stew",
    "portuguese fish stew",
)

# ─────────────────────────────────────────────────────────────────────────────

random.shuffle(ADDITIONS)
split   = int(len(ADDITIONS) * 0.9)
new_train = ADDITIONS[:split]
new_val   = ADDITIONS[split:]

train_rows.extend(new_train)
val_rows.extend(new_val)

random.shuffle(train_rows)
random.shuffle(val_rows)

save(TRAIN_IN, train_rows)
save(VAL_IN,   val_rows)

from collections import Counter
counts_train = Counter(r["label"] for r in train_rows)

print(f"Total examples : {len(train_rows)+len(val_rows)}")
print(f"Training rows  : {len(train_rows)}")
print(f"Validation rows: {len(val_rows)}")
print(f"New examples   : {len(ADDITIONS)} (+{split} train, +{len(new_val)} val)")
print(f"\nModified classes:")
for k in sorted(set(r["label"] for r in ADDITIONS)):
    print(f"  {k:<45} {counts_train[k]}")
print(f"\nSmallest 10 (post-expansion):")
for k, v in sorted(counts_train.items(), key=lambda x: x[1])[:10]:
    print(f"  {k:<45} {v}")
