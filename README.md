# Calorie Tracker

Calorie Tracker is an iOS app for logging food, calories, and nutrients.

It includes:
- Manual logging and quick add flows
- PCC dining menu import (Nutrislice)
- USDA food search (through Firebase Functions)
- AI meal text analysis
- AI food photo analysis
- AI plate portion estimation for menu items
- Health/step/exercise integration and widget support

## Repo layout

- `Calorie Tracker/`: main iOS SwiftUI app
- `Calorie Tracker Widgets/`: iOS widgets
- `Calorie TrackerUITests/`: UI test target
- `functions/`: Firebase Functions backend (TypeScript)
- `public/`: Firebase Hosting site (`/privacy` page)
- `scripts/stress/`: stress and regression test runner
- `webapp/`: separate Vite TypeScript sandbox/demo app

## Requirements

- macOS + Xcode (for iOS app development)
- Node.js 20 (for `functions/`)
- Firebase CLI (`npm i -g firebase-tools`)

## Run the iOS app

1. Open `Calorie Tracker.xcodeproj` in Xcode.
2. Select the `Calorie Tracker` scheme.
3. Choose an iOS Simulator or device.
4. Run (`Cmd+R`).

## Backend (Firebase Functions)

The backend exposes these HTTP functions:
- `searchUSDAFoods`
- `estimatePlatePortions`
- `analyzeFoodPhoto`
- `analyzeFoodText`
- `proxyNutrislice`

Current app usage:
- iOS app calls `searchUSDAFoods`, `estimatePlatePortions`, `analyzeFoodPhoto`, and `analyzeFoodText`.
- `proxyNutrislice` is used by Firebase Hosting rewrites for `/api/nutrislice/**`.

### Setup

```bash
cd functions
npm install
firebase functions:secrets:set USDA_API_KEY
firebase functions:secrets:set GEMINI_API_KEY
npm run build
```

### Run emulator

```bash
cd functions
npm run serve
```

### Deploy

```bash
cd functions
npm run deploy
```

## Hosting

Hosting serves files from `public/`.

- `/privacy` rewrites to `public/privacy.html`
- `/api/nutrislice/**` rewrites to the `proxyNutrislice` function

Deploy:

```bash
firebase deploy --only hosting
```

## Stress tests

Run from repo root:

```bash
STRESS_TIER=pr ./scripts/stress/run_all.sh
```

Other tiers: `nightly`, `pre-release`.
Outputs are written under `output/stress/<run-id>/`.

## Notes

- Default Firebase project in this repo is `calorie-tracker-364e3` (see `.firebaserc`).
- The iOS services currently default to the deployed backend URL:
  `https://us-central1-calorie-tracker-364e3.cloudfunctions.net`
