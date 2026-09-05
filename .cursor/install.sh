#!/usr/bin/env bash
set -euo pipefail

# The homepage source ships as a RAR archive in the repo root. This script
# refreshes the extractor and unpacks the archive into ./site so it can be
# served and edited. It is safe to run repeatedly.

cd "$(dirname "$0")/.."

# Ensure the RAR extractor is available (idempotent).
if ! command -v unar >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unar
fi

# Extract the shipped homepage archive into ./site.
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
unar -quiet -force-overwrite -output-directory "$tmpdir" homepage.rar

rm -rf site
mkdir -p site
# The archive contains a top-level homepage/ folder; flatten it into ./site.
if [ -d "$tmpdir/homepage" ]; then
  cp -a "$tmpdir/homepage/." site/
else
  cp -a "$tmpdir/." site/
fi

echo "Homepage extracted to ./site"
