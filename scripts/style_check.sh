#!/usr/bin/env bash
# Reports where the tree disagrees with CODE_STYLE.md. A report, not a gate:
# each line is a question ("is this one job?"), and the answer may be "yes".
set -euo pipefail
cd "$(dirname "$0")/.."

section() { printf '\n== %s ==\n' "$1"; }
over() { # over <lines> <path...>
  local limit=$1; shift
  find "$@" -name '*.dart' ! -name '*.g.dart' ! -path '*/src/rust/*' \
    -exec awk -v l="$limit" 'END{if(NR>l)printf "%5d %s\n",NR,FILENAME}' {} \; | sort -rn
}

section "widgets over 200 lines"
over 200 lib/presentation
section "cubit parts over 250 lines"
find lib/logic/cubits -name '*.dart' ! -name '*_cubit.dart' ! -name '*_state.dart' ! -name '*.g.dart' \
  -exec awk 'END{if(NR>250)printf "%5d %s\n",NR,FILENAME}' {} \; | sort -rn
section "cubit hubs over 400 lines"
find lib/logic/cubits -name '*_cubit.dart' -exec awk 'END{if(NR>400)printf "%5d %s\n",NR,FILENAME}' {} \; | sort -rn
section "repositories over 350 lines"
over 350 lib/data/repositories
section "models / helpers over 200 lines"
over 200 lib/data/classes lib/data/enums lib/logic/services

section "colour literals outside presentation/theme"
grep -rn 'Color(0x' lib --include=*.dart | grep -v 'lib/presentation/theme/' || true
section "fontSize outside app_text.dart"
grep -rn 'fontSize:' lib/presentation --include=*.dart | grep -v -e 'theme/app_text.dart' -e 'common/emoji_text.dart' || true
section "literal radii"
grep -rnE 'BorderRadius\.circular\([0-9]' lib/presentation --include=*.dart || true
section "CircularProgressIndicator (use LoadingDots)"
grep -rln 'CircularProgressIndicator' lib --include=*.dart || true
section "dart:io in widgets"
grep -rln "import 'dart:io'" lib/presentation --include=*.dart || true
section "ListView(children:) (use .builder)"
grep -rn 'ListView($' lib --include=*.dart || true
section "ThemeState as a constructor parameter"
grep -rn 'final ThemeState ' lib/presentation --include=*.dart || true
section "literal Duration in widgets (use AppMotion)"
grep -rn 'Duration(milliseconds' lib/presentation --include=*.dart | grep -v 'theme/' || true
section "bare print"
grep -rnE '^\s*print\(' lib --include=*.dart || true
