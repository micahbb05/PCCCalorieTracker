# Firebase Backend Menu Sync

This Cloud Functions package syncs the Four Winds lunch menu from Nutrislice into Firestore `menus/today` and proxies USDA food search so the iOS app does not ship the USDA API key.

## What it deploys

- `syncTodayMenuDaily` (scheduled): runs every day at `6:00 AM` in `America/Los_Angeles`.
- `syncTodayMenuNow` (HTTP): manual trigger for immediate sync testing.
- `searchUSDAFoods` (HTTP): proxies USDA food search for the app.

## Firestore output

Document: `menus/today`

Fields written:
- `source: "nutrislice"`
- `sourceDate: "YYYY-MM-DD"`
- `syncedAt: server timestamp`
- `lines: [{ id, name, items: [{ id, name, calories, protein }] }]`

## Deploy

From repo root:

```bash
npx firebase-tools login
npx firebase-tools functions:secrets:set USDA_API_KEY
npx firebase-tools deploy --only functions
```

## Manual test after deploy

Call:

```bash
curl https://us-central1-calorie-tracker-364e3.cloudfunctions.net/syncTodayMenuNow
```

Expected JSON:

```json
{ "ok": true, "sourceDate": "...", "lineCount": 11, "itemCount": 72 }
```

USDA proxy test:

```bash
curl "https://us-central1-calorie-tracker-364e3.cloudfunctions.net/searchUSDAFoods?query=banana"
```
