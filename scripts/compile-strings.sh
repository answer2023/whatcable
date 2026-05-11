#!/usr/bin/env bash
# Compile .xcstrings string catalogs into .lproj directories inside the
# SPM debug build bundles.  Run this after `swift build` so that
# String(localized:bundle:) picks up the non-English translations at
# runtime.
#
# Usage:  ./scripts/compile-strings.sh
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR=".build/arm64-apple-macosx/debug"

for bundle_name in WhatCable_WhatCableCore WhatCable_WhatCable; do
    xcstrings="${BUILD_DIR}/${bundle_name}.bundle/Localizable.xcstrings"
    if [[ -f "${xcstrings}" ]]; then
        xcrun xcstringstool compile "${xcstrings}" \
            --output-directory "$(dirname "${xcstrings}")"
        echo "Compiled ${bundle_name}.bundle"
    fi
done
