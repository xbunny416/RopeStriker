#!/usr/bin/env bash
# One-command quality gate: strict type check (legacy + new Luau solver), lint,
# formatting, unit/integration tests and a place build.
#
#   ./scripts/validate.sh            # everything
#   SKIP_BUILD=1 ./scripts/validate.sh
#
# Requires the tools in rokit.toml on PATH (`rokit install`).
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLING=.tooling
DEFS="$TOOLING/globalTypes.None.d.luau"
DEFS_URL="https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau"
mkdir -p "$TOOLING"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }

step "Rojo sourcemap"
rojo sourcemap default.project.json --include-non-scripts -o sourcemap.json

if [ ! -s "$DEFS" ]; then
	step "Downloading Roblox type definitions"
	curl -fsSL "$DEFS_URL" -o "$DEFS"
fi

analyze() {
	luau-lsp analyze "$@" \
		--definitions="@roblox=$DEFS" \
		--sourcemap=sourcemap.json \
		--base-luaurc=.luaurc \
		--ignore="**/Packages/**" \
		--platform=roblox \
		src
}

step "Type check (--!strict, legacy solver)"
analyze
step "Type check (--!strict, new solver)"
analyze --flag:LuauSolverV2=true

step "Lint (selene)"
selene src

step "Format (stylua --check)"
stylua --check src tests

step "Tests (lune)"
lune run tests/run.luau

if [ -z "${SKIP_BUILD:-}" ]; then
	step "Build place (rojo)"
	mkdir -p build
	rojo build default.project.json -o build/ChronoRope.rbxlx
fi

printf '\n\033[1;32mAll checks passed.\033[0m\n'
