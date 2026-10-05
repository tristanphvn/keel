#!/usr/bin/env python3
# UserPromptSubmit: when the operator's prompt reads as a correction, tell the lead to fix the mistake and
# record it through the correct skill in the same turn, so it is not repeated. pstack's /correct runs only
# when typed. Set KEEL_CORRECT=off to silence it.
import json, os, re, sys

CORRECTION_PATTERNS = tuple(re.compile(p, re.IGNORECASE) for p in (
    r"\bsai (rồi|nữa|hết|bét|tiếp)\b",
    r"\b(bị|làm|lại|vẫn|còn|đều) sai\b",
    r"\b(không|chưa|ko|hông) (đúng|chuẩn) (rồi|nha|nhé|đâu|mà)\b",
    r"\b(lại|vẫn|còn) (bị )?lỗi\b",
    r"\bnhầm (rồi|nữa)\b",
    r"\b(tái phạm|lặp lại lỗi)\b",
    r"\bđã (bảo|nói|dặn) (rồi|là|bao nhiêu)\b",
    r"\bsao (lại|cứ) (làm|sai|bỏ|quên)\b",
    r"\b(sai|nham) roi\b",
    r"\b(lai|van|bi) sai\b",
    r"\btai pham\b",
    r"\b(that'?s|this is|it'?s) (wrong|incorrect|not right)\b",
    r"\byou (broke|missed|forgot|ignored)\b",
    r"\bnot what i (asked|wanted|said)\b",
    r"\bi (already )?(told|asked) you\b",
    r"\b(wrong|broken) again\b",
    r"\bstop doing\b",
))


def is_correction(prompt):
    return any(p.search(prompt) for p in CORRECTION_PATTERNS)


def main():
    if os.environ.get("KEEL_CORRECT", "on") == "off":
        return
    try:
        prompt = json.loads(sys.stdin.buffer.read().decode("utf-8")).get("prompt") or ""
    except (ValueError, AttributeError):
        return
    if not is_correction(prompt):
        return
    root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    skill = os.path.join(root, "skills", "correct", "SKILL.md") if root else "the keel correct skill (skills/correct/SKILL.md)"
    context = (
        "keel correct: the operator's message reads as a correction. Fix the mistake first. Then, in this same turn, "
        f"read {skill} and record it as its 'One correction' section says. In the reply, name what you recorded and where. "
        "If the message is not a correction of your work, ignore this."
    )
    json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": context}}, sys.stdout)


if __name__ == "__main__":
    main()
