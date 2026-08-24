#!/bin/bash
# Compiles CommentWatcher against its tests and runs them. The app builds as a
# bare swiftc invocation rather than a SwiftPM package, so this does the same.
set -euo pipefail
cd "$(dirname "$0")"
swiftc -O \
  Sources/GitHubClient.swift \
  Sources/CommentWatcher.swift \
  Tools/CommentWatcherTests.swift \
  -o /tmp/prbar-tests
/tmp/prbar-tests
