#!/bin/bash
# Regenerates MenuBarIconTemplate*.png and PRBar.icns from menubar.svg.
# Only needed when the SVG changes; build.sh just copies the results.
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -O Tools/MakeIcons.swift -o /tmp/prbar-makeicons
/tmp/prbar-makeicons "$PWD/Resources"
