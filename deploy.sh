#!/usr/bin/env bash
# Deploy the working tree into the live WoW AddOns folder for in-game testing.
#
# Syncs code/locale/toc only. Dev and tooling files are excluded, and Libs/ is
# left untouched in the live folder (seeded once, then preserved) so a code
# deploy can never wipe the vendored libraries. Run, then /reload in game.
set -euo pipefail

SRC="$HOME/projects/VaultTracker/"
DEST="/Applications/World of Warcraft/_retail_/Interface/AddOns/VaultTracker/"

if [ ! -d "$DEST/Libs" ]; then
  echo "Libs/ missing in live folder. Seed it first:" >&2
  echo "  rsync -a \"$SRC\"Libs/ \"$DEST\"Libs/" >&2
  exit 1
fi

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
  --exclude='Libs/' \
  "$SRC" "$DEST"

echo "Deployed to live AddOns folder. /reload in game."
