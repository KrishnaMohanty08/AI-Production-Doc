# 🗺️ Data Flow Diagrams

> This file is automatically maintained by the AI DevDocs Engine.
> Mermaid diagrams inside `<!-- AI:START:* -->` blocks are AI-managed.
> Add your own diagrams **outside** these blocks.

---

<!-- AI:START:SYSTEM_DFD -->
### 🗺️ System-Level Data Flow

```mermaid
graph TD
    User["👤 User"] --> Frontend["🖥️ Frontend"]
    Frontend --> Backend["⚙️ Backend API"]
    Backend --> Database["🗄️ Database"]
    Backend --> GitHub["🐙 GitHub"]
    GitHub --> Secrets["🔒 Secrets"]
    Secrets -->|GROQ_API_KEY_2|> Backend
```
<!-- AI:END:SYSTEM_DFD -->

---

<!-- AI:START:FEATURE_DFD -->
### ⚙️ Feature / Module Data Flow
_Based on: new api token added_

```mermaid
graph LR
    GitHub["🐙 GitHub"] --> Secrets["🔒 Secrets"]
    Secrets -->|GROQ_API_KEY_2|> Backend["⚙️ Backend API"]
    Backend --> Scripts["📝 Scripts"]
    Scripts -->|generate-dfd.sh|> DFD["🗺️ DFD Generation"]
    Scripts -->|generate-todos.sh|> Todos["📋 TODO Tracker Generation"]
```
<!-- AI:END:FEATURE_DFD -->

---

<!-- AI:START:CHANGE_SUMMARY -->
### 📝 Diagram Change Notes
- Added GitHub and Secrets to the system-level data flow to reflect the new API token.
- Updated the feature-level data flow to show the generation of DFD and TODO tracker using the new API token.
<!-- AI:END:CHANGE_SUMMARY -->

---

<!-- MANUAL: Add your own diagrams below -->
