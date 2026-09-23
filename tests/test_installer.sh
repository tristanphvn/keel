#!/usr/bin/env bash
# Destructive boundaries of scripts/install.sh and scripts/uninstall.sh.
#
# These test the promises a user relies on when pointing the installer at a
# directory that already holds their own work: a dry run writes nothing, a
# second run changes nothing, and nothing outside the installer's own manifest
# is ever removed.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

INSTALL="bash $REPO_ROOT/scripts/install.sh"
UNINSTALL="bash $REPO_ROOT/scripts/uninstall.sh"

# A sandbox that already contains user-owned content the installer must respect.
seed_home() {
  _h="$1"
  printf '# my own notes\n\nkeep me exactly\n' > "$_h/CLAUDE.md"
  mkdir -p "$_h/skills/local-only"
  printf -- '---\nname: local-only\n---\nmine\n' > "$_h/skills/local-only/SKILL.md"
  mkdir -p "$_h/rules"
  printf '# not from the repo\n' > "$_h/rules/99-local.md"
}

# --- dry run is inert --------------------------------------------------------
H="$(sandbox_new)"; seed_home "$H"
before="$(tree_fingerprint "$H")"
out="$(AGENT_HOME="$H" $INSTALL 2>&1)"; rc=$?
after="$(tree_fingerprint "$H")"
assert_eq  "dry run exits 0" 0 "$rc"
assert_eq  "dry run mutates nothing at all" "$before" "$after"
assert_contains "dry run announces pending writes" "$out" "NEW"
assert_contains "dry run says it wrote nothing" "$out" "Nothing written"
assert_file_absent "dry run writes no manifest" "$H/.agent-skills/manifest.tsv"

# --- apply -------------------------------------------------------------------
out="$(AGENT_HOME="$H" $INSTALL --apply 2>&1)"; rc=$?
assert_eq "apply exits 0" 0 "$rc"
assert_file_exists "rules installed"   "$H/rules/00-operating-principles.md"
assert_file_exists "registry installed" "$H/skill-registry/registry.yaml"
assert_file_exists "manifest written"  "$H/.agent-skills/manifest.tsv"

assert_same_file "user CLAUDE.md untouched by the installer" \
  "$H/CLAUDE.md" <(printf '# my own notes\n\nkeep me exactly\n')
assert_file_exists "user local-only skill kept" "$H/skills/local-only/SKILL.md"
assert_file_exists "user local rule kept"       "$H/rules/99-local.md"
assert_contains    "local-only content is reported, not deleted" "$out" "LOCAL-ONLY"

leftover="$(grep -rlF '{{AGENT_HOME}}' "$H/rules" "$H/skill-registry" "$H/commands" 2>/dev/null | wc -l)"
assert_eq "no unrendered {{AGENT_HOME}} tokens remain" 0 "$leftover"

# Contract resources must be installed, not only present in the checkout: role
# profiles reference skills by repository-relative path, and those references
# have to resolve on the machine.
assert_file_exists "role catalog installed"   "$H/roles/catalog.json"
assert_file_exists "role profile installed"   "$H/roles/review.json"
assert_file_exists "contract schema installed" "$H/contracts/agent-work.schema.json"
if command -v python3 >/dev/null 2>&1; then
  out="$(python3 "$REPO_ROOT/scripts/routing/render.py" --runtime claude \
           --root "$H" --target "$(sandbox_new)" \
           --config "$REPO_ROOT/config/routing/models.example.yaml" 2>&1)"
  rc=$?
  assert_eq "every role reference still resolves against the installed tree" 0 "$rc"
  assert_contains "…for the whole canonical set" "$out" "14 role(s)"
fi

# --- an installed file the user edited is not overwritten ---------------------
# The manifest records the hash of every file written, and the uninstaller
# already refuses to delete a file whose hash has moved (KEPT (modified since
# install)). The installer did not apply the same test: it compared the
# destination against the rendered source and overwrote on any difference, so a
# customized skill was replaced and the run still exited 0. The hash was written
# every run and then loaded with `cut -f1`, discarding it.
HE="$(sandbox_new)"
AGENT_HOME="$HE" $INSTALL --apply >/dev/null 2>&1
EDITED="$HE/skills/review-code/SKILL.md"
assert_file_exists "a skill is installed to edit" "$EDITED"
printf '\n## Local customization\n\nteam-specific checklist\n' >> "$EDITED"
edited_sum="$(sha256sum < "$EDITED")"
fp="$(tree_fingerprint "$HE")"

out="$(AGENT_HOME="$HE" $INSTALL --apply 2>&1)"; rc=$?
assert_ne "an edited installed file blocks the install" 0 "$rc"
assert_contains "…reported as a conflict"    "$out" "CONFLICT (edited since installed"
assert_contains "…naming the file"           "$out" "review-code"
assert_contains "…and saying nothing was written" "$out" "Nothing was written"
assert_eq "…the edit survives byte for byte" "$edited_sum" "$(sha256sum < "$EDITED")"
# The preflight runs before the backup, so a refused run leaves no new backup
# directory and no manifest rewrite behind.
assert_eq "…and the destination is untouched entirely" "$fp" "$(tree_fingerprint "$HE")"

# A dry run reports the same conflict rather than promising a clean apply.
out="$(AGENT_HOME="$HE" $INSTALL 2>&1)"; rc=$?
assert_ne "a dry run reports it too" 0 "$rc"
assert_contains "…as the same conflict" "$out" "CONFLICT (edited since installed"

# Restoring the file clears the conflict: the check is about the content, not a
# permanent mark against the path.
AGENT_HOME="$HE" $UNINSTALL --apply >/dev/null 2>&1
rm -rf "$HE/skills" "$HE/rules" "$HE/.agent-skills"
out="$(AGENT_HOME="$HE" $INSTALL --apply 2>&1)"; rc=$?
assert_eq "a clean destination installs again" 0 "$rc"
out="$(AGENT_HOME="$HE" $INSTALL --apply 2>&1)"; rc=$?
assert_eq "…and an unedited re-install is not a false positive" 0 "$rc"
assert_not_contains "…with no conflict reported" "$out" "CONFLICT"

# --- repeat installation is predictable --------------------------------------
fp1="$(tree_fingerprint "$H")"
out="$(AGENT_HOME="$H" $INSTALL --apply 2>&1)"
fp2="$(tree_fingerprint "$H")"
assert_contains "second apply reports no changes" "$out" "0 file(s) changed"
# backups/ gains a directory each run by design, so compare everything else.
b1="$(cd "$H" && find . -path ./backups -prune -o -type f -print | LC_ALL=C sort | sha256sum)"
out="$(AGENT_HOME="$H" $INSTALL --apply 2>&1)"
b2="$(cd "$H" && find . -path ./backups -prune -o -type f -print | LC_ALL=C sort | sha256sum)"
assert_eq "repeat installs converge on the same file set" "$b1" "$b2"

# --- a destination path containing spaces ------------------------------------
HS="$(sandbox_new)/config dir with spaces"
mkdir -p "$HS"
out="$(AGENT_HOME="$HS" $INSTALL --apply 2>&1)"; rc=$?
assert_eq "install into a path with spaces exits 0" 0 "$rc"
assert_file_exists "…and actually writes there" "$HS/rules/00-operating-principles.md"
out="$(AGENT_HOME="$HS" $INSTALL --apply 2>&1)"
assert_contains "…and is idempotent there too" "$out" "0 file(s) changed"

# --- uninstall refuses to guess ownership ------------------------------------
HU="$(sandbox_new)"; seed_home "$HU"
out="$(AGENT_HOME="$HU" $UNINSTALL --apply 2>&1)"; rc=$?
assert_ne "uninstall without a manifest fails" 0 "$rc"
assert_contains "…and says why" "$out" "no manifest"
assert_file_exists "…and removes nothing" "$HU/skills/local-only/SKILL.md"

# --- uninstall removes only what it owns -------------------------------------
AGENT_HOME="$HU" $INSTALL --apply >/dev/null 2>&1
printf '\nedited by the user\n' >> "$HU/rules/50-design.md"

before="$(tree_fingerprint "$HU")"
out="$(AGENT_HOME="$HU" $UNINSTALL 2>&1)"; rc=$?
after="$(tree_fingerprint "$HU")"
assert_eq "uninstall dry run exits 0" 0 "$rc"
assert_eq "uninstall dry run mutates nothing" "$before" "$after"

out="$(AGENT_HOME="$HU" $UNINSTALL --apply 2>&1)"; rc=$?
assert_eq "uninstall exits 0" 0 "$rc"
assert_file_absent "installed rule removed"       "$HU/rules/00-operating-principles.md"
assert_file_absent "installed registry removed"   "$HU/skill-registry/registry.yaml"
assert_file_exists "locally modified file kept"   "$HU/rules/50-design.md"
assert_contains    "…and reported as kept"        "$out" "KEPT (modified since install)"
assert_file_exists "user local-only skill kept"   "$HU/skills/local-only/SKILL.md"
assert_file_exists "user local rule kept"         "$HU/rules/99-local.md"
assert_same_file   "user CLAUDE.md still byte-identical" \
  "$HU/CLAUDE.md" <(printf '# my own notes\n\nkeep me exactly\n')

# The removal backup must be complete enough to restore from.
bdir="$(find "$HU/backups" -maxdepth 1 -type d -name 'uninstall-*' | head -1)"
assert_file_exists "uninstall backup contains the removed rule" "$bdir/rules/00-operating-principles.md"

# --- --force is the only way to remove edited files --------------------------
out="$(AGENT_HOME="$HU" $UNINSTALL --force --apply 2>&1)"
assert_file_absent "--force removes the locally modified file" "$HU/rules/50-design.md"
assert_file_exists "…and still keeps unmanaged content"        "$HU/skills/local-only/SKILL.md"

# --- --stale removes only entries the repo no longer ships -------------------
HT="$(sandbox_new)"
AGENT_HOME="$HT" $INSTALL --apply >/dev/null 2>&1
printf 'left over from an older version\n' > "$HT/rules/99-removed-upstream.md"
printf '%s\t%s\n' "$HT/rules/99-removed-upstream.md" \
  "$(sha256sum "$HT/rules/99-removed-upstream.md" | cut -d' ' -f1)" >> "$HT/.agent-skills/manifest.tsv"

out="$(AGENT_HOME="$HT" $UNINSTALL --stale --apply 2>&1)"; rc=$?
assert_eq "--stale exits 0" 0 "$rc"
assert_file_absent "stale file removed"                 "$HT/rules/99-removed-upstream.md"
assert_file_exists "currently shipped file kept"        "$HT/rules/00-operating-principles.md"
assert_file_exists "manifest still present after --stale" "$HT/.agent-skills/manifest.tsv"

t_summary
