#!/usr/bin/env bash
set -euo pipefail

profile="${1:-default}"
include_optional=0
if [ "${2:-}" = "--include-optional" ]; then
  include_optional=1
fi

config=".agent/project.json"
if [ ! -f "$config" ]; then
  echo "[FAIL] missing $config" >&2
  exit 1
fi

node - "$profile" <<'NODE'
const fs = require('fs')
const profileId = process.argv[2] || 'default'
const data = JSON.parse(fs.readFileSync('.agent/project.json', 'utf8'))
if (!data.verification_profiles || !data.verification_profiles[profileId]) {
  console.error('[FAIL] unknown verification profile: ' + profileId)
  process.exit(2)
}
NODE

failures=0
while IFS=$'\t' read -r requirement service_id service_dir check_key command; do
  if [ -z "${service_id:-}" ]; then
    continue
  fi

  if [ -z "${command:-}" ] || [[ "$command" == echo* ]]; then
    echo "[WARN] $requirement $service_id/$check_key has no executable command"
    if [ "$requirement" = "required" ]; then
      failures=$((failures + 1))
    fi
    continue
  fi

  if [ ! -d "$service_dir" ]; then
    echo "[FAIL] service directory missing: $service_id -> $service_dir"
    failures=$((failures + 1))
    continue
  fi

  echo "[RUN] $requirement $service_id/$check_key: $command"
  (cd "$service_dir" && bash -lc "$command") || failures=$((failures + 1))
done < <(node - "$profile" "$include_optional" <<'NODE'
const fs = require('fs')
const profileId = process.argv[2] || 'default'
const includeOptional = process.argv[3] === '1'
const data = JSON.parse(fs.readFileSync('.agent/project.json', 'utf8'))
const profiles = data.verification_profiles || {}
const profile = profiles[profileId]
if (!profile) {
  console.error('[FAIL] unknown verification profile: ' + profileId)
  process.exit(2)
}
const services = new Map((data.service_matrix || []).map((service) => [service.id, service]))
const serviceIds = profile.services && profile.services.length
  ? profile.services
  : (data.service_matrix || []).filter((service) => service.default).map((service) => service.id)
const checks = [
  ...(profile.required || []).map((key) => ['required', key]),
  ...(includeOptional ? (profile.optional || []).map((key) => ['optional', key]) : []),
]
for (const serviceId of serviceIds) {
  const service = services.get(serviceId)
  if (!service) {
    console.log(['required', serviceId, '.', 'service', ''].join('\t'))
    continue
  }
  for (const [requirement, key] of checks) {
    const command = (service.commands && service.commands[key]) || (data.commands && data.commands[key]) || ''
    console.log([requirement, service.id, service.directory || '.', key, command].join('\t'))
  }
}
NODE
)

if [ "$failures" -gt 0 ]; then
  echo "[FAIL] verification profile '$profile' failed: $failures failure(s)"
  exit 1
fi

echo "[OK] verification profile '$profile' passed"
