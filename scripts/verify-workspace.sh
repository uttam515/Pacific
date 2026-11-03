#!/usr/bin/env bash
set -euo pipefail

echo "==========================================="
echo "   OFFGRID Monorepo Workspace Verification "
echo "==========================================="

echo "Checking Node.js & pnpm..."
node -v
pnpm -v

echo "Checking Git repository..."
git rev-parse --is-inside-work-tree >/dev/null && echo "Git repository verified."

echo "Checking Xcode tools (macOS only)..."
if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -version
else
    echo "Notice: xcodebuild not present (non-macOS environment or CLI not linked)."
fi

echo "Checking Android SDK..."
if [ -n "${ANDROID_HOME:-}" ] || [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    echo "Android SDK found at ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
else
    echo "Notice: ANDROID_HOME is unset. Engineer 2 should configure Android SDK."
fi

echo "Workspace verification complete."
