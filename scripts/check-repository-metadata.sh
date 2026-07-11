#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_executable() {
  require_file "$1"
  if [[ ! -x "$1" ]]; then
    echo "Expected executable file: $1" >&2
    exit 1
  fi
}

require_tool ruby

required_files=(
  ".editorconfig"
  ".gitattributes"
  ".gitignore"
  ".swift-format"
  ".github/workflows/ci.yml"
  ".github/ISSUE_TEMPLATE/bug_report.yml"
  ".github/ISSUE_TEMPLATE/config.yml"
  ".github/ISSUE_TEMPLATE/feature_request.yml"
  ".github/ISSUE_TEMPLATE/security_contact.yml"
  ".github/pull_request_template.md"
  "CONTRIBUTING.md"
  "README.md"
  "SECURITY.md"
)

for path in "${required_files[@]}"; do
  require_file "$path"
done

ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path); puts "YAML OK #{path}" }' \
  .github/workflows/ci.yml \
  .github/ISSUE_TEMPLATE/*.yml

required_executables=(
  "scripts/check-format.sh"
  "scripts/check-swiftui-appkit-boundaries.sh"
  "scripts/check-swiftui-background-tasks.sh"
  "scripts/check-swiftui-main-thread-io.sh"
  "scripts/check-swiftui-store-boundaries.sh"
  "scripts/Install MacAlarm.command"
  "scripts/package-release.sh"
  "scripts/run-viewer-debug.sh"
  "scripts/Uninstall MacAlarm.command"
  "scripts/verify-release.sh"
  "scripts/check-repository-metadata.sh"
)

for path in "${required_executables[@]}"; do
  require_executable "$path"
done

echo "Repository metadata checks passed."
