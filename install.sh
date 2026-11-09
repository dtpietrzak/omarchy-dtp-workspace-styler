#!/usr/bin/env bash
# Install Workspace Styler in place of the stock workspace widget, with the
# look recorded in settings.json. Safe to run again: a plugin, placement, or
# setting that already matches is left alone.
#
#   ./install.sh

set -euo pipefail

PLUGIN_ID="io.github.sanchokusika.workspace-styler"
PLUGIN_URL="https://github.com/SanchoKusika/omarchy-workspace-styler.git"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$ROOT/settings.json"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID/manifest.json"

fail() {
  echo "install: $*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: install.sh"
  echo "Installs Workspace Styler and applies settings.json."
  exit 0
fi
[[ $# -eq 0 ]] || fail "unknown argument: $1"
[[ -f $SETTINGS ]] || fail "missing $SETTINGS"
[[ -f $SHELL_JSON ]] || fail "$SHELL_JSON must already exist"
command -v jq >/dev/null || fail "jq is required"
command -v omarchy >/dev/null || fail "omarchy is required"
jq -e 'type == "object" and (. | length) > 0' "$SETTINGS" >/dev/null || fail "settings.json must be a non-empty object"

plugin_list() {
  local json
  json="$(omarchy plugin list --json)"
  [[ $json == \[* ]] || fail "omarchy plugin list --json did not return a list"
  printf '%s\n' "$json"
}

# Where the row should sit: beside the menu button, or where the stock
# workspace widget is when the menu button is not on the left.
# Prints "keep", or "put|move <section> after|index <target>".
placement() {
  jq -r --arg id "$PLUGIN_ID" '
    def sections: ["left", "centerBegin", "center", "centerEnd", "tray", "right"];
    def widgets($section): (.bar.layout[$section] // []);
    def find_in($section; $wanted):
      widgets($section)
      | to_entries
      | map(select(.value.id == $wanted))
      | if length == 0 then null else .[0].key end;
    def find_any($wanted):
      [sections[] as $section
        | (find_in($section; $wanted)) as $index
        | select($index != null)
        | {section: $section, index: $index}
      ] | if length == 0 then null else .[0] end;
    (find_in("left"; "dtpietrzak.menu")) as $own_menu
    | (find_in("left"; "omarchy.menu")) as $stock_menu
    | (find_any("omarchy.workspaces")) as $workspaces
    | (find_any($id)) as $self
    | (
        if $own_menu != null then {section: "left", after: "dtpietrzak.menu", index: ($own_menu + 1)}
        elif $stock_menu != null then {section: "left", after: "omarchy.menu", index: ($stock_menu + 1)}
        elif $workspaces != null then {section: $workspaces.section, after: "omarchy.workspaces", index: ($workspaces.index + 1)}
        else {section: "left", after: "", index: 0}
        end
      ) as $want
    | (if $self == null then "put"
        elif $self.section == $want.section and $self.index == $want.index then "keep"
        else "move"
        end) as $op
    | if $op == "keep" then "keep"
      elif $want.after != "" then "\($op)\t\($want.section)\tafter\t\($want.after)"
      else "\($op)\t\($want.section)\tindex\t\($want.index)"
      end
  ' "$SHELL_JSON"
}

if [[ -f $DEST ]]; then
  echo "Plugin $PLUGIN_ID is already installed"
else
  omarchy plugin add "$PLUGIN_URL" --yes
fi

ready=0
for attempt in $(seq 1 40); do
  if plugin_list | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null; then
    ready=1
    break
  fi
  if [[ $attempt -eq 1 ]]; then
    omarchy-shell shell rescanPlugins >/dev/null || true
  fi
  sleep 0.05
done
[[ $ready -eq 1 ]] || fail "plugin $PLUGIN_ID was not discovered"

place="$(placement)"
IFS=$'\t' read -r op section how target <<<"$place"
case "$op" in
  keep)
    echo "Workspace Styler is already in place"
    ;;
  put | move)
    [[ -n $section && -n $how && -n $target ]] || fail "could not decide where to put Workspace Styler"
    args=(--section "$section")
    if [[ $how == after ]]; then
      args+=(--after "$target")
    elif [[ $how == index ]]; then
      args+=(--index "$target")
    else
      fail "unknown placement: $place"
    fi
    if [[ $op == put ]]; then
      omarchy bar put "$PLUGIN_ID" "${args[@]}"
    else
      omarchy bar move "$PLUGIN_ID" "${args[@]}"
    fi
    [[ "$(placement)" == keep ]] || fail "Workspace Styler did not land in its place"
    ;;
  *)
    fail "unknown placement: $place"
    ;;
esac

if plugin_list | jq -e 'any(.[]; .id == "omarchy.workspaces" and .enabled)' >/dev/null; then
  omarchy plugin disable omarchy.workspaces
  echo "Turned off the stock workspace widget"
else
  echo "Stock workspace widget is already off"
fi

changed=0
while IFS= read -r key; do
  desired="$(jq -c --arg key "$key" '.[$key]' "$SETTINGS")"
  # `//` would treat false as missing, and layoutGlyph is saved as false.
  current="$(jq -c --arg id "$PLUGIN_ID" --arg key "$key" '
    [ .bar.layout[][]? | select(.id == $id) | .[$key] ] | if length == 0 then null else .[0] end
  ' "$SHELL_JSON")"
  if jq -e -n --argjson want "$desired" --argjson got "$current" '$want == $got' >/dev/null; then
    continue
  fi
  omarchy bar set "$PLUGIN_ID" "$key" "$desired" --json
  changed=1
done < <(jq -r 'keys_unsorted[]' "$SETTINGS")

if [[ $changed -eq 0 ]]; then
  echo "Workspace Styler settings already match"
else
  echo "Applied Workspace Styler settings"
fi
