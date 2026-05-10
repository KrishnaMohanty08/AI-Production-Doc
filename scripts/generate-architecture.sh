#!/usr/bin/env bash
# =============================================================================
# generate-architecture.sh
# Generates/updates ai-docs/architecture.md using Groq API
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROMPT_FILE="${ROOT_DIR}/prompts/architecture.txt"
TEMPLATE_FILE="${ROOT_DIR}/templates/architecture.md"
OUTPUT_FILE="${ROOT_DIR}/ai-docs/architecture.md"
DIFF_FILE="${ROOT_DIR}/changes.diff"
COMMIT_FILE="${ROOT_DIR}/commit.txt"

FULL_ANALYSIS=false

if [[ ! -f "$OUTPUT_FILE" ]]; then
  FULL_ANALYSIS=true
  echo "🚀 FULL ANALYSIS MODE ENABLED"
fi

GROQ_MODEL="llama-3.3-70b-versatile"
GROQ_API_URL="https://api.groq.com/openai/v1/chat/completions"
GROQ_MAX_TOKENS=2000

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
# Detect tech stack from repo structure
# ---------------------------------------------------------------------------
STACK_HINTS=""
[[ -f "${ROOT_DIR}/package.json" ]]          && STACK_HINTS+="Node.js detected (package.json)\n"
[[ -f "${ROOT_DIR}/prisma/schema.prisma" ]]  && STACK_HINTS+="Prisma ORM detected\n"
[[ -f "${ROOT_DIR}/src/app.tsx" ]]           && STACK_HINTS+="React (TSX) detected\n"
[[ -f "${ROOT_DIR}/src/app.jsx" ]]           && STACK_HINTS+="React (JSX) detected\n"
[[ -f "${ROOT_DIR}/requirements.txt" ]]      && STACK_HINTS+="Python detected (requirements.txt)\n"
[[ -f "${ROOT_DIR}/pyproject.toml" ]]        && STACK_HINTS+="Python (pyproject.toml) detected\n"
[[ -f "${ROOT_DIR}/go.mod" ]]                && STACK_HINTS+="Go detected (go.mod)\n"
[[ -f "${ROOT_DIR}/Dockerfile" ]]            && STACK_HINTS+="Docker detected\n"
[[ -f "${ROOT_DIR}/docker-compose.yml" ]]    && STACK_HINTS+="Docker Compose detected\n"

# Read repo tree (top 2 levels)
# -----------------------------------------------------------------------------
# Generate semantic repository context
# -----------------------------------------------------------------------------
echo "🧠 Running repository intelligence extraction..."
bash "${ROOT_DIR}/scripts/generate-context.sh"

CONTEXT_DIR="${ROOT_DIR}/context"

FULL_CONTEXT=$(head -c 4000 "${CONTEXT_DIR}/full-context.txt")

ROUTES_CONTEXT=$(head -c 3000 "${CONTEXT_DIR}/routes.txt")
PRISMA_CONTEXT=$(head -c 3000 "${CONTEXT_DIR}/prisma.txt")
FRONTEND_CONTEXT=$(head -c 2000 "${CONTEXT_DIR}/frontend.txt")
AUTH_CONTEXT=$(head -c 1500 "${CONTEXT_DIR}/auth.txt")

# ---------------------------------------------------------------------------
# Read inputs
# ---------------------------------------------------------------------------
PROMPT_TEMPLATE=$(cat "$PROMPT_FILE")
if [[ "$FULL_ANALYSIS" == "true" ]]; then
  echo "📚 FULL ANALYSIS MODE: scanning broader repository context..."

  DIFF_CONTENT=$(find "$ROOT_DIR" \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/dist/*' \
    -type f \
    | head -200)

else
  echo "⚡ Incremental analysis mode..."

  DIFF_CONTENT=$(head -c 5000 "$DIFF_FILE")
fi
COMMIT_MSG=$(cat "$COMMIT_FILE")

if [[ -f "$OUTPUT_FILE" ]]; then
  EXISTING_DOC=$(cat "$OUTPUT_FILE")
else
  EXISTING_DOC=$(cat "$TEMPLATE_FILE")
  echo "ℹ️  No existing architecture.md — using template as base."
fi

# Read full codebase snapshot if available
if [[ -f "${ROOT_DIR}/codebase.txt" ]]; then
  CODEBASE_CONTENT=$(head -c 1000 "${ROOT_DIR}/codebase.txt")
else
  CODEBASE_CONTENT="No codebase snapshot available."
fi

# ---------------------------------------------------------------------------
# Build prompt
# ---------------------------------------------------------------------------
FULL_PROMPT="${PROMPT_TEMPLATE}

=== DETECTED STACK ===
${STACK_HINTS:-No specific stack files detected.}

=== FULL REPOSITORY INTELLIGENCE ===
${FULL_CONTEXT}

=== ROUTES ===
${ROUTES_CONTEXT}

=== DATABASE / PRISMA ===
${PRISMA_CONTEXT}

=== FRONTEND ===
${FRONTEND_CONTEXT}

=== AUTH / SECURITY ===
${AUTH_CONTEXT}

=== COMMIT MESSAGE ===
${COMMIT_MSG}

=== GIT DIFF (changes.diff) ===
${DIFF_CONTENT}

=== EXISTING ARCHITECTURE.md ===
${EXISTING_DOC}
"

ESCAPED_PROMPT=$(printf '%s' "$FULL_PROMPT" \
  | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# ---------------------------------------------------------------------------
# Call Groq API
# ---------------------------------------------------------------------------
echo "🤖 Calling Groq API for architecture.md..."

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

echo "✅ architecture.md updated."

