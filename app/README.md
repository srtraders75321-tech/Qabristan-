# Flutter app

The Flutter project has not been generated yet. Generate it on the developer machine (see `docs/SETUP_WINDOWS.md`, section 3):

```
flutter create --platforms=android,ios --project-name kabristan_committee --org <your.org.id> app
```

Run this from the repository root. It fills this directory with the standard Flutter project.

## Planned structure

```
lib/
  core/       theme (Emerald & Ivory tokens), routing, config, localization
  features/   families, members, payments, receipts, burials, admin
  data/       repositories that call Supabase (no money math)
l10n/         app_en.arb, app_ur.arb
test/
```

## Rules

- Money calculations happen in the database. The app displays results.
- Screens depend on repository interfaces, so they can run on fictional data before the backend feature is ready.
- Every user-visible string is in both ARB files. Check screens in RTL.
