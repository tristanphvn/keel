---
description: Dựng (hoặc cập nhật) vault knowledge cho repo hiện tại ở E:\vault\<project-slug>\ theo đúng convention chung
argument-hint: "[project-slug] (tuỳ chọn — mặc định suy ra từ tên repo)"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# /setup-vault

Dựng vault cho repo đang mở. Slug: `$1` nếu có, không thì suy ra từ tên thư mục repo (kebab-case, giữ tiền tố khách hàng: `WanQol-WEB-PUSH` → `cainz-wanqol-web-push`).

**Rule nền:** `E:\vault\_common\operations\vault-location.md`. Đọc nó trước nếu chưa có trong context.

## Bất biến — vi phạm là làm lại

1. Vault sống ở `E:\vault\<slug>\`. **Không bao giờ** tạo thư mục vault trong repo code.
2. Không tạo `.obsidian/` riêng — `E:\vault\` đã là 1 Obsidian vault.
3. Link giữa note = **relative markdown**, không wikilink `[[...]]`.
4. Một repo = một vault project. Repo khác của cùng sản phẩm → vault riêng, ghi rõ phân biệt ở hub note.
5. Nội dung phải **đọc từ code thật**, không bịa. Mọi khẳng định kèm `file:line` khi có thể.

## Bước

### 1. Khảo sát

- `E:\vault\_common\_common.md` + `E:\vault\_common\operations\vault-location.md` — convention.
- `ls E:\vault` — đã có project nào; nếu `<slug>` tồn tại thì **update**, không ghi đè mù.
- Một project sẵn có làm mẫu format (vd `E:\vault\cainz-wanqol-web-push\`).
- `E:\vault\_common\templates\` — frontmatter chuẩn theo loại note.

### 2. Đọc repo

Đọc thật, không lướt: entrypoint, router/route table, config, model/schema, service/repository, Dockerfile, CI/CD, manifest deploy, `package.json`/`go.mod`/..., `git log --oneline -10`.

Ghi lại lúc đọc: env var (kèm default), endpoint, bảng + trạng thái, luồng nghiệp vụ chính, và **mọi bẫy** (hardcode secret, auth yếu, race, lỗi off-by-one, mismatch cấu hình deploy).

### 3. Scaffold

```
E:\vault\<slug>\
  <Project Name> Vault.md    hub: Structure / Đọc khi vào project / In-repo references /
                             Conventions / Repo location / Stack quick reference
  CLAUDE.md                  Layout / Common commands / Stack notes / Conventions / Known issues
                             + footer NAV:AUTO trỏ về hub
  audit/audit.md         decisions/decisions.md   memory/memory.md
  meta/meta.md           operations/operations.md org/org.md
  perf/perf.md           systems/systems.md       thinking/thinking.md
  work/work.md
  work/{active,archive}/  operations/{incidents,tasks,playbooks}/  memory/sessions/
```

Thư mục rỗng: thêm `.gitkeep`.

### 4. Note nội dung

- `systems/overview.md` — layer, bootstrap, runtime topology, sidecar. **Bắt buộc.**
- `systems/<domain>.md` — mỗi mảng 1 file: `api-routes`, `data-model`, luồng nghiệp vụ chính, tích hợp ngoài.
- `operations/deploy-<platform>.md` — build → registry → deploy, ma trận env.
- `operations/env-secrets.md` — bảng env var + default + nơi cất secret per env.
- `operations/pitfalls.md` — bẫy chia nhóm **Security / Correctness / Vận hành**, đánh ID `S1..`, `C1..`, `O1..` để note khác tham chiếu.
- `meta/vault-setup.md` — log dựng vault: nguồn (branch + commit), map file cũ → mới nếu là migrate, việc còn để ngỏ.

Frontmatter mỗi note nội dung: `title`, `created`, `updated`, `tags`, `status`, `code_paths` (+ `component`/`depends_on`/`depended_by` cho `systems/`), `owner`.

### 5. Wiring

- Copy `E:\vault\_common\hooks\cainz-wanqol-gate.ps1` → `<slug>-gate.ps1`; đổi `$*RepoPath` (đường dẫn repo), `$*EncodedDir` (path repo với `:`/`\` → `-`, vd `E--canz-wanqol-WanQol-WEB-PUSH`), và tên project truyền cho hook script ở dòng cuối.
- Thêm gate vào `~/.claude/settings.json` đủ **4 event**: `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `SessionEnd`.
- Validate: `python -c "import json;json.load(open(r'C:\Users\User.HP\.claude\settings.json',encoding='utf-8'));print('OK')"`

### 6. Báo cáo

Liệt kê file đã tạo, và nêu riêng những phát hiện đáng lo lúc đọc code (secret hardcode, auth yếu, mismatch deploy) — đó là giá trị chính của lượt chạy, đừng chôn trong danh sách file.

## Ghi chú

- Repo đã có vault → chỉ cập nhật phần lệch, giữ nguyên `work/`, `memory/`, `decisions/` do người viết.
- Không commit gì vào repo code. Vault `E:\vault\` là git repo riêng — chỉ commit khi người dùng yêu cầu.
