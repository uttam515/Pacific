# OFFGRID — Contribution & Git Collaboration Guidelines

Welcome to the OFFGRID development repository. To ensure smooth collaboration between all three engineers during the hackathon, please follow these conventions.

---

## 1. Branch Strategy

We use a modified Git Flow model:

- `main`: Production-ready, stable releases. Protected branch.
- `develop`: Integration branch where all tested features land.
- `feature/*`: Dedicated branches for each component and engineer.

### Canonical Feature Branches
- `feature/web-dashboard` — Web Dashboard (Engineer 1)
- `feature/backend` — API Server & Central DB (Engineer 1)
- `feature/network-core` — Shared Protocol & Sync Engine (Engineer 1 Lead, Eng 2 & 3 align)
- `feature/android-app` — Native Android Kotlin App (Engineer 2)
- `feature/ios-app` — Native iOS Swift App (Engineer 3)

### Branch Naming Conventions
- `feature/<component>-<short-description>` (e.g. `feature/ios-sqlite-queue`)
- `fix/<component>-<short-description>` (e.g. `fix/ble-packet-fragmentation`)
- `docs/<short-description>` (e.g. `docs/update-protocol-spec`)

---

## 2. Commit Message Conventions

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <short description in imperative mood>

[optional body explaining motivation and details]

[optional footer(s)]
```

### Allowed Types
- `feat`: New feature for the user or platform
- `fix`: Bug fix
- `docs`: Documentation only changes
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `test`: Adding or updating tests
- `chore`: Changes to build process, dependencies, or tool configurations

### Scopes
- `ios`: iOS application
- `android`: Android application
- `web`: Web dashboard
- `api`: Backend server
- `protocol`: Shared protocol & serialization
- `sync`: Synchronization engine
- `repo`: Monorepo tooling and workspace configs

**Example:**
`feat(ios): implement sqlite local operation queue for offline-first actions`

---

## 3. Pull Request & Review Rules

1. **Target Branch:** All feature PRs must target `develop`, not `main`.
2. **Review Ownership:**
   - Protocol & API contract PRs must be reviewed and approved by **Engineer 1**.
   - Android-specific PRs are reviewed by **Engineer 2**.
   - iOS-specific PRs are reviewed by **Engineer 3**.
   - Cross-platform changes (BLE GATT, packet framing) must be coordinated across both mobile engineers.
3. **Never push directly to `main` or force push (`--force`) to shared branches.**

---

## 4. Local Verification Before Pushing

Before opening a PR:
- TypeScript/Web/Backend: `pnpm run lint` and `pnpm run test`
- iOS: Build target `OFFGRID` in Xcode or run `xcodebuild -project apps/ios/OFFGRID.xcodeproj -scheme OFFGRID -destination 'generic/platform=iOS Simulator'`
- Android: `./gradlew assembleDebug testDebugUnitTest`
