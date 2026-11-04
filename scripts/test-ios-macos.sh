#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -D DEBUG -swift-version 5 -o "$out/offgrid-tests" \
 apps/ios/OFFGRID/Protocol/*.swift \
 apps/ios/OFFGRID/Data/Models/*.swift \
 apps/ios/OFFGRID/Data/Database/*.swift \
 apps/ios/OFFGRID/Data/Repositories/*.swift \
 apps/ios/OFFGRID/Security/*.swift \
 apps/ios/OFFGRID/Networking/Discovery/*.swift \
 apps/ios/OFFGRID/Networking/Multipeer/*.swift \
 apps/ios/OFFGRID/Networking/Relay/*.swift \
 apps/ios/OFFGRID/Networking/Mesh/*.swift \
 apps/ios/OFFGRID/Networking/Routing/*.swift \
 apps/ios/OFFGRID/Sync/GatewayQueue.swift \
 apps/ios/OFFGRID/Sync/GatewayManager.swift \
 apps/ios/Tests/*.swift
"$out/offgrid-tests"
