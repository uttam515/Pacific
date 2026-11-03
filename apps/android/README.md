# OFFGRID Android Application

> **Lead:** Engineer 2  
> **Stack:** Kotlin, Jetpack Compose, Room Database, Kotlin Coroutines, Android BLE GATT

## Overview
This is the native Android implementation of the OFFGRID client:
- Offline-first Room persistence for all messages, operations, and node state.
- BLE GATT Server and Client for cross-platform interoperability with iOS.
- Wi-Fi Direct / Local IP communication where available.
- Store-and-forward relay support.
- Gateway sync when WAN is detected.

## Directory Structure (Recommended for Engineer 2)
```
apps/android/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/offgrid/app/
│   │   │   │   ├── data/          # Room DB, DAOs, Entities
│   │   │   │   ├── network/       # BLE GATT, Wi-Fi Direct, Packet transport
│   │   │   │   ├── protocol/      # Packet envelope conforming to Eng 1 spec
│   │   │   │   ├── sync/          # Operation queue & Cloud Gateway sync
│   │   │   │   └── ui/            # Jetpack Compose UI screens (Chat, SOS, Mesh)
│   │   │   └── AndroidManifest.xml
│   ├── build.gradle.kts
├── build.gradle.kts
├── settings.gradle.kts
└── gradle/
```

## BLE UUID Alignment
- **Service UUID:** `7B6E0001-C72B-4E36-96F1-30AA4B848694`
- **TX Characteristic:** `7B6E0002-C72B-4E36-96F1-30AA4B848694`
- **RX Characteristic:** `7B6E0003-C72B-4E36-96F1-30AA4B848694`
