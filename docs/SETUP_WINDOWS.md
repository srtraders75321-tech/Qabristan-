# Developer Setup (Windows)

Do these steps on the Windows laptop. Check each tool's official site for the current installer.

## 1. Accounts

| Account | Needed from | Notes |
|---|---|---|
| GitHub | Now | Private repo `srtraders75321-tech/Qabristan-` |
| Supabase | Phase 0 | Create two projects: `kabristan-staging` and `kabristan-production`. Leave production empty |
| Apple Developer Program | Start early (Phase 1) | Needed for iOS. Enrollment can take days. Decision D7 sets the distribution method |
| Codemagic | Phase 8 (can start earlier) | Cloud Mac for iOS builds |
| Backup provider | Phase 8 | Second provider for encrypted dumps |

## 2. Software

1. Git for Windows
2. VS Code with the **Flutter** and **Dart** extensions
3. Flutter SDK (stable channel)
4. Android Studio (installs the Android SDK and emulator); accept Android licenses: `flutter doctor --android-licenses`
5. Node.js (LTS)
6. WSL2, then Docker Desktop (needed to run Supabase locally)
7. Supabase CLI

Verify: `flutter doctor` shows no errors for Windows and Android. iOS items are expected to be unavailable on Windows.

## 3. Create the Flutter project (once)

From the repo root:

```
flutter create --platforms=android,ios --project-name kabristan_committee --org <your.org.id> app
```

`<your.org.id>` becomes the app's bundle/application ID. It is hard to change later, so decide it first (see DECISIONS Q4). Commit the generated project.

## 4. Initialize Supabase locally (once)

From the repo root:

```
supabase init
supabase start
```

This creates `supabase/config.toml`. Link the **staging** project only (`supabase link`). Never link production from a developer laptop.

## 5. Secrets

- Keep Supabase keys, signing keystores, and Apple certificates out of the repo.
- Local values go in `.env` files (ignored by git). Share a `.env.example` with names only.
- CI secrets are stored in the GitHub repository's secret settings, never in files.

## 6. Verify the repo tooling

```
node --test ".claude/hooks/*.test.mjs"
```

All hook tests should pass.
