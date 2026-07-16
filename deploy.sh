#!/usr/bin/env bash
# Deploy the working tree into the live WoW AddOns folder for in-game testing.
#
# No Libs/ to seed or preserve here -- VaultTracker has no vendored libraries of
# its own; everything comes from the required BoomForge dependency (deploy that
# separately). Run, then /reload in game.
set -euo pipefail

SRC="$HOME/projects/VaultTracker/"
DEST="/Applications/World of Warcraft/_retail_/Interface/AddOns/VaultTracker/"

rsync -a --delete \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='.gitignore' \
  --exclude='.pkgmeta' \
  --exclude='.superpowers/' \
  --exclude='.DS_Store' \
  --exclude='docs/' \
  --exclude='tests/' \
  --exclude='CLAUDE.md' \
  --exclude='VaultTracker-spec.md' \
  --exclude='deploy.sh' \
  "$SRC" "$DEST"

echo "Deployed to live AddOns folder. /reload in game."
