#!/bin/bash
# Fails if a SwiftUI view under the given directories has a hardcoded,
# human-readable string literal in Text(/Label(/Button(/.alert(/
# .navigationTitle(/.confirmationDialog( instead of routing through
# l10n.t("key"). Exists because the Greek Life feature shipped entirely
# hardcoded in Spanish, invisible to English/Portuguese users, with no
# guardrail catching it before it landed. Run before every commit that
# touches these directories:
#
#   BarPass-iOS/scripts/check-translations.sh
#
# A string is allowed through even if it "looks" hardcoded when it's:
#  - a % / string-format placeholder consumed elsewhere (handled by grep
#    only matching runs of letters, so "%@" alone won't trip this)
#  - an SF Symbol name, a font/color token, a URL, or a single punctuation
#    character (comma, space) — filtered out below
#  - already wrapped in l10n.t(...) or String(format: l10n.t(...), ...)

set -euo pipefail
cd "$(dirname "$0")/.."

DIRS=(
  "BarPass/Features/CollegeLife"
  "BarPass/Features/Profile/AffiliationPickerView.swift"
)

FAIL=0

for target in "${DIRS[@]}"; do
  if [ -d "$target" ]; then
    FILES=$(find "$target" -name "*.swift")
  else
    FILES="$target"
  fi

  for file in $FILES; do
    # Lines with Text(/Label(/Button(/.alert(/.navigationTitle(/.confirmationDialog(
    # followed directly by a quoted literal (not l10n.t(...), not a variable).
    MATCHES=$(grep -nE '(Text|Label|Button|\.alert|\.navigationTitle|\.confirmationDialog)\(\s*"[A-Za-zÀ-ÿ]{3,}' "$file" \
      | grep -v 'l10n\.t(' \
      | grep -vE 'systemImage:\s*"' \
      || true)

    if [ -n "$MATCHES" ]; then
      echo "❌ Hardcoded string(s) found in $file (not routed through l10n.t):"
      echo "$MATCHES" | sed 's/^/    /'
      FAIL=1
    fi
  done
done

if [ "$FAIL" -eq 1 ]; then
  echo ""
  echo "Fix: replace each literal with l10n.t(\"your.key\") — add the key to"
  echo "all three language tables (.es/.en/.pt) in"
  echo "BarPass/Core/Services/LocalizationService.swift, then rerun this script."
  exit 1
fi

echo "✅ No hardcoded strings found."
