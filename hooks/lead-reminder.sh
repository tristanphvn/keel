#!/bin/sh
# UserPromptSubmit: keep the lead's method sticky across turns, as pstack's `reminder:` frontmatter does for
# poteto-mode in Cursor. Claude Code has no sticky-mode flag, so the reminder is re-injected on every prompt.
# Set KEEL_REMINDER=off to silence it.
[ "${KEEL_REMINDER:-on}" = "off" ] && exit 0
cat >/dev/null
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"keel reminder: if keel:lead is not loaded yet in this session, load it before any tool call, then follow it. The lead gate denies other tools until then. A new task matches a fresh playbook."}}'
