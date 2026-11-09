#!/usr/bin/env bash
# The installer adds the upstream plugin once, places it beside the menu,
# turns the stock workspace widget off, applies settings.json, and is quiet
# when run again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_ID="io.github.sanchokusika.workspace-styler"
fail() {
  echo "not ok - $*" >&2
  exit 1
}

jq -e '
  .style == "numbers" and .accent == true and .persistent == 7
  and .wormLag == 0.7 and .effect == "comet" and .layoutGlyph == false
' "$ROOT/settings.json" >/dev/null || fail "settings.json is not the saved setup"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir"
mkdir -p "$HOME/.config/omarchy" "$tmpdir/bin"

cat >"$tmpdir/bin/omarchy-shell" <<'SH'
#!/bin/sh
exit 0
SH

cat >"$tmpdir/bin/omarchy" <<'PY'
#!/usr/bin/env python3
import json
import sys
from pathlib import Path

home = Path.home()
plugin_id = "io.github.sanchokusika.workspace-styler"
plugin_url = "https://github.com/SanchoKusika/omarchy-workspace-styler.git"
log = home / ".omarchy-log"
shell_path = home / ".config/omarchy/shell.json"
installed_path = home / ".installed"
args = sys.argv[1:]
with log.open("a") as handle:
    handle.write(" ".join(args) + "\n")

def load_shell():
    return json.loads(shell_path.read_text())

def save_shell(data):
    shell_path.write_text(json.dumps(data, indent=2) + "\n")

def bar(data):
    return data.setdefault("bar", {}).setdefault("layout", {})

def find(data, wanted):
    for section, widgets in bar(data).items():
        if not isinstance(widgets, list):
            continue
        for index, widget in enumerate(widgets):
            if isinstance(widget, dict) and widget.get("id") == wanted:
                return section, index
    return None

def installed_ids():
    extra = installed_path.read_text().split() if installed_path.exists() else []
    seen = []
    for plugin in ["omarchy.menu", "omarchy.workspaces", "dtpietrzak.menu", *extra]:
        if plugin not in seen:
            seen.append(plugin)
    return seen

def parse_place(rest, data):
    section = None
    after = None
    index = None
    tokens = iter(rest)
    for token in tokens:
        if token == "--section":
            section = next(tokens)
        elif token == "--after":
            after = next(tokens)
        elif token == "--index":
            index = int(next(tokens))
        elif token == "--json":
            continue
        else:
            raise SystemExit(f"bad placement token {token}")
    if after:
        loc = find(data, after)
        if loc is None or (section and loc[0] != section):
            raise SystemExit(f"missing anchor {after}")
        return loc[0], loc[1] + 1
    return section or "left", 0 if index is None else index

if args[:2] == ["plugin", "list"]:
    data = load_shell()
    print(json.dumps([
        {"id": plugin, "enabled": find(data, plugin) is not None}
        for plugin in installed_ids()
    ]))
elif args[:2] == ["plugin", "add"]:
    url = next(token for token in args[2:] if not token.startswith("--"))
    if url != plugin_url:
        raise SystemExit(f"unexpected url {url}")
    ids = installed_path.read_text().split() if installed_path.exists() else []
    if plugin_id in ids:
        raise SystemExit("already installed")
    ids.append(plugin_id)
    installed_path.write_text("\n".join(ids) + "\n")
    manifest = home / ".config/omarchy/plugins" / plugin_id
    manifest.mkdir(parents=True, exist_ok=True)
    (manifest / "manifest.json").write_text("{}\n")
    print(f"Added {plugin_id}")
elif args[:2] == ["plugin", "disable"]:
    target = args[2]
    data = load_shell()
    loc = find(data, target)
    if loc:
        section, index = loc
        bar(data)[section].pop(index)
        save_shell(data)
    print(f"Disabled {target}")
elif args[:2] == ["bar", "put"]:
    target = args[2]
    data = load_shell()
    if find(data, target) is None:
        section, index = parse_place(args[3:], data)
        bar(data).setdefault(section, []).insert(index, {"id": target})
        save_shell(data)
    print(f"{target} is on the bar")
elif args[:2] == ["bar", "move"]:
    target = args[2]
    data = load_shell()
    loc = find(data, target)
    if loc is None:
        raise SystemExit(f"cannot move {target}")
    entry = bar(data)[loc[0]].pop(loc[1])
    section, index = parse_place(args[3:], data)
    bar(data).setdefault(section, []).insert(index, entry)
    save_shell(data)
    print(f"Moved {target}")
elif args[:2] == ["bar", "set"]:
    target, key, value = args[2], args[3], args[4]
    if "--json" not in args[5:]:
        raise SystemExit("set was not passed --json")
    data = load_shell()
    loc = find(data, target)
    if loc is None:
        raise SystemExit(f"cannot set {target}")
    bar(data)[loc[0]][loc[1]][key] = json.loads(value)
    save_shell(data)
    print(f"Set {key} on {target}")
else:
    raise SystemExit("unhandled: " + " ".join(args))
PY
chmod +x "$tmpdir/bin/omarchy" "$tmpdir/bin/omarchy-shell"
export PATH="$tmpdir/bin:$PATH"

SHELL_JSON="$HOME/.config/omarchy/shell.json"
mutations() {
  grep -E '^(plugin add|plugin disable|bar put|bar move|bar set) ' "$HOME/.omarchy-log" || true
}

widget() {
  jq -c --arg id "$PLUGIN_ID" 'first(.bar.layout[][] | select(.id == $id))' "$SHELL_JSON"
}

write_shell() {
  printf '%s\n' "$1" >"$SHELL_JSON"
}

expect_settings() {
  widget | jq -e '
    .style == "numbers" and .accent == true and .persistent == 7
    and .wormLag == 0.7 and .effect == "comet" and .layoutGlyph == false
  ' >/dev/null || fail "$1: settings were not applied: $(widget)"
}

# Stock bar: menu, then the workspace widget.
write_shell '{
  "version": 1,
  "bar": {"layout": {"left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"}]}}
}'
: >"$HOME/.omarchy-log"
"$ROOT/install.sh" >/dev/null
[[ "$(jq -c '.bar.layout.left | map(.id)' "$SHELL_JSON")" == '["omarchy.menu","'"$PLUGIN_ID"'"]' ]] \
  || fail "stock bar: row was not placed after the menu: $(jq -c '.bar.layout.left' "$SHELL_JSON")"
expect_settings "stock bar"
grep -q '^plugin add ' "$HOME/.omarchy-log" || fail "stock bar: plugin was not added"
grep -q '^plugin disable omarchy.workspaces$' "$HOME/.omarchy-log" || fail "stock bar: stock widget stayed on"
rm -f "$HOME/.omarchy-log"
"$ROOT/install.sh" >/dev/null
[[ -z "$(mutations)" ]] || fail "stock bar: second run changed something: $(mutations)"

# The personal menu button wins over the stock one.
write_shell '{
  "version": 1,
  "bar": {"layout": {"left": [{"id": "dtpietrzak.menu"}, {"id": "omarchy.workspaces"}]}}
}'
rm -f "$HOME/.installed" "$HOME/.config/omarchy/plugins/$PLUGIN_ID/manifest.json"
: >"$HOME/.omarchy-log"
"$ROOT/install.sh" >/dev/null
[[ "$(jq -c '.bar.layout.left | map(.id)' "$SHELL_JSON")" == '["dtpietrzak.menu","'"$PLUGIN_ID"'"]' ]] \
  || fail "own menu: row was not placed after dtpietrzak.menu"
grep -q -- '--after dtpietrzak.menu' "$HOME/.omarchy-log" || fail "own menu: did not anchor on dtpietrzak.menu"

# No menu button: take the stock workspace widget's spot.
write_shell '{
  "version": 1,
  "bar": {"layout": {"left": [{"id": "omarchy.workspaces"}]}}
}'
rm -f "$HOME/.installed" "$HOME/.config/omarchy/plugins/$PLUGIN_ID/manifest.json"
: >"$HOME/.omarchy-log"
"$ROOT/install.sh" >/dev/null
[[ "$(jq -c '.bar.layout.left | map(.id)' "$SHELL_JSON")" == '["'"$PLUGIN_ID"'"]' ]] \
  || fail "workspaces only: stock widget was not replaced"
expect_settings "workspaces only"

# Already on the bar, but on the wrong side of the stock widget, and unconfigured.
write_shell '{
  "version": 1,
  "bar": {"layout": {"left": [
    {"id": "dtpietrzak.menu"},
    {"id": "omarchy.workspaces"},
    {"id": "'"$PLUGIN_ID"'"}
  ]}}
}'
mkdir -p "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
echo '{}' >"$HOME/.config/omarchy/plugins/$PLUGIN_ID/manifest.json"
printf '%s\n' "$PLUGIN_ID" >"$HOME/.installed"
: >"$HOME/.omarchy-log"
"$ROOT/install.sh" >/dev/null
[[ "$(jq -c '.bar.layout.left | map(.id)' "$SHELL_JSON")" == '["dtpietrzak.menu","'"$PLUGIN_ID"'"]' ]] \
  || fail "wrong place: row was not moved beside the menu"
expect_settings "wrong place"
grep -q '^plugin add ' "$HOME/.omarchy-log" && fail "wrong place: added a plugin that was already installed"
grep -q '^bar move ' "$HOME/.omarchy-log" || fail "wrong place: did not move the row"

echo "ok"
