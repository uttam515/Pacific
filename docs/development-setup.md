# OFFGRID Developer Setup Guide

This guide describes how to configure your workstation to build and run the OFFGRID ecosystem.

---

## 1. Prerequisites Checklist

| Component | Required For | Recommended Version |
| :--- | :--- | :--- |
| **Node.js** | Backend, Web, Shared Packages | v20.x or higher |
| **pnpm** | Monorepo dependency management | v10.x or v12.x |
| **PostgreSQL** | Central backend database | v15.x or higher |
| **Xcode** | iOS Application | 16.0+ (iOS SDK 17.0+) |
| **Android Studio** | Android Application | Ladybug / Meerkat (API 34+) |
| **Java JDK** | Android Gradle builds | OpenJDK 17 or 21 |

---

## 2. Monorepo Setup (All Engineers)

1. Clone the repository and checkout `develop`:
   ```bash
   git checkout develop
   ```

2. Install Node dependencies:
   ```bash
   pnpm install
   ```

3. Copy environment configuration:
   ```bash
   cp .env.example .env
   ```

---

## 3. Engineer 1 Guide — Web, Backend & Protocol

1. Navigate to services:
   ```bash
   # In services/api-server
   pnpm dev

   # In apps/web-dashboard
   pnpm dev
   ```

2. Database Setup:
   Ensure PostgreSQL is running locally with database `offgrid_db`.

---

## 4. Engineer 2 Guide — Android Application

1. Open Android Studio:
   - File -> Open -> Select `apps/android`
2. Configure JDK 17+ in Gradle settings.
3. Sync Gradle and run on an Android device or emulator with API 34+.
4. **Bluetooth Testing:** Physical Android devices are required to test BLE advertising and GATT servers.

---

## 5. Engineer 3 Guide — iOS Application

1. Open Xcode:
   ```bash
   open apps/ios/OFFGRID.xcodeproj
   ```
2. Build via Xcode (Cmd+B) or Terminal:
   ```bash
   xcodebuild -project apps/ios/OFFGRID.xcodeproj -scheme OFFGRID -destination 'generic/platform=iOS Simulator' build
   ```
3. Run on physical iPhone:
   - Select your personal development team in **Signing & Capabilities**.
   - Physical devices are required for Multipeer Connectivity and CoreBluetooth peripheral advertising.
