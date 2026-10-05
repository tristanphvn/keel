#!/usr/bin/env python3
# UserPromptSubmit: when the operator's prompt reads as a correction, tell the lead to fix the mistake and
# record it through the correct skill in the same turn, so it is not repeated. pstack's /correct runs only
# when typed. Patterns favor precision: a bare "bị sai" or "vẫn lỗi" also describes a bug to build, so most
# need a trailing marker such as "rồi" or must open the prompt. Set KEEL_CORRECT=off to silence it.
import json, os, re, sys, unicodedata

TRAIL_VI = r"(rồi|r|rùi|nữa|nha|nhé|đâu|mà|kìa)"
TRAIL_PLAIN = r"(roi|r|rui|nua|nha|nhe|dau|ma|kia)"

CORRECTION_PATTERNS = tuple(re.compile(p, re.IGNORECASE) for p in (
    rf"\bsai {TRAIL_VI}\b",
    r"\bsai (hết|bét|tiếp)\b",
    r"\b(lại|vẫn) sai\b",
    r"\b(bạn|em|anh|mày) (làm|viết|hiểu|trả lời|sửa) sai\b",
    rf"\b(không|chưa|ko|k|hông) (đúng|chuẩn) {TRAIL_VI}\b",
    rf"\b(lại|vẫn|vẫn còn) (bị )?lỗi( y)? (như cũ|{TRAIL_VI})\b",
    rf"\bnhầm {TRAIL_VI}\b",
    r"\b(tái phạm|lặp lại lỗi)\b",
    r"\bđã (bảo|nói|dặn) (rồi|bao nhiêu lần|mà)\b",
    r"\b(không|ko|chưa) phải (vậy|thế|ý (tôi|mình|em|anh)|cái (tôi|mình) (cần|muốn))\b",
    r"\bsao (lại|cứ) (sai|bỏ|quên)\b",
    r"^(không|chưa|ko) đúng\b",
    r"^(lại|vẫn|vẫn còn) (bị )?(lỗi|sai)\b(?! thì)",
    rf"\bsai {TRAIL_PLAIN}\b",
    r"\b(lai|van) sai\b",
    rf"\b(khong|chua|ko|k|hong) (dung|chuan) {TRAIL_PLAIN}\b",
    rf"\b(lai|van|van con) (bi )?loi( y)? (nhu cu|{TRAIL_PLAIN})\b",
    rf"\bnham {TRAIL_PLAIN}\b",
    r"\b(tai pham|lap lai loi)\b",
    r"\bda (bao|noi|dan) (roi|bao nhieu lan|ma)\b",
    r"\b(khong|ko|chua) phai (vay|the|y (toi|minh|em|anh))\b",
    r"^(lai|van|van con) (bi )?(loi|sai)\b(?! thi)",
    r"\b(that'?s|this is|it'?s) (wrong|incorrect|not right)(?![\w-])",
    r"^(wrong|incorrect|nope)\b",
    r"\byou (broke|forgot|ignored)\b",
    r"\bnot what i (asked|wanted|said)\b",
    r"\bi (already )?told you\b",
    r"\b(wrong|broken) again\b",
    r"\bsame (mistake|error|bug) again\b",
))

QUOTED = re.compile(r"```.*?```|`[^`]*`|\"[^\"]*\"|“[^”]*”", re.DOTALL)
NOT_OPERATOR_TEXT = ("<task-notification>", "<system-reminder>", "[SYSTEM NOTIFICATION")


def is_correction(prompt):
    if any(marker in prompt for marker in NOT_OPERATOR_TEXT):
        return False
    text = QUOTED.sub(" ", unicodedata.normalize("NFC", prompt)).strip()
    return any(p.search(text) for p in CORRECTION_PATTERNS)


def main():
    if os.environ.get("KEEL_CORRECT", "on") == "off":
        return
    try:
        prompt = json.loads(sys.stdin.buffer.read().decode("utf-8")).get("prompt")
    except (ValueError, AttributeError):
        return
    if not isinstance(prompt, str) or not is_correction(prompt):
        return
    root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.environ.get("PLUGIN_ROOT")
    skill = os.path.join(root, "skills", "correct", "SKILL.md") if root else "the keel plugin's correct skill"
    context = (
        "keel correct: the operator's message may be a correction. If it corrects your work, fix the mistake first. "
        f"Then, in this same turn, read {skill} and record it as its 'One correction' section says. "
        "In the reply, name what you recorded and where. If the message is not a correction of your work, ignore this."
    )
    json.dump({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": context}}, sys.stdout)


if __name__ == "__main__":
    main()
