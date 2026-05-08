# =============================================================================
# scripts/generate-context.sh
# Central repository intelligence extractor
# =============================================================================

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_DIR="${ROOT_DIR}/context"

mkdir -p "$CONTEXT_DIR"

echo "🧠 Generating repository intelligence context..."

# -----------------------------------------------------------------------------
# Structure
# -----------------------------------------------------------------------------
{
  echo "=== PROJECT STRUCTURE ==="
  find "$ROOT_DIR" \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/coverage/*' \
    -not -path '*/context/*' \
    -maxdepth 4 \
    | sed "s|${ROOT_DIR}/||" \
    | sort
} > "${CONTEXT_DIR}/structure.txt"

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------
{
  echo "=== PACKAGE.JSON ==="
  find "$ROOT_DIR" -name "package.json" \
    -not -path '*/node_modules/*' \
    -exec sh -c '
      for file do
        echo ""
        echo "FILE: $file"
        cat "$file"
      done
    ' sh {} +

  echo ""
  echo "=== PYTHON REQUIREMENTS ==="
  find "$ROOT_DIR" \( -name "requirements.txt" -o -name "pyproject.toml" \) \
    -exec sh -c '
      for file do
        echo ""
        echo "FILE: $file"
        cat "$file"
      done
    ' sh {} +
} > "${CONTEXT_DIR}/dependencies.txt"

# -----------------------------------------------------------------------------
# Prisma / Database Schema
# -----------------------------------------------------------------------------
{
  echo "=== DATABASE SCHEMA ==="

  find "$ROOT_DIR" \( -name "schema.prisma" -o -name "*.sql" \) \
    -exec sh -c '
      for file do
        echo ""
        echo "FILE: $file"
        cat "$file"
      done
    ' sh {} +
} > "${CONTEXT_DIR}/prisma.txt"

# -----------------------------------------------------------------------------
# Routes
# -----------------------------------------------------------------------------
{
  echo "=== EXPRESS / API ROUTES ==="

  grep -R \
    --include="*.js" \
    --include="*.ts" \
    --include="*.jsx" \
    --include="*.tsx" \
    -E "router\.|app\.get|app\.post|app\.put|app\.delete|Route\(" \
    "$ROOT_DIR" \
    2>/dev/null || true
} > "${CONTEXT_DIR}/routes.txt"

# -----------------------------------------------------------------------------
# Controllers / Services
# -----------------------------------------------------------------------------
{
  echo "=== CONTROLLERS / SERVICES ==="

  find "$ROOT_DIR" \
    \( -iname "*controller*" -o -iname "*service*" \) \
    \( -name "*.js" -o -name "*.ts" \) \
    -exec sh -c '
      for file do
        echo ""
        echo "=================================================="
        echo "FILE: $file"
        echo "=================================================="
        head -120 "$file"
      done
    ' sh {} +
} > "${CONTEXT_DIR}/controllers.txt"

# -----------------------------------------------------------------------------
# Frontend Intelligence
# -----------------------------------------------------------------------------
{
  echo "=== FRONTEND COMPONENTS / PAGES ==="

  find "$ROOT_DIR" \
    \( -path "*/src/*" -o -path "*/pages/*" \) \
    \( -name "*.jsx" -o -name "*.tsx" -o -name "*.js" -o -name "*.ts" \) \
    -exec sh -c '
      for file do
        echo ""
        echo "=================================================="
        echo "FILE: $file"
        echo "=================================================="
        head -80 "$file"
      done
    ' sh {} +
} > "${CONTEXT_DIR}/frontend.txt"

# -----------------------------------------------------------------------------
# Auth / Security Detection
# -----------------------------------------------------------------------------
{
  echo "=== AUTH / SECURITY ==="

  grep -R \
    -E "jwt|bcrypt|passport|authMiddleware|verifyToken|session|cookie" \
    "$ROOT_DIR" \
    --include="*.js" \
    --include="*.ts" \
    2>/dev/null || true
} > "${CONTEXT_DIR}/auth.txt"

# -----------------------------------------------------------------------------
# Docker / Infra
# -----------------------------------------------------------------------------
{
  echo "=== INFRASTRUCTURE ==="

  find "$ROOT_DIR" \
    \( -name "Dockerfile" -o -name "docker-compose.yml" -o -name "*.yml" \) \
    -exec sh -c '
      for file do
        echo ""
        echo "FILE: $file"
        head -120 "$file"
      done
    ' sh {} +
} > "${CONTEXT_DIR}/infra.txt"

# -----------------------------------------------------------------------------
# Generate merged intelligence snapshot
# -----------------------------------------------------------------------------
cat \
  "${CONTEXT_DIR}/structure.txt" \
  "${CONTEXT_DIR}/dependencies.txt" \
  "${CONTEXT_DIR}/prisma.txt" \
  "${CONTEXT_DIR}/routes.txt" \
  "${CONTEXT_DIR}/controllers.txt" \
  "${CONTEXT_DIR}/frontend.txt" \
  "${CONTEXT_DIR}/auth.txt" \
  "${CONTEXT_DIR}/infra.txt" \
  > "${CONTEXT_DIR}/full-context.txt"

echo "✅ Context generation complete."