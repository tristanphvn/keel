#!/usr/bin/env bash
# Managed directory links, shared by the runtime adapters.
#
# A runtime discovers skills at a fixed path. When the skills tree is installed
# somewhere else, an adapter links each skill directory into that path. These
# links are the only thing an adapter creates outside its managed block, so they
# are tracked in a manifest and removed only while they still resolve to the
# target recorded there.
#
# Requires lib/common.sh to be sourced first.

# as_links_link SRC VIEW MANIFEST APPLY
# One link per immediate subdirectory of SRC, created inside VIEW.
# Never overwrites: an existing file, directory or foreign link is a collision,
# reported and skipped. Returns non-zero if anything collided or failed.
as_links_link() {
  _src="$1"; _view="$2"; _manifest="$3"; _apply="$4"
  [ -d "$_src" ] || { echo "FATAL: $_src does not exist" >&2; return 1; }
  mkdir -p "$_view" 2>/dev/null || true

  # Measured, not assumed: on Windows without Developer Mode, MSYS `ln -s`
  # reports success and silently DEEP-COPIES the directory. A copy recorded as a
  # managed link can never be cleaned up again, and drifts from its source.
  _mech="$(as_link_support "$_view")"
  echo "  link mechanism: $_mech"
  if [ "$_mech" = none ]; then
    cat >&2 <<MSG

FATAL: this host cannot create directory links in $_view.
  POSIX symlinks are unavailable (on Windows they need Developer Mode or the
  SeCreateSymbolicLinkPrivilege) and no directory junction could be created.

Supported fallback — install the skills where the runtime already looks and skip
linking entirely; see docs/runtime-capabilities.md.
MSG
    return 1
  fi

  _collisions=0; _planned=""
  for _d in "$_src"/*/; do
    [ -d "$_d" ] || continue
    _name="$(basename "$_d")"
    _link="$_view/$_name"
    _tgt="${_d%/}"

    if [ -L "$_link" ]; then
      if as_link_points_at "$_link" "$_tgt"; then
        echo "  ok       $_name (already linked)"
        _planned="$_planned$_link	$_tgt
"
        continue
      fi
      echo "  COLLISION $_link is a link to $(readlink "$_link") — not overwriting"
      _collisions=$((_collisions + 1)); continue
    fi
    if [ -e "$_link" ]; then
      echo "  COLLISION $_link already exists ($([ -d "$_link" ] && echo directory || echo file)) — not overwriting"
      _collisions=$((_collisions + 1)); continue
    fi

    echo "  LINK     $_name -> $_tgt"
    if [ "$_apply" -eq 1 ]; then
      if as_make_link "$_mech" "$_tgt" "$_link"; then
        _planned="$_planned$_link	$_tgt
"
      else
        # Clear whatever a failed attempt left behind — notably a silent copy.
        [ -L "$_link" ] || rm -rf "$_link" 2>/dev/null
        echo "  FAILED   $_link"; _collisions=$((_collisions + 1))
      fi
    else
      _planned="$_planned$_link	$_tgt
"
    fi
  done

  if [ "$_apply" -eq 1 ]; then
    mkdir -p "$(dirname "$_manifest")" 2>/dev/null
    printf '%s' "$_planned" > "$_manifest"
    echo "  manifest written: $_manifest"
  fi

  [ "$_collisions" -eq 0 ]
}

# as_links_unlink MANIFEST APPLY
# Removes only entries that still resolve to their recorded target. Anything
# else is left in place AND left in the manifest: dropping it would orphan the
# link, with nothing on disk recording that an adapter created it.
as_links_unlink() {
  _manifest="$1"; _apply="$2"
  [ -f "$_manifest" ] || { echo "  no manifest at $_manifest; nothing was linked by this adapter."; return 0; }
  _n=0; _kept=""
  while IFS="$(printf '\t')" read -r _link _target; do
    [ -z "${_link:-}" ] && continue
    if as_link_points_at "$_link" "$_target"; then
      echo "  UNLINK $_link"
      [ "$_apply" -eq 1 ] && rm -f "$_link"
      _n=$((_n + 1))
    else
      echo "  skip (not our link any more) $_link"
      _kept="$_kept$_link	$_target
"
    fi
  done < "$_manifest"

  if [ "$_apply" -eq 1 ]; then
    if [ -n "$_kept" ]; then
      printf '%s' "$_kept" > "$_manifest"
      echo "  manifest kept with $(grep -c . "$_manifest") unresolved entry(ies): $_manifest"
    else
      rm -f "$_manifest"
    fi
  fi
  AS_LINKS_REMOVED="$_n"
  AS_LINKS_KEPT="$_kept"
  return 0
}

# as_links_check MANIFEST — prints one line per broken entry, returns the count.
as_links_check() {
  _manifest="$1"
  [ -f "$_manifest" ] || return 0
  _bad=0; _ok=0
  while IFS="$(printf '\t')" read -r _link _target; do
    [ -z "${_link:-}" ] && continue
    if as_link_points_at "$_link" "$_target" && [ -f "$_link/SKILL.md" ]; then
      _ok=$((_ok + 1))
    else
      _bad=$((_bad + 1)); echo "  FAIL  broken managed link: $_link"
    fi
  done < "$_manifest"
  AS_LINKS_OK="$_ok"
  return "$_bad"
}
