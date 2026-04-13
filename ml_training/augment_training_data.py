#!/usr/bin/env python3
"""
Augments the existing training examples and writes expanded training/validation CSVs.
Run: python3 ml_training/augment_training_data.py
"""
import csv, random, os

random.seed(99)

# ── Extra examples appended to the smallest/weakest classes ──────────────────

extra: dict[str, list[str]] = {

    "FoodIconCandyCane": [
        "holiday peppermint stick","christmas peppermint","red and white candy cane",
        "striped peppermint cane","cane shaped candy","peppermint stripe candy",
        "candy cane cookie","candy cane bark","candy cane pieces","crushed candy cane",
        "candy cane milkshake","candy cane hot cocoa","peppermint cane treat",
        "classic candy cane","traditional candy cane","old fashioned candy cane",
        "cane sugar candy","handmade candy cane","organic candy cane",
        "giant candy cane","mini candy cane pack","candy cane hershey kiss",
        "candy cane oreo","candy cane trail mix","peppermint bark pieces",
        "candy cane smoothie","candy cane shake","candy cane protein",
        "candy cane yogurt","peppermint holiday candy","seasonal peppermint",
        "christmas candy cane","holiday candy stick","seasonal striped candy",
    ],

    "FoodIconRefrigerator": [
        "refrigerator items","fridge contents","cold storage food","chilled item",
        "refrigerated","from the fridge","stored in fridge","fridge meal",
        "leftover refrigerated","pre-made refrigerated","ready made from fridge",
        "meal prepped fridge","batch cooked fridge","fridge snack","fridge lunch",
        "refrigerated snack","cold food from fridge","fridge yogurt","fridge fruit",
        "refrigerated yogurt","cold leftovers","overnight leftovers","fridge leftovers",
        "next day leftovers","leftover dinner","leftover lunch","leftover breakfast",
        "reheated leftovers","fridge staple","cold cut from fridge",
        "refrigerated meal prep","pre-portioned fridge meal","cold prep container",
    ],

    "FoodIconUtensilsCrossed": [
        "restaurant meal","dining out","eat out","eating out","restaurant food",
        "restaurant dish","restaurant plate","diner food","bistro meal",
        "cafe meal","table service","fine dining meal","casual dining food",
        "sit down restaurant","full service dining","plated restaurant dish",
        "restaurant entree","restaurant main course","restaurant order",
        "food service meal","professional kitchen meal","chef prepared restaurant",
        "restaurant takeout","restaurant delivery","doordash order","ubereats order",
        "grubhub order","restaurant portion","restaurant size","dine in",
        "eat in restaurant","restaurant special","prix fixe","tasting menu",
        "omakase restaurant","restaurant buffet","all you can eat",
    ],

    "FoodIconCherry": [
        "fresh cherry","fresh cherries","whole cherries","ripe cherries",
        "dark sweet cherries","rainier cherries","bing cherries","black cherries",
        "frozen cherries","canned cherries","cherry in syrup","cherry topping",
        "cherry compote","cherry sauce","cherry jam","cherry preserve",
        "cherry pie filling","cherry gelatin","cherry flavored","maraschino cherries",
        "cocktail cherries","luxardo cherry","cherry garnish","cherry fruit salad",
        "cherry smoothie","cherry juice","tart cherry juice","sour cherry drink",
        "dried tart cherries","dried sweet cherries","cherry trail mix",
        "chocolate covered cherries","cherry chocolate","cherry almond",
        "cherry vanilla","cherry limeade","shirley temple cherry",
    ],

    "FoodIconIceCreamSandwich": [
        "ice cream sandwich cookie","homemade ice cream sandwich","store bought ice cream sandwich",
        "giant ice cream sandwich","mini ice cream sandwich","birthday ice cream sandwich",
        "chocolate chip ice cream sandwich","oatmeal ice cream sandwich",
        "snickerdoodle ice cream sandwich","wafer ice cream sandwich",
        "brownie ice cream sandwich bar","caramel ice cream sandwich",
        "strawberry ice cream sandwich","mint chip ice cream sandwich",
        "cookie sandwich ice cream","sandwich ice cream bar","ice cream cookie bar",
        "frozen cookie sandwich","it's it","mochi sandwich","waffle sandwich ice cream",
        "klondike sandwich","drumstick sandwich style","giant chipwich",
        "vanilla bean ice cream sandwich","double chocolate ice cream sandwich",
        "neapolitan ice cream sandwich","cookies and cream ice cream sandwich",
    ],

    "FoodIconSnail": [
        "escargot appetizer","escargot with garlic butter","classic french escargot",
        "baked escargot shell","escargot in shell","land snails cooked",
        "escargot bourguignon","escargot de bourgogne garlic","snail dish french",
        "garlicky escargot","herbed escargot","escargot parsley butter",
        "snail caviar","petit gris snail","burgundy snail","helix pomatia",
        "canned escargot","prepared escargot","escargot mushroom","escargot toast",
        "sea snail","periwinkle seafood","steamed periwinkle","boiled whelk",
        "abalone dish","conch meal","conch fritter","conch salad",
        "conch chowder","queen conch","whelk snail","cooked whelk",
    ],

    "FoodIconShoppingBasket": [
        "grocery list food","market items food","supermarket food",
        "food haul","weekly food haul","meal planning food","bulk grocery",
        "warehouse club food","costco food","sams club food","bj's food",
        "farmers market food","fresh market food","whole foods grocery",
        "trader joes groceries","aldi groceries","kroger groceries",
        "safeway groceries","publix groceries","sprouts groceries",
        "grocery pickup food","grocery delivery food","instacart food",
        "pantry restock","pantry staples food","food storage item",
        "meal prep ingredients","cooking ingredients","recipe ingredients",
        "miscellaneous food","mixed food items","assorted groceries",
        "variety pack food","food bundle","food package","food kit",
    ],

    "FoodIconBottleWine": [
        "750ml wine bottle","standard wine bottle","magnum wine bottle",
        "half bottle of wine","split wine bottle","wine bottle opener",
        "cork wine bottle","screwcap wine bottle","wine label bottle",
        "red blend bottle","white blend bottle","rosé bottle","pink wine bottle",
        "natural wine bottle","biodynamic wine bottle","organic wine bottle",
        "bottle of malbec","bottle of tempranillo","bottle of sangiovese",
        "bottle of pinot blanc","bottle of gewurztraminer","bottle of viognier",
        "bottle of gruner","grüner veltliner bottle","bottle of riesling",
        "bottle of moscato","bottle of prosecco","bottle of cava",
        "champagne bottle 750ml","sparkling wine bottle full","bubbly bottle",
        "dessert wine bottle","port wine bottle","sherry bottle","madeira bottle",
        "full bottle of wine","sealed wine bottle","wine to share",
    ],

    "FoodIconEggFried": [
        "egg over easy","egg sunny side","fried egg plate","pan egg",
        "skillet fried egg","butter fried egg","olive oil egg","crispy egg white",
        "runny yolk egg","broken yolk egg","over medium cooked","well done egg",
        "basted egg dish","steam basted egg","egg on toast fried","egg avocado toast",
        "breakfast fried egg","diner fried egg","greasy spoon egg",
        "cast iron egg","stainless pan egg","nonstick egg","fried egg burger",
        "fried egg sandwich","fried egg ramen","fried egg rice","fried egg bibimbap",
        "korean fried egg","spanish fried egg spicy","shakshuka style egg",
        "egg in tomato sauce","purgatory egg","middle eastern baked egg",
        "green egg no ham","cloud egg baked","pinterest egg",
    ],

    "FoodIconCakeSlice": [
        "birthday cake slice","chocolate cake piece","vanilla slice cake",
        "red velvet piece","carrot cake wedge","lemon drizzle slice",
        "coffee cake slice piece","funfetti cake wedge","marble cake slice",
        "german chocolate piece","black forest slice","tiramisu piece",
        "tres leches wedge","cheesecake wedge","cheesecake triangle",
        "key lime pie slice","pumpkin pie slice","apple pie slice",
        "pecan pie slice","lemon meringue slice","coconut cream slice",
        "chocolate cream pie slice","banana cream pie piece",
        "opera cake slice","baked alaska slice","pavlova slice",
        "chiffon cake slice","angel food cake piece","pound cake slice",
        "single slice cake","one slice birthday","dessert slice",
        "cake wedge","piece of layer cake","a slice of cake",
    ],

    "FoodIconLollipop": [
        "classic round lollipop","swirl lollipop pop","fruit flavored pop",
        "tootsie pop grape","tootsie pop cherry","blow pop watermelon",
        "charms blow pop strawberry","chupa chups cola","dum dum mystery",
        "flat round pop","disc lollipop","pancake lollipop","heart lollipop",
        "star lollipop","flower lollipop","holiday lollipop",
        "jumbo lollipop large","giant novelty pop","photobooth lollipop",
        "rainbow lollipop","tie dye lollipop","swirling lollipop",
        "chocolate dipped lollipop","caramel lollipop","gummy lollipop",
        "sour lollipop","ultra sour pop","warhead pop","extreme sour lollipop",
        "sugar free lollipop","organic lollipop","artisan lollipop",
        "rock candy stick","rock candy lollipop","sugar crystal lollipop",
    ],

    "FoodIconChefHat": [
        "chef special today","daily chef feature","kitchen daily special",
        "line cook special","head chef creation","executive chef dish",
        "chef's tasting","chef's table menu","from the kitchen","kitchen choice",
        "house feature","seasonal feature","market menu","farm to table special",
        "prix fixe choice","tasting menu item","degustation course",
        "specials board item","chalkboard special","today's creation",
        "chef curated","seasonal rotation","limited offering","exclusive dish",
        "new item this week","try something new","kitchen experiment",
        "scratch made dish","from scratch daily","batch cooked special",
        "slow fermented","long braise special","house cured","house smoked",
    ],

    "FoodIconUtensils": [
        "generic food","food item","meal item","food entry","calorie entry",
        "log food","add food","track food","food serving","plate of food",
        "portion of food","something to eat","a meal","a dish","a food",
        "something I ate","what I had","my meal","my food","my plate",
        "unspecified food","unknown food","miscellaneous meal","other food",
        "various food","mixed meal","combination meal","random meal",
        "leftovers mixed","assorted food","food and drink","eat","eating",
        "snack","a snack","quick snack","bite to eat","small bite",
    ],

    "FoodIconDrumstick": [
        "chicken leg quarter roasted","bone in chicken leg oven",
        "bbq chicken drumstick grilled","smoked chicken leg bbq",
        "crispy chicken leg air fryer","garlic herb roasted leg",
        "honey mustard chicken leg","spicy sriracha drumstick",
        "buffalo style chicken leg","lemon pepper chicken leg",
        "paprika drumstick","cajun chicken drumstick","teriyaki chicken leg",
        "korean gochujang drumstick","jerk spiced chicken leg",
        "turmeric chicken drumstick","curry chicken leg",
        "five spice chicken drumstick","hoisin glazed leg",
        "balsamic glazed drumstick","maple glazed chicken leg",
        "brown sugar chicken leg","chipotle chicken drumstick",
        "ranch seasoned drumstick","italian seasoned chicken leg",
        "mediterranean chicken leg","herbes de provence drumstick",
        "za'atar chicken leg","sumac chicken drumstick","harissa leg",
        "peri peri chicken leg","portuguese chicken leg piece",
    ],

    "FoodIconBeef": [
        "dry aged ribeye","wet aged strip","grass fed sirloin","grain finished filet",
        "USDA prime steak","USDA choice beef","wagyu beef steak grade a5",
        "kobe beef steak","snake river farms beef","omaha steaks beef",
        "new york strip cooked","porterhouse for two","bone in ribeye cowboy",
        "tomahawk ribeye huge","flat iron quick sear","denver steak",
        "picanha sirloin cap","bavette steak","coulotte steak","tri tip roast",
        "smoked beef brisket flat","burnt ends brisket","texas bbq brisket",
        "corned beef dinner","ropa vieja shredded","machaca dried beef",
        "beef gyudon bowl steak","korean bulgogi plate","vietnamese bo luc lac",
        "taiwanese beef noodle steak","japanese sukiyaki beef",
        "beef shabu thin sliced","beef hot pot","mongolian beef stir",
        "beef stroganoff sauce","hungarian beef paprikash","beef goulash bowl",
        "carne asada grilled","arrachera fajita beef","suadero tacos beef",
    ],

    "FoodIconCroissant": [
        "fresh baked croissant","warm croissant morning","artisan croissant bakery",
        "laminated dough croissant","layers croissant flaky","crescent shape pastry",
        "croissant sandwich lunch","croissant breakfast sandwich",
        "egg croissant sandwich","ham brie croissant","turkey croissant",
        "caprese croissant","prosciutto croissant roll","smoked salmon croissant",
        "avocado croissant toast","brie honey croissant","fig jam croissant",
        "nutella croissant stuffed","almond frangipane croissant",
        "pain au chocolat dark","pain au chocolat milk","double chocolate croissant",
        "kouign amann caramelized","morning bun cinnamon orange","cruffin pastry",
        "laminated pastry","viennoiserie pastry","french viennoiserie",
        "danish pastry laminated","rough puff pastry","puff pastry layer",
        "croissant dough baked","bakery fresh croissant","patisserie croissant",
    ],

    "FoodIconDessert": [
        "soft serve twist vanilla chocolate","rainbow soft serve","rainbow swirl",
        "strawberry soft serve cone","mango soft serve","matcha soft serve",
        "ube soft serve","black sesame soft serve","hojicha soft serve",
        "dole whip pineapple","dole whip stand","theme park soft serve",
        "blizzard dairy queen large","blizzard dq small","mcdonald's mcflurry",
        "sonic blast ice cream","culver's concrete mixer thick",
        "freddy's custard","andy's custard","leon's custard","kopp's custard",
        "shake shack shake cup","steak n shake shake","portillo's shake",
        "five guys milkshake","in n out shake","whataburger shake",
        "soft serve station buffet","self serve ice cream","swirl machine",
        "overrun ice cream machine","restaurant soft serve","diner soft serve",
        "hotel soft serve machine","all inclusive soft serve","cruise ship dessert",
    ],

    "FoodIconPopcorn": [
        "movie theater popcorn tub","large popcorn bucket cinema",
        "small bag popcorn snack","individual popcorn serving","popcorn for one",
        "shareable popcorn bag","party size popcorn","family pack popcorn",
        "caramelized popcorn gourmet","chicago mix cheese caramel",
        "white cheddar popcorn snack bag","aged parmesan popcorn",
        "ranch popcorn seasoned","buffalo ranch popcorn","dill pickle popcorn",
        "old bay popcorn seasoned","everything bagel popcorn seasoning",
        "sriracha lime popcorn","jalapeño cheddar popcorn","ghost pepper popcorn",
        "truffle butter popcorn gourmet","truffle salt popcorn",
        "coconut oil popcorn","avocado oil popcorn","ghee popcorn",
        "organic white popcorn","yellow hull popcorn","mushroom popcorn kernel",
        "hull-less popcorn","tender pop popcorn","ladyfinger popcorn",
        "microwave kettle corn bag","microwave movie theater butter",
        "ready to eat popcorn bag","popcorn tin holiday",
    ],

    "FoodIconIceCreamBowl": [
        "double scoop ice cream dish","triple scoop sundae bowl",
        "banana split dish classic","banana split boat",
        "hot fudge sundae whipped cream","caramel drizzle sundae",
        "strawberry shortcake sundae","peach melba sundae","pear belle helene",
        "brownie hot fudge sundae","cookie sundae ice cream bowl",
        "waffle bowl ice cream","pretzel bowl ice cream","churro bowl ice cream",
        "acai bowl topped","smoothie bowl fruit topped","dragon bowl pitaya",
        "frozen yogurt cup toppings","froyo bowl granola","froyo toppings bar cup",
        "pinkberry froyo cup","menchie's froyo bowl","yogurtland cup",
        "tcby frozen yogurt cup","orange leaf cup","red mango cup",
        "kiwi yogurt bowl","sweetfrog cup","tutti frutti cup",
        "ice cream shop scoop cup","gelateria cup gelato","parlor scoop cup",
        "baskin robbins scoop","31 flavors cup","haagen dazs scoop cup",
        "ben jerrys scoop cup","jeni's scoop bowl","salt straw scoop",
    ],
}

# ── Load existing training data ───────────────────────────────────────────────
def load_csv(path: str) -> list[tuple[str, str]]:
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append((row["text"], row["label"]))
    return rows

base_dir = os.path.dirname(__file__)
train_path = os.path.join(base_dir, "training_data.csv")
val_path   = os.path.join(base_dir, "validation_data.csv")

existing = load_csv(train_path) + load_csv(val_path)

# ── Merge originals + extras ──────────────────────────────────────────────────
all_rows: list[tuple[str, str]] = list(existing)
for label, examples in extra.items():
    for text in examples:
        all_rows.append((text.strip(), label))

random.shuffle(all_rows)

split = int(len(all_rows) * 0.85)
train_rows = all_rows[:split]
val_rows   = all_rows[split:]

def write_csv(path: str, rows: list[tuple[str, str]]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["text", "label"])
        writer.writerows(rows)

write_csv(train_path, train_rows)
write_csv(val_path,   val_rows)

# ── Stats ─────────────────────────────────────────────────────────────────────
from collections import Counter
label_counts: Counter = Counter()
for _, label in all_rows:
    label_counts[label] += 1

print(f"Total examples : {len(all_rows)}")
print(f"Training rows  : {len(train_rows)}")
print(f"Validation rows: {len(val_rows)}")
print(f"\nSmallest classes:")
for label, count in sorted(label_counts.items(), key=lambda x: x[1])[:15]:
    print(f"  {label:35s} {count:4d}")
print(f"\nLargest classes:")
for label, count in sorted(label_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
    print(f"  {label:35s} {count:4d}")
