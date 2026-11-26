#!/bin/zsh
# Compiles the app sources (without the app entry point) together with Tests/main.swift
# and runs the checks. Snapshots of the rendered overlay land in build/snapshots.
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
sources=(${(f)"$(find IceBall -name '*.swift' ! -path 'IceBall/App/*')"})
swiftc -Onone \
  -target arm64-apple-macos26.0 \
  -swift-version 6 \
  -default-isolation MainActor \
  -module-name IceBallTests \
  -o build/IceBallTests \
  "${sources[@]}" Tests/main.swift
./build/IceBallTests build/snapshots
