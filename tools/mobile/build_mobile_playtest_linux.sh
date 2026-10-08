#!/usr/bin/env bash
# Development-only Linux export. Never builds against the Windows .godot cache.
set -euo pipefail
source_project=$1
output_directory=$2
template_directory=$3
workspace_key=$4
godot=/opt/fishing-mobile/Godot_v4.7.2-stable_linux.x86_64
if [[ ! -x "$godot" ]] || [[ $("$godot" --version) != 4.7.2.stable.* ]]; then
    echo 'Godot 4.7.2 Linux is not installed in /opt/fishing-mobile.' >&2
    exit 1
fi
workspace="$HOME/.cache/fishing-mobile/$workspace_key"
mkdir -p "$workspace/project" "$workspace/export" "$HOME/.local/share/godot/export_templates/4.7.2.stable"
# Delete only inside this dedicated mirror; preserve the Linux import cache.
rsync -a --delete --exclude=.git/ --exclude=.godot/ --exclude=export/ \
    --exclude=build/ --exclude=android/ "$source_project/" "$workspace/project/"
rsync -a "$template_directory/" "$HOME/.local/share/godot/export_templates/4.7.2.stable/"
if ! "$godot" --headless --path "$workspace/project" --editor --import \
    --log-file "$workspace/import.log" > "$workspace/import.stdout.log" 2>&1; then
    tail -n 40 "$workspace/import.stdout.log" >&2
    exit 1
fi
if ! "$godot" --headless --path "$workspace/project" \
    --export-debug 'Mobile Portrait Web Playtest' "$workspace/export/index.html" \
    --log-file "$workspace/export.log" > "$workspace/export.stdout.log" 2>&1; then
    tail -n 40 "$workspace/export.stdout.log" >&2
    exit 1
fi
echo "Linux build logs: $workspace/import.log and $workspace/export.log"
mkdir -p "$output_directory"
# Copy generated artifacts intact; PowerShell validates before publishing.
cp "$workspace/export/"index.* "$output_directory/"
