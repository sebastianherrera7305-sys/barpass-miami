#!/bin/bash
# Fails if a SwiftUI view under the given directories has a hardcoded,
# human-readable string literal instead of routing through l10n.t("key").
# Exists because the Greek Life feature shipped entirely hardcoded in
# Spanish, invisible to English/Portuguese users, with no guardrail
# catching it before it landed. Run before every commit that touches
# these directories:
#
#   BarPass-iOS/scripts/check-translations.sh
#
# TWO rules, because rule 1 alone missed real strings that shipped:
#
#   1. A quoted literal directly inside Text(/Label(/Button(/.alert(/
#      .navigationTitle(/.confirmationDialog(. This is what caught the
#      Greek Life regression. It ALSO catches the two city-hardcoded
#      taglines found by hand on 2026-09-16 — Text("Miami, at its best.")
#      in Core/Sharing/ShareCardView.swift and Text("NIGHTLIFE · MIAMI")
#      in Features/Splash/SplashView.swift — which went unnoticed only
#      because the scan was scoped to two directories. The scope is now
#      all of Features/ and Core/.
#
#   2. An ARRAY of string literals used as a UI label — the shape
#      `.bpAccessibility(label: ["Esta noche", "Explorar", …][index])`.
#      Rule 1 cannot see these: the literal is not adjacent to the call.
#      Only arrays on a line that is itself a label/title call are
#      flagged, so keyword tables, analytics names and SF Symbol lists
#      (data, not UI) stay quiet.
#
# A string is allowed through even if it "looks" hardcoded when it's:
#  - a % / string-format placeholder consumed elsewhere (handled by grep
#    only matching runs of letters, so "%@" alone won't trip this)
#  - an SF Symbol name, a font/color token, a URL, or a single punctuation
#    character (comma, space) — filtered out below
#  - already wrapped in l10n.t(...) / L10n.tSync(...) or
#    String(format: l10n.t(...), ...)
#  - a brand name that is the same word in every language (BarPass, REMY,
#    Ticketmaster) and is the ENTIRE literal — "BarPass, at its best."
#    would still be flagged.

set -euo pipefail
cd "$(dirname "$0")/.."

DIRS=(
  "BarPass/Features"
  "BarPass/Core"
)

# Literals that are proper nouns, identical in es/en/pt. Matched as the
# WHOLE literal, never as a substring of a longer sentence.
BRANDS='\("(BarPass|BARPASS|REMY|Ticketmaster)"\)'

FAIL=0

for target in "${DIRS[@]}"; do
  if [ -d "$target" ]; then
    FILES=$(find "$target" -name "*.swift")
  else
    FILES="$target"
  fi

  for file in $FILES; do
    # Rule 1 — literal directly inside a text-bearing call. The leading
    # (^|[^A-Za-z]) on Button keeps helper names like `presetButton("key")`
    # from matching, which used to happen and taught nothing.
    MATCHES=$(grep -nE '(Text|Label|(^|[^A-Za-z])Button|\.alert|\.navigationTitle|\.confirmationDialog)\(\s*"[A-Za-zÀ-ÿ]{3,}' "$file" \
      | grep -v 'l10n\.t(' \
      | grep -v 'L10n\.tSync(' \
      | grep -vE 'systemImage:\s*"' \
      | grep -vE "$BRANDS" \
      || true)

    # Rule 2 — array of string literals on a label/title line.
    ARRAYS=$(grep -nE '(bpAccessibility\(\s*label:|accessibilityLabel\(|\.navigationTitle\(|Text\(|Label\(|hint:)[^[]*\[\s*"[^"]*[A-Za-zÀ-ÿ]{3,}[^"]*"\s*,' "$file" \
      | grep -v 'l10n\.t(' \
      | grep -v 'L10n\.tSync(' \
      || true)

    if [ -n "$MATCHES" ] || [ -n "$ARRAYS" ]; then
      echo "❌ Hardcoded string(s) found in $file (not routed through l10n.t):"
      [ -n "$MATCHES" ] && echo "$MATCHES" | sed 's/^/    /'
      [ -n "$ARRAYS" ] && echo "$ARRAYS" | sed 's/^/    [array] /'
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
