# Universal MCP + Skills Setup Guide

This folder is a **universal, clone-and-run toolbox** for AI agents (Claude Code, OpenCode, Codex, Unsloth Studio, etc.).
It bundles MCP servers, agent skills, and sync scripts so any agent can bootstrap itself without manual setup.

> **Rule for agents:** If an MCP server or skill referenced below is not yet configured on the current machine,
> run the setup steps in this document **before** attempting to use that tool. Do not silently skip it.

---

## 1. Clone the toolbox

```bash
git clone <repo-url> "FULL STACK AI SKILL"
cd "FULL STACK AI SKILL"
```

All paths in this guide are relative to this folder.

---

## 2. Skills — sync into agent skill directories

Skills live under subfolders (e.g. `remotion/.agents/skills`, `upstream-mcp/.../skills`, `OmniRoute/skills`).
The master index is `SKILLS_INDEX.md` (auto-generated).

### Sync command (Windows / PowerShell)

```powershell
.\sync_skills.ps1
```

This links every skill into:
- `%USERPROFILE%\.claude\skills`
- `%USERPROFILE%\.config\opencode\skills`

### Manual sync (if script unavailable)

Copy or symlink each `SKILL.md`-containing folder into the agent's skills directory.
An agent can discover skills by scanning this folder for `SKILL.md` files.

### Agent rule
- Before claiming a skill is unavailable, check `SKILLS_INDEX.md` and the source paths listed there.
- If a skill is missing locally, re-run `sync_skills.ps1` (or re-clone) instead of guessing.

---

## 3. MCP servers — setup & auto-configure

MCP servers are stored as subprojects (e.g. `context7`, `shadcn-ui-mcp-server`, `cursor-talk-to-figma-mcp`,
`mcp-for-blender`, `playwright-mcp`, `upstream-mcp/*`).

### 3.1 Generic `.mcp.json` template

Place this in your agent's config location (e.g. project root or `~/.config/opencode/`):

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "env": {}
    },
    "shadcn-ui": {
      "command": "node",
      "args": ["shadcn-ui-mcp-server/index.js"],
      "env": {}
    }
  }
}
```

Adjust `args` paths to point at the cloned subproject folders.

### 3.2 Auto-setup rule for agents

If an MCP tool is needed but not configured:
1. Check whether the subproject folder exists in this toolbox.
2. If yes, install its dependencies (`npm install` / `pip install`) inside that subproject.
3. Register it in `.mcp.json` using the template above (relative path to the subproject).
4. Retry the tool call.
5. If the subproject is missing, clone it into this folder first, then repeat.

### 3.3 Common MCPs included

| MCP | Folder | Notes |
| :--- | :--- | :--- |
| context7 | `upstream-mcp/context7` / `context7` | Docs lookup |
| shadcn-ui | `shadcn-ui-mcp-server` | UI components |
| chrome-devtools | `upstream-mcp/chrome-devtools-mcp` | Browser debugging |
| figma-context | `figma-context-mcp` | Figma integration |
| cursor-talk-to-figma | `cursor-talk-to-figma-mcp` | Figma bridge |
| magic-mcp / 21st-ui | `upstream-mcp/magic-mcp` | UI generation |
| playwright | `playwright-mcp` | Browser automation |
| blender | `mcp-for-blender` | 3D |
| OmniRoute | `OmniRoute` | Routing / inference |

---

## 4. How agents should use this toolbox

- **Always prefer** skills/MCPs from this folder over ad-hoc solutions.
- **Before using a tool**, verify it is installed & configured (see §3.2).
- **When a tool call fails** with "not found" / "not configured", follow §3.2 auto-setup instead of giving up.
- **When adding a new skill or MCP**, place it in this folder and update `SKILLS_INDEX.md` (re-run `sync_skills.ps1`).
- **Keep paths relative** so the toolbox stays portable after cloning.

---

## 5. Troubleshooting

- **Skill not found by agent:** re-run `sync_skills.ps1`; check `SKILLS_INDEX.md` for the source path.
- **MCP not connecting:** verify the subproject builds (`npm run build`), check `.mcp.json` paths are correct, restart the agent.
- **Missing dependencies:** run install inside the specific subproject folder, not the toolbox root.
- **Permission errors on Windows:** run PowerShell as Administrator or adjust execution policy (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`).

---

## 6. Updating

```powershell
git pull
.\sync_skills.ps1
```

Re-run installs for any MCP subproject whose `package.json` changed.

---

*This file is the single source of truth for setting up the universal toolbox. Agents: read this first.*
