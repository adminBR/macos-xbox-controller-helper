#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/.build/tests"
TEST_DIR="$PROJECT_DIR/.build/tests"
xcrun swiftc "$PROJECT_DIR/Sources/PromptPolicy.swift" "$PROJECT_DIR/Tests/PromptPolicyTests.swift" -o "$TEST_DIR/prompt-tests"
"$TEST_DIR/prompt-tests"
xcrun clang -dynamiclib "$PROJECT_DIR/Tests/mock-sdl.c" -o "$TEST_DIR/mock-sdl.dylib"
xcrun clang "$PROJECT_DIR/Tests/shim-tests.c" -o "$TEST_DIR/shim-tests"
xcrun clang -dynamiclib -arch arm64 -arch x86_64 -Wall -Wextra "$PROJECT_DIR/Sources/xbox-identity.c" -o "$TEST_DIR/xbox-identity.dylib"
for SWAP in 1 0; do
    DYLD_INSERT_LIBRARIES="$TEST_DIR/xbox-identity.dylib" X5_SWAP_FACE_BUTTONS="$SWAP" "$TEST_DIR/shim-tests" "$TEST_DIR/mock-sdl.dylib"
done
