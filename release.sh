#!/usr/bin/env bash
# Usage: ./release.sh 0.2.0   -> tags v0.2.0 and pushes; GitHub Actions builds & publishes the APK.
set -euo pipefail
V="${1:?usage: ./release.sh <version>  e.g. 0.2.0}"
git push origin main
git tag -a "v$V" -m "Hollowmere v$V"
git push origin "v$V"
echo "Release v$V started: https://github.com/z1fire/hollowmere/actions"
