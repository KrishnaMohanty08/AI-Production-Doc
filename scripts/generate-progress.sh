#!/usr/bin/env bash
# =============================================================================
# generate-progress.sh
# Generates/updates ai-docs/progress.md using Groq API
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROMPT_FILE="${ROOT_DIR}/prompts/progress.txt"
TEMPLATE_FILE="${ROOT_DIR}/templates/progress.md"
OUTPUT_FILE="${ROOT_DIR}/ai-docs/progress.md"
DIFF_FILE="${ROOT_DIR}/changes.diff"
COMMIT_FILE="${ROOT_DIR}/commit.txt"

GROQ_MODEL="llama-3.3-70b-versatile"
GROQ_API_URL="https://api.groq.com/openai/v1/chat/completions"
GROQ_MAX_TOKENS=2048

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ -z "${GROQ_API_KEY:-}" ]]; then
  echo "❌ ERROR: GROQ_API_KEY environment variable is not set." >&2
  exit 1
fi

for f in "$PROMPT_FILE" "$TEMPLATE_FILE" "$DIFF_FILE" "$COMMIT_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "❌ ERROR: Required file not found: $f" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Check .llmignore
# ---------------------------------------------------------------------------
LLMIGNORE="${ROOT_DIR}/.llmignore"
if [[ -f "$LLMIGNORE" ]]; then
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
    if echo "$DIFF_FILE" | grep -q "$pattern" 2>/dev/null; then
      echo "⏭️  Skipping due to .llmignore rule: $pattern"
      exit 0
    fi
  done < "$LLMIGNORE"
fi

# ---------------------------------------------------------------------------
# Read inputs
# ---------------------------------------------------------------------------
PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")
DIFF_CONTENT=$(cat "$DIFF_FILE")
COMMIT_MSG=$(cat "$COMMIT_FILE")

if [[ -f "$OUTPUT_FILE" ]]; then
  EXISTING_DOC=$(cat "$OUTPUT_FILE")
else
  EXISTING_DOC=$(cat "$TEMPLATE_FILE")
  echo "ℹ️  No existing progress.md — using template as base."
fi

# Truncate diff to avoid token overflow (max ~6000 chars)
DIFF_TRUNCATED=$(printf '%s' "$DIFF_CONTENT" | head -c 6000)
if [[ ${#DIFF_CONTENT} -gt 6000 ]]; then
  DIFF_TRUNCATED="${DIFF_TRUNCATED}
... [diff truncated for token limit]"
fi

# ---------------------------------------------------------------------------
# Build prompt
# ---------------------------------------------------------------------------
FULL_PROMPT="${PROMPT_TEMPLATE}

=== COMMIT MESSAGE ===
${COMMIT_MSG}

=== GIT DIFF (changes.diff) ===
${DIFF_TRUNCATED}

=== EXISTING PROGRESS.md ===
${EXISTING_DOC}
"

# ---------------------------------------------------------------------------
# Escape for JSON
# ---------------------------------------------------------------------------
ESCAPED_PROMPT=$(printf '%s' "$FULL_PROMPT" \
  | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# ---------------------------------------------------------------------------
# Call Groq API
# ---------------------------------------------------------------------------
echo "🤖 Calling Groq API for progress.md..."

HTTP_RESPONSE=$(curl --silent --show-error --fail-with-body \
  --write-out "HTTPSTATUS:%{http_code}" \
  --max-time 60 \
  -X POST "$GROQ_API_URL" \
  -H "Authorization: Bearer ${GROQ_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${GROQ_MODEL}\",
    \"max_tokens\": ${GROQ_MAX_TOKENS},
    \"temperature\": 0.3,
    \"messages\": [{\"role\": \"user\", \"content\": ${ESCAPED_PROMPT}}]
  }" || true)

HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS:[0-9]*$//')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | grep -o 'HTTPSTATUS:[0-9]*' | cut -d: -f2)

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "❌ Groq API error (HTTP ${HTTP_STATUS:-unknown}):" >&2
  echo "$HTTP_BODY" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract content
# ---------------------------------------------------------------------------
GENERATED=$(echo "$HTTP_BODY" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])")

if [[ -z "$GENERATED" ]]; then
  echo "❌ Empty response from Groq API." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Merge: preserve manual edits outside AI blocks
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

echo "✅ progress.md updated."

