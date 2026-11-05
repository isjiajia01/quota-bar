#!/usr/bin/env bash
# Token lint: raw colours, sizes, radii, font sizes, opacities and durations are only
# allowed in Sources/QuotaBar/Design/Tokens.swift. Exit 1 on any violation.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

allow="Sources/QuotaBar/Design/Tokens.swift"
files=$(find Sources/QuotaBar -name '*.swift' ! -path "$allow")

patterns=(
  'Color\((red|white|hue|\.sRGB|nsColor: *NSColor\()'     # raw colour constructors
  'NSColor\((red|srgbRed|white|calibrated|deviceRed)'
  '#[0-9A-Fa-f]{6}\b'                                       # hex literals
  '(Color|NSColor)\.(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|gray|black|white|system[A-Z][a-z]+)\b'
  '\.font\(\.system\(size'                                  # raw font sizes
  'Font\.system\(size'
  '\.padding\((\.[a-zA-Z]+, *)?[0-9]'                       # raw padding
  'spacing: *[1-9]'                                         # raw stack spacing (0 allowed)
  'cornerRadius: *[0-9]'                                    # raw radii
  '\.frame\([^)]*(width|height|minWidth|maxWidth|minHeight|maxHeight|idealWidth|idealHeight): *[0-9]'
  'lineWidth: *[0-9]'
  '\.opacity\(0?\.[0-9]'                                    # raw opacity
  '(duration|response): *[0-9]'                             # raw animation timing
)

status=0
for p in "${patterns[@]}"; do
  if hits=$(grep -nE "$p" $files); then
    echo "token-lint: raw value outside Tokens.swift (pattern: $p)"
    echo "$hits" | sed 's/^/  /'
    status=1
  fi
done

[ $status -eq 0 ] && echo "token-lint: OK ($(echo "$files" | wc -l | tr -d ' ') files)"
exit $status
