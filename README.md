#  AI DevDocs Engine

> Automatically generate and update developer documentation from Git commits using an LLM (Groq API + `llama3-70b-8192`).

[![Docs CI](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/docs.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/docs.yml)

---

## 🎯 What It Does

Every time you push to `main`, this system:

1. Extracts the **git diff** and **commit message**
2. Calls the **Groq API** (LLaMA 3 70B) with structured prompts
3. Updates four living documentation files in `ai-docs/`
4. Commits the updated docs back to your repo automatically

---

## 📁 Project Structure

```
ai-devdocs/
├── scripts/
│   ├── generate-progress.sh       # Updates progress tracking
│   ├── generate-architecture.sh   # Updates architecture docs
│   ├── generate-dfd.sh            # Updates Mermaid DFD diagrams
│   └── generate-todos.sh          # Tracks TODO/FIXME comments (bonus)
│
├── prompts/
│   ├── progress.txt               # LLM prompt for progress tracking
│   ├── architecture.txt           # LLM prompt for architecture docs
│   ├── dfd.txt                    # LLM prompt for DFD generation
│   └── todos.txt                  # LLM prompt for TODO tracking
│
├── templates/
│   ├── progress.md                # Initial template with AI block markers
│   ├── architecture.md            # Initial template with AI block markers
│   ├── dfd.md                     # Initial template with Mermaid stubs
│   └── todos.md                   # Initial template for TODO table
│
├── ai-docs/                       # ← Generated documentation lives here
│   ├── progress.md
│   ├── architecture.md
│   ├── dfd.md
│   └── todos.md
│
├── .github/workflows/
│   └── docs.yml                   # GitHub Actions pipeline
│
├── .llmignore                     # Patterns to skip for LLM processing
└── README.md
```

---

## 🚀 Setup

### 1. Add your Groq API key as a GitHub Secret

Go to your repo → **Settings → Secrets → Actions → New repository secret**

```
Name:  GROQ_API_KEY
Value: gsk_xxxxxxxxxxxxxxxxxxxx
```

Get your free key at [console.groq.com](https://console.groq.com).

### 2. Copy this project into your repo

You can either:
- Use this repo as a **template** (click "Use this template" on GitHub)
- Or **copy the relevant directories** into your existing project:

```bash
cp -r scripts/ prompts/ templates/ .github/ .llmignore YOUR_PROJECT/
mkdir -p YOUR_PROJECT/ai-docs
cp templates/*.md YOUR_PROJECT/ai-docs/
```

### 3. Push a commit to `main`

```bash
git add .
git commit -m "feat: add AI DevDocs Engine"
git push origin main
```

The GitHub Action will run automatically and populate `ai-docs/`.

---

## 📖 Generated Documentation

| File | Description |
|------|-------------|
| `ai-docs/progress.md` | ✅ Completed tasks, 🔁 recent changes, ⏳ pending work |
| `ai-docs/architecture.md` | Tech stack, project structure, request flow, DB schema |
| `ai-docs/dfd.md` | Mermaid system-level and feature-level data flow diagrams |
| `ai-docs/todos.md` | Tracked TODO/FIXME/HACK comments across the codebase |

---

## ✏️ Preserving Manual Edits

All generated files use **AI-managed blocks**:

```markdown
<!-- AI:START:BLOCK_NAME -->
... AI updates only this section ...
<!-- AI:END:BLOCK_NAME -->
```

Any content you write **outside** these blocks will **never be overwritten**.

---

## 🚫 .llmignore

Similar to `.gitignore`, you can tell the engine to skip files:

```
# Skip lock files
package-lock\.json
yarn\.lock

# Skip binary files
\.(png|jpg|pdf|zip)$

# Skip test snapshots
__snapshots__/
```

---

## 🔧 Running Scripts Locally

```bash
# Set your API key
export GROQ_API_KEY="gsk_your_key_here"

# Generate a fake diff and commit for testing
git diff HEAD~1 HEAD > changes.diff
git log -1 --pretty=format:"%s" > commit.txt

# Run individual scripts
./scripts/generate-progress.sh
./scripts/generate-architecture.sh
./scripts/generate-dfd.sh
./scripts/generate-todos.sh

# View results
cat ai-docs/progress.md
```

---

## ⚙️ Configuration

| Variable | Where | Description |
|----------|-------|-------------|
| `GROQ_API_KEY` | GitHub Secret | Your Groq API key |
| `GROQ_MODEL` | In each script | Default: `llama3-70b-8192` |
| `GROQ_MAX_TOKENS` | In each script | Default: `2048` |

---

## 🧠 How the AI Block System Works

Each generated document is divided into **named sections** with HTML comment delimiters:

```
<!-- AI:START:SECTION_NAME -->
[LLM-managed content]
<!-- AI:END:SECTION_NAME -->
```

The merge logic in each script:
1. Reads the existing file (or template if first run)
2. Gets the newly generated content from Groq
3. Extracts named blocks from the generated content
4. Replaces **only the matching blocks** in the existing file
5. Preserves everything else unchanged

This means you can safely add notes, decisions, and context anywhere in the doc.

---

## 🛡️ Safety Features

- **Token limits**: Diffs are truncated at ~6000 chars to prevent API errors
- **HTTP error handling**: Non-200 responses abort the script with a clear error
- **Empty response guard**: Scripts fail fast if Groq returns empty content
- **[skip ci]**: Doc commits include this tag to prevent infinite Action loops
- **Idempotent commits**: Only commits if `ai-docs/` actually changed
- **Timeout**: All API calls have a 60-second timeout

---

## 📦 Requirements

- `bash` ≥ 4.0
- `curl`
- `python3` (standard library only — `json`, `re`, `os`, `sys`)
- `git`
- A Groq API key (free tier available)

---

## 🤝 Extending the Engine

To add a new documentation type:

1. Create a prompt in `prompts/newdoc.txt`
2. Create a template in `templates/newdoc.md` with `<!-- AI:START:BLOCK -->` markers
3. Copy one of the existing scripts to `scripts/generate-newdoc.sh` and update the file paths
4. Add a new step in `.github/workflows/docs.yml`

---

## 📄 License

MIT — use freely in your projects.
