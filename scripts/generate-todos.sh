#!/usr/bin/env bash
# =============================================================================
# generate-todos.sh  (BONUS)
# Extracts and tracks TODO/FIXME/HACK/NOTE comments from the codebase
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROMPT_FILE="${ROOT_DIR}/prompts/todos.txt"
TEMPLATE_FILE="${ROOT_DIR}/templates/todos.md"
OUTPUT_FILE="${ROOT_DIR}/ai-docs/todos.md"
DIFF_FILE="${ROOT_DIR}/changes.diff"
COMMIT_FILE="${ROOT_DIR}/commit.txt"

GROQ_MODEL="llama-3.3-70b-versatile"
GROQ_API_URL="https://api.groq.com/openai/v1/chat/completions"
GROQ_MAX_TOKENS=1500

if [[ -z "${GROQ_API_KEY:-}" ]]; then
  echo "❌ ERROR: GROQ_API_KEY is not set." >&2
  exit 1
fi

for f in "$PROMPT_FILE" "$TEMPLATE_FILE" "$DIFF_FILE" "$COMMIT_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "❌ ERROR: Required file not found: $f" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Scan codebase for TODO / FIXME / HACK / NOTE comments
# ---------------------------------------------------------------------------
TODO_SCAN=$(grep -rn \
  --include="*.js" \
  --include="*.ts" \
  --include="*.tsx" \
  --include="*.jsx" \
  --include="*.py" \
  --include="*.go" \
  --include="*.sh" \
  --include="*.java" \
  -E "(TODO|FIXME|HACK|NOTE|XXX|BUG)(\(.*?\))?:?\s*.+" \
  "$ROOT_DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=__pycache__ \
  2>/dev/null | head -60 || echo "No TODOs found in codebase.")

# Also grab TODOs from the diff specifically
DIFF_TODOS=$(grep -E "^\+.*\b(TODO|FIXME|HACK)\b" "$DIFF_FILE" 2>/dev/null || true)

PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")
DIFF_CONTENT=$(head -c 4000 "$DIFF_FILE")
COMMIT_MSG=$(cat "$COMMIT_FILE")

if [[ -f "$OUTPUT_FILE" ]]; then
  EXISTING_DOC=$(cat "$OUTPUT_FILE")
else
  EXISTING_DOC=$(cat "$TEMPLATE_FILE")
fi

FULL_PROMPT="${PROMPT_TEMPLATE}

=== COMMIT MESSAGE ===
${COMMIT_MSG}

=== TODOS FOUND IN CODEBASE ===
${TODO_SCAN}

=== NEW TODOs IN THIS DIFF ===
${DIFF_TODOS:-None in this diff.}

=== EXISTING TODOS.md ===
${EXISTING_DOC}
"

ESCAPED_PROMPT=$(printf '%s' "$FULL_PROMPT" \
  | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

echo "🤖 Calling Groq API for todos.md..."

HTTP_RESPONSE=$(curl --silent --show-error \
  --write-out "HTTPSTATUS:%{http_code}" \
  --max-time 60 \
  -X POST "$GROQ_API_URL" \
  -H "Authorization: Bearer ${GROQ_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${GROQ_MODEL}\",
    \"max_tokens\": ${GROQ_MAX_TOKENS},
    \"temperature\": 0.2,
    \"messages\": [{\"role\": \"user\", \"content\": ${ESCAPED_PROMPT}}]
  }" || true)

HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS:[0-9]*$//')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | grep -o 'HTTPSTATUS:[0-9]*' | cut -d: -f2)

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "❌ Groq API error (HTTP ${HTTP_STATUS:-unknown}):" >&2
  echo "$HTTP_BODY" >&2
  exit 1
fi

GENERATED=$(echo "$HTTP_BODY" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])")

if [[ -z "$GENERATED" ]]; then
  echo "❌ Empty response from Groq API." >&2
  exit 1
fi

python3 - "$OUTPUT_FILE" "$TEMPLATE_FILE" <<PYEOF
import re, sys, os

output_file, template_file = sys.argv[1], sys.argv[2]
generated = """${GENERATED}"""

if os.path.exists(output_file):
    with open(output_file) as f:
        existing = f.read()
else:
    with open(template_file) as f:
        existing = f.read()

block_re = re.compile(r'(<!-- AI:START:(\w+) -->)(.*?)(<!-- AI:END:\2 -->)', re.DOTALL)

gen_blocks = {}
for m in block_re.finditer(generated):
    gen_blocks[m.group(2)] = m.group(1) + m.group(3) + m.group(4)

def replace_block(match):
    name = match.group(2)
    return gen_blocks.get(name, match.group(0))

if block_re.search(existing):
    merged = block_re.sub(replace_block, existing)
else:
    merged = generated

os.makedirs(os.path.dirname(output_file) or '.', exist_ok=True)
with open(output_file, 'w') as f:
    f.write(merged)
print(f"✅ Written: {output_file}")
PYEOF

echo "✅ todos.md updated."

