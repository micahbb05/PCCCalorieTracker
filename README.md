Calorie Tracker (iOS) – PCC Dining + AI Food Logging
=======================================================

This project is an iOS calorie‑tracking app with tight integration to Pensacola Christian College (PCC) dining menus, barcode and USDA search, Apple Health, and AI photo features backed by Firebase Functions and Google Gemini.

This README summarizes how the codebase is structured, how the major features work, and how to run and deploy it.

High‑level architecture
-----------------------

- **Client app**: Native SwiftUI iOS app in the `Calorie Tracker` Xcode project.
  - Tracks meals, exercises, goals, and history entirely on‑device using `UserDefaults` archives.
  - Pulls PCC menus from Nutrislice, and supports barcode scanning and USDA food search.
  - Supports:
    - Plate photos for selected menu items (Gemini portion estimation).
    - General food photos and nutrition label photos (Gemini structured food/nutrient extraction).
- **Backend**: Firebase Functions in `functions/`.
  - Proxy for USDA FoodData Central search.
  - Plate portion estimation endpoint (`estimatePlatePortions`) that calls Gemini 2.5 with the plate photo and menu context and returns structured JSON.
- **Hosting**: Static marketing site and privacy policy in `public/`, deployed via Firebase Hosting.

Key iOS app components
----------------------

### 1. `ContentView.swift`

This is the main container for the app. It owns almost all application state and orchestrates persistence, day transitions, and navigation.

- **State and storage**
  - Uses `@AppStorage` for user‑level settings and archives:
    - Goals and nutrient tracking preferences.
    - Per‑day archives:
      - `dailyEntryArchiveData` – `MealEntry` objects keyed by `"YYYY-MM-DD"` (central‑time day identifier).
      - `dailyCalorieGoalArchiveData`, `dailyBurnedCalorieArchiveData`, `dailyExerciseArchiveData`, `dailyGoalTypeArchiveData`.
    - `useAIBaseServings` – whether Gemini is allowed to refine ambiguous base servings (e.g. `"1 each"` entrees).
  - Uses `@State` for in‑memory working sets:
    - `entries`, `exercises` for the currently selected day.
    - `dailyEntryArchive` and related dictionaries for all days.
    - Menu state, onboarding, and UI flags (sheet presentation, keyboard state, etc.).

- **Day management**
  - `todayDayIdentifier`: builds a `"YYYY-MM-DD"` string based on the app’s calendar (central-ish time).
  - `applyCentralTimeTransitions(forceMenuReload:)`:
    - Detects when the current central‑time day has changed.
    - On first run, seeds archives for the current day.
    - When the day changes:
      - Archives the previous day’s `entries` and `exercises` under `lastCentralDayIdentifier`, but **guards against overwriting a non‑empty archive with empty arrays on cold start**.
      - Loads the new day’s entries and exercises from the archives.
      - Resets menu selections and optionally reloads menus.
    - Always keeps archives in sync via `saveDailyEntryArchive()` and related save helpers.

- **Persistence helpers**
  - `loadDailyEntryArchive()` / `saveDailyEntryArchive()` – round trip `dailyEntryArchive` to `storedDailyEntryArchiveData` (JSON).
  - Similar helpers exist for calorie goals, burned calories, exercises, and goal type.
  - `syncCurrentEntriesToArchive()` is called whenever `entries` or `exercises` change to keep today’s data in the per‑day archive and history views in sync.

- **Health and activity**
  - Owns `StepActivityService` and `HealthKitService`.
  - Uses:
    - Apple Health for sex, age (DOB), height, weight, today’s workouts, and body-mass history for weekly calibration.
    - Motion & Fitness for step count + distance.
  - Computes daily burned calories as:
    - `BMR + effective step activity + exercise calories (+ optional weekly calibration offset)`.
  - Running overlap is explicitly de-duplicated:
    - Running contributes full run calories.
    - A walking-equivalent portion is reclassified from step calories to avoid counting both “run” and “steps” for the same distance.

- **Menus and history**
  - Uses `NutrisliceMenuService` to fetch PCC menus:
    - `currentMenuType` (breakfast / lunch / dinner).
    - `currentCentralDayIdentifier` for date scoping.
  - Caches menus per venue in `venueMenus` and persists them to `UserDefaults` for faster startup.
  - Handles today vs. history selection, including month views and chart ranges.

- **Plate photo workflow**
  - Holds:
    - `plateEstimateItems: [MenuItem]?` – items being estimated.
    - `plateEstimateOzByItemId: [String: Double]` – current oz or counts per item ID.
    - `plateEstimateBaseOzByItemId: [String: Double]` – base serving in oz per item ID (from menu or Gemini, depending on settings).
  - `handlePhotoPlate(items:imageData:)`:
    - Calls `GeminiPlateEstimateService.estimatePortions`.
    - Maps `ozByName` and `countByName` back onto menu item IDs.
    - Applies `baseOzByName` only when:
      - `useAIBaseServings` is `true`, and
      - The serving unit is ambiguous (`"each"`, `"serving"`, `"item"`, etc.).
    - Populates `plateEstimateItems`, `plateEstimateOzByItemId`, and `plateEstimateBaseOzByItemId`.
    - Shows `PlateEstimateResultView` full‑screen.
  - `addMenuItemsWithPortions(_:)`:
    - Takes `(MenuItem, oz, baseOz)` tuples from the adjust screen.
    - Computes a multiplier (oz / baseOz for oz‑based items or quantity for count‑based).
    - Scales calories and nutrients accordingly and appends to `entries`.

### 2. `MenuSheetView.swift`

Presents a sheet for a given PCC venue’s menu:

- Shows meal lines and items with quantity/multiplier controls.
- Exposes:
  - `onAddSelected` to add all selected items to today’s log.
  - `onPhotoPlate` to trigger the plate photo flow.
- **AI portion estimation entrypoint**:
  - Bottom CTA row has:
    - An **AI plate photo button** (sparkles icon) when:
      - `onPhotoPlate` is non‑nil.
      - `venue != .grabNGo` (Grab N Go does not offer plate photos).
    - An “Add Selected” button.
  - Tapping the AI button:
    - Requires `selectedCount > 0`.
    - Presents a confirmation dialog titled **“AI portion estimation”** with options:
      - “Use camera”
      - “Choose from library”
    - Uses `PlateImagePickerView` to capture or choose the plate image, then calls `onPhotoPlate(items, data)`.

### 3. `PlateEstimateResultView.swift`

Full‑screen adjust UI for the plate estimates:

- Props:
  - `items: [MenuItem]`
  - `ozByItemId: Binding<[String: Double]>`
  - `baseOzByItemId: [String: Double]`
  - `mealGroup` and callbacks for confirm/dismiss.
- Captures the original Gemini estimates (`geminiOzByItemId`) on first appear so slider math is stable.
- Layout:
  - Top bar with **Cancel** and **Add to log** (enabled only when some item has `oz > 0`).
  - Heading: **“Adjust portion size”**.
  - Scrollable content:
    - **Warning pill**:
      - Icon + text: “AI portions are estimates — please double‑check before logging.”
      - Same horizontal width as the food cards, just above the first item.
    - A card per `MenuItem`:
      - Title, base serving and calories.
      - “Remove from plate” or “Add to plate” controls.
      - Either:
        - Count stepper for `isCountBased` items.
        - Oz slider for continuous portions, using a `PlateAdjustSlider` tied to a −20%…+20% delta relative to `geminiOz`.
      - A “Calories at this portion” summary and a brief nutrient scaling hint.

### 4. `NutrisliceMenuService.swift`

Encapsulates Nutrislice menu fetching and serving logic:

- Defines `DiningVenue` and `MenuItem`/`MenuLine` types.
- `MenuItem`:
  - `isCountBased`: returns `true` for cookies/chips/slices based on unit/name.
  - `servingOzForPortions`:
    - Converts grams, ounces, cups, tablespoons, and teaspoons to oz.
    - For ambiguous units (`"each"`, `"serving"`, `"item"`, etc.), uses `inferredBaseOzFromCalories`:
      - Dense protein ~50 cal/oz.
      - Rice/grains ~35 cal/oz.
      - Sauces/dressings ~25 cal/oz.
- `currentMenuType` and `currentCentralDayIdentifier` give the current meal and date for API calls.
- `fetchTodayMenu(for:)` pulls PCC menus via Nutrislice’s JSON API.

### 5. `PlateImagePickerView.swift`

`UIViewControllerRepresentable` wrapper around `UIImagePickerController`:

- `Source` enum: `.camera` or `.photoLibrary`.
- Presents a system image picker and returns JPEG data via `onPicked`.
- Used exclusively from `MenuSheetView` when the user chooses AI portion estimation.

### 6. `ExerciseCalorieService.swift` and `StepActivityService.swift`

These two services power burn estimation and overlap handling:

- **`StepActivityService`**
  - Estimates walking activity from steps/distance using a net walking baseline of **0.50 kcal/kg/km**.
  - Uses pedometer distance when available; otherwise estimates distance via stride (`0.415 * height`).
- **`ExerciseCalorieService`**
  - Running:
    - Uses distance-based running economy when distance is present (`1.0 kcal/kg/km` net).
    - Falls back to pace/speed-aware MET estimates when distance is unavailable.
  - Cycling:
    - Uses speed-aware MET bins when speed can be inferred; otherwise light-intensity fallback.
  - Running walking-equivalent:
    - Uses **0.50 kcal/kg/km** walking-equivalent calories for overlap removal.
    - Infers running distance from pace+duration when distance is missing.

Key Firebase Functions
----------------------

The Firebase Functions project lives under `functions/` and is written in TypeScript.

### 1. `estimatePlatePortions` (Gemini plate portion estimate)

This Cloud Function accepts:

```json
{
  "imageBase64": "<base64-encoded plate image>",
  "mimeType": "image/jpeg" | "image/png",
  "foodItems": [
    { "name": "...", "calories": 213, "servingAmount": 1, "servingUnit": "each" }
  ]
}
```

and returns:

```json
{
  "ozByFoodName": { "Orange Ginger Chicken": 4.2, "Steamed White Rice": 3.5 },
  "countByFoodName": { "Chocolate Chip Cookie": 2 },
  "baseOzByFoodName": { "Orange Ginger Chicken": 4.3 },
  "rawText": "{ \"items\": [ ... ] }"
}
```

Where:

- `ozByFoodName` – estimated oz on the plate per item name (0 = not on plate).
- `countByFoodName` – integer counts for count‑based items (0 = not on plate).
- `baseOzByFoodName` – oz equivalent of one serving (for ambiguous items).
- `rawText` – the raw JSON/text returned by Gemini (for debugging).

Core pieces:

- **Prompt (`GEMINI_SYSTEM_PROMPT`)**
  - Describes:
    - Plate size: 11" diameter for scale.
    - Items with name, calories per serving, and serving size.
    - Rules for explicit vs. ambiguous units:
      - Explicit units (`oz`, `g`, `cups`, `tbsp`, `tsp`) must be treated as the **base serving** without change.
      - Ambiguous units (`"1 each"`, `"1 serving"`, etc.) should infer base oz from calories and food type.
  - Instructs Gemini to return **only JSON** of the form:

    ```json
    {
      "items": [
        {
          "name": "Steamed White Rice",
          "portionOz": 3.5,
          "portionCount": 0,
          "baseServingOz": 4.0
        }
      ]
    }
    ```

- **Call configuration**

  ```ts
  generationConfig: {
    temperature: 2.0,
    maxOutputTokens: 2048,
    responseMimeType: "application/json"
  }
  ```

  The function actually calls Gemini **twice in parallel** and averages the results.

- **Double‑run averaging**
  - `callGemini()` is invoked twice. For each run:
    - The JSON is parsed via `parsePlateJsonResponse`, which maps back to the original `foodNames`.
  - If either run produced valid JSON:
    - For each food name:
      - Average non‑zero `portionOz` values across runs.
      - Average non‑zero `portionCount` values and round.
      - Average `baseServingOz` when present in both; otherwise take the one non‑nil value.
  - If neither run produced valid JSON:
    - Falls back to the older text parser (line‑based, “Item: 4.0 oz”) and averages oz, counts, and base oz across the two text runs.
    - For ambiguous servings, infers base oz from calories where missing.
    - Never overrides base oz for explicit units (`oz`, `g/grams`, `cups`, `tbsp`, `tsp`); the client uses the menu’s base serving for those.

### 2. `searchUSDAFoods`

Proxy endpoint for USDA FoodData Central search:

- Accepts `?query=` and forwards it to USDA with your API key.
- Maps back USDA results into a shape the app can consume: name, nutrients, serving info, etc.

### 3. `analyzeFoodPhoto`

AI endpoint for general photo logging:

- Accepts an image and classifies it as:
  - `food_photo` (meal/food image), or
  - `nutrition_label` (nutrition facts panel).
- Returns structured JSON with:
  - detected items,
  - calories/protein,
  - normalized nutrient keys when available.
- Uses Gemini 2.5 Flash with low temperature (`0.2`) and JSON-only response format.

Marketing site and privacy policy
---------------------------------

- `public/index.html`
  - Simple static landing page describing:
    - PCC Dining integration.
    - Health‑based goals (Apple Health).
    - AI plate photo estimates and AI food photo logging.
    - Barcode scanning and USDA food search.
  - Links to the App Store listing and the privacy policy.

- `public/privacy.html`
  - Documents:
    - On‑device storage of user data.
    - Health data usage (read‑only from Apple Health).
    - Motion & Fitness (steps).
    - Camera uses:
      - On‑device barcode scanning.
      - Plate photos sent to the backend and Gemini for portion estimation.
    - External services: USDA, Open Food Facts, PCC Nutrislice, Google Gemini.
    - No third‑party analytics or ads; only minimal technical logging for reliability.

Running and deploying
---------------------

### iOS app

1. Open `Calorie Tracker.xcodeproj` in Xcode.
2. Select the `Calorie Tracker` scheme and an iOS Simulator or device.
3. Run the app.

The app uses local `UserDefaults` archives and remote services via HTTPS. To exercise the plate photo feature end‑to‑end, you’ll need:

- A valid `GEMINI_API_KEY` in Firebase Functions configuration.
- Network access from the device/simulator to your deployed functions.

### Firebase Functions

From the `functions/` directory:

```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

Make sure you’ve set the required secrets (e.g. `GEMINI_API_KEY`, `USDA_API_KEY`) in your Firebase project.

### Hosting

From the project root:

```bash
firebase deploy --only hosting
```

This serves `public/index.html` and `public/privacy.html` at your Firebase Hosting URL (e.g. `https://calorie-tracker-364e3.web.app`).

Notes and caveats
-----------------

- **AI accuracy**: The plate photo feature is intentionally labeled as an estimate. The adjust screen displays a warning banner reminding users to double‑check before logging.
- **Energy model**: Burn estimates are model-based (BMR + steps + exercise) and not direct calorimetry. Running/steps overlap is adjusted by subtracting walking-equivalent calories from step activity for runs.
- **Calibration**: Optional weekly calibration can apply a daily burn offset based on trend weight and logged intake quality checks.
- **Temperature and averaging**: A relatively high temperature (2.0) is used, but results are averaged across two runs to smooth out noise while still giving the model flexibility to interpret different plates.
- **Not a medical device**: The app is for personal tracking and educational purposes only; it is not intended for medical use.
