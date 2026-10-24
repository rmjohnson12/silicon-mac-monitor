#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
if [[ -d "$HOME/Applications/Silicon.app" ]]; then
    open "$HOME/Applications/Silicon.app"
    exit 0
fi
if [[ ! -d "$PROJECT_DIR/dist/Silicon.app" ]]; then
    "$PROJECT_DIR/scripts/build-app.sh"
fi
open "$PROJECT_DIR/dist/Silicon.app"
