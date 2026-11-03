#!/usr/bin/env bash
set -euo pipefail

echo "==========================================="
echo "   OFFGRID Monorepo Workspace Verification "
echo "==========================================="

echo "Checking Node.js & pnpm..."
node -v
pnpm -v

echo "Checking Git branches..."
git branch -a

echo "Checking Xcode tools..."
if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -version
else
    echo "xcodebuild not installed or not in PATH"
fi

echo "Checking Android SDK..."
if [ -n "${ANDROID_HOME:-}" ] || [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    echo "Android SDK found at ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
else
    echo "Notice: ANDROID_HOME is unset. Engineer 2 should configure Android SDK."
fi

echo "Workspace verification complete."
