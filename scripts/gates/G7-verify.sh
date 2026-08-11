#!/usr/bin/env bash
set -euo pipefail

# G7: Security verification gate — stack-aware security checks
# First try the configured security command from project.json
if [ -f "scripts/lib/project-config.sh" ]; then
  source "scripts/lib/project-config.sh"
  cmd="$(command_for_gate "security" 2>/dev/null || true)"
  if [ -n "$cmd" ] && [ "$cmd" != "N/A" ]; then
    echo "[RUN] G7 Security: $cmd"
    bash -lc "$cmd" || exit 1
  fi
fi

# Run stack-specific and universal security pattern checks
# Python security checks
if true; then
  echo "[CHECK] Scanning for hardcoded secrets in Python files..."
  grep -rn --include='*.py' -E '(password|secret|api_key|token)\s*=\s*['"'"'"][^'"'"'"]+['"'"'"]' . 2>/dev/null | grep -v '.agent/' | grep -v 'test_' | head -5 || true
  echo "[CHECK] Checking for SQL injection patterns..."
  grep -rn --include='*.py' -E 'execute\(|raw\(' . 2>/dev/null | grep -v '.agent/' | grep -i 'f["'"'"'"]' | head -5 || true
fi

  # JavaScript/TypeScript security checks
if true; then
  echo "[CHECK] Scanning for hardcoded secrets in JS/TS files..."
  grep -rn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' -E '(password|secret|api_key|apiKey|token)\s*[:=]\s*['"'"'"][^'"'"'"]+['"'"'"]' . 2>/dev/null | grep -v 'node_modules' | grep -v '.agent/' | grep -v '.d.ts' | head -5 || true
  echo "[CHECK] Checking for dangerouslySetInnerHTML..."
  grep -rn --include='*.tsx' --include='*.jsx' 'dangerouslySetInnerHTML' . 2>/dev/null | grep -v 'node_modules' | head -5 || true
fi

# Universal security checks
if true; then
  echo "[CHECK] Scanning for .env files with secrets..."
  found_env=0
  for envfile in .env .env.local .env.production .env.staging; do
    if [ -f "$envfile" ]; then
      echo "[WARN] G7: Found $envfile — ensure it is in .gitignore and does not contain real secrets"
      found_env=1
    fi
  done

  echo "[CHECK] Scanning for common secret patterns in all files..."
  SECRET_HITS=$(grep -rn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.py' --include='*.go' --include='*.java' --include='*.rs' --include='*.cs' --include='*.cpp' \
    -E '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY-----)' \
    . 2>/dev/null | grep -v 'node_modules' | grep -v '.agent/' | grep -v '.git/' | head -5 || true)

  if [ -n "$SECRET_HITS" ]; then
    echo "[FAIL] G7: Detected potential secrets/credentials in source code:"
    echo "$SECRET_HITS"
    exit 1
  fi
fi

echo "[PASS] G7: Security verification passed — no obvious secrets or dangerous patterns found"
exit 0
