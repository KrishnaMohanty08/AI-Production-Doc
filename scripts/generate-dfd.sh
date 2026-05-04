#!/usr/bin/env bash
# =============================================================================
# generate-dfd.sh
# Generates/updates ai-docs/dfd.md with Mermaid DFD diagrams using Groq API
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROMPT_FILE="${ROOT_DIR}/prompts/dfd.txt"
TEMPLATE_FILE="${ROOT_DIR}/templates/dfd.md"
OUTPUT_FILE="${ROOT_DIR}/ai-docs/dfd.md"
DIFF_FILE="${ROOT_DIR}/changes.diff"
COMMIT_FILE="${ROOT_DIR}/commit.txt"

GROQ_MODEL="llama-3.3-70b-versatile"
GROQ_API_URL="https://api.groq.com/openai/v1/chat/completions"
GROQ_MAX_TOKENS=2048

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
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
# Read inputs
# ---------------------------------------------------------------------------
PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")
DIFF_CONTENT=$(echo "$(cat "$DIFF_FILE")" | head -c 5000)
COMMIT_MSG=$(cat "$COMMIT_FILE")

if [[ -f "$OUTPUT_FILE" ]]; then
  EXISTING_DOC=$(cat "$OUTPUT_FILE")
else
  EXISTING_DOC=$(cat "$TEMPLATE_FILE")
  echo "ℹ️  No existing dfd.md — using template as base."
fi

# Collect endpoint/route hints from diff
ROUTES=$(echo "$DIFF_CONTENT" | grep -E "(app\.(get|post|put|delete|patch)|router\.|@(Get|Post|Put|Delete)|def [a-z_]+\(request)" | head -20 || true)

# ---------------------------------------------------------------------------
# Build prompt
# ---------------------------------------------------------------------------
FULL_PROMPT="${PROMPT_TEMPLATE}

=== COMMIT MESSAGE ===
${COMMIT_MSG}

=== DETECTED ROUTES/ENDPOINTS ===
${ROUTES:-None detected in this diff.}

=== GIT DIFF (changes.diff) ===
${DIFF_CONTENT}

=== EXISTING DFD.md ===
${EXISTING_DOC}
"

ESCAPED_PROMPT=$(printf '%s' "$FULL_PROMPT" \
  | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# ---------------------------------------------------------------------------
# Call Groq API
# ---------------------------------------------------------------------------
echo "🤖 Calling Groq API for dfd.md..."

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

# ---------------------------------------------------------------------------
# Validate Mermaid blocks are present
# ---------------------------------------------------------------------------
if ! echo "$GENERATED" | grep -q '```mermaid'; then
  echo "⚠️  WARNING: Generated output does not contain a Mermaid diagram block." >&2
fi

# ---------------------------------------------------------------------------
# Merge: preserve manual content outside AI blocks
# ---------------------------------------------------------------------------
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

echo "✅ dfd.md updated."

