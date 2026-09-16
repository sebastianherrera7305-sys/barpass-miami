#!/bin/bash
# Barrido completo de cartas: las 23 ciudades, una por una, reanudable.
#
# Reanudable de verdad: extract-drink-menus saltea los venues que ya tienen
# carta y los que quedaron registrados como "none_published", así que si esto
# se corta (red, cuota, la Mac dormida) se vuelve a lanzar igual y sigue donde
# estaba. No hay estado propio que mantener.
#
# El orden es el del mercado: primero los college towns y Miami, que es donde
# lanzamos, y las ciudades grandes al final — son las que más venues tienen y
# las que menos urgen.
#
#   bash scripts/sweep-drink-menus.sh            # escribe
#   bash scripts/sweep-drink-menus.sh --dry-run  # no escribe
set -u
cd "$(dirname "$0")/.."
APPLY="--apply"; [ "${1:-}" = "--dry-run" ] && APPLY=""
LOG_DIR="${SWEEP_LOG_DIR:-/tmp/barpass-sweep}"
mkdir -p "$LOG_DIR"

CITIES=(
  "Gainesville" "Miami" "Tallahassee" "Tuscaloosa" "Athens" "Oxford"
  "College Station" "Bloomington" "Chapel Hill" "State College" "Ann Arbor"
  "Madison" "Boulder" "Tempe" "Baton Rouge" "Columbus" "Austin"
  "Nashville" "New Orleans" "Las Vegas" "Los Angeles" "Chicago" "New York"
)

echo "== barrido de cartas · $(date '+%Y-%m-%d %H:%M') · ${#CITIES[@]} ciudades =="
for CITY in "${CITIES[@]}"; do
  LOG="$LOG_DIR/$(echo "$CITY" | tr ' ' '-').log"
  echo ""
  echo "---- $CITY ----"
  node --env-file=.env.local --import tsx scripts/extract-drink-menus.ts --city "$CITY" $APPLY > "$LOG" 2>&1
  tail -1 "$LOG"
  # Si la corrida cortó por red, esperar y reintentar esa ciudad una vez antes
  # de seguir: el corta-circuito ya evitó escribir falsos negativos.
  if grep -q "STOPPING:" "$LOG"; then
    echo "   (red caída — espero 3 min y reintento $CITY)"
    sleep 180
    node --env-file=.env.local --import tsx scripts/extract-drink-menus.ts --city "$CITY" $APPLY >> "$LOG" 2>&1
    tail -1 "$LOG"
  fi
done
echo ""
echo "== barrido terminado · $(date '+%H:%M') · logs en $LOG_DIR =="
