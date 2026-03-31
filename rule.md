# SillyTavern Remote Backup Project Rules
# 本文件为 AI 提供项目上下文，请严格遵守以下规范。

## 1. Project Overview (项目概览)
- **Name**: SillyTavern Remote Backup (ST-Backup)
- **Type**: 独立的微服务备份工具，不依赖 Git 或 ST 插件系统。
- **Goal**: 提供 Web 界面 (Port 8787) 用于一键备份、查看、恢复和删除 SillyTavern 的数据文件。
- **Deployment**: 通常运行在 Linux 环境 (Termux/VPS)，通过 PM2 守护进程。

## 2. Tech Stack (技术栈)
- **Backend**: Node.js, Express.
  - **Dependencies**: `express`, `tar` (核心压缩库), `basic-auth`.
  - **Process Manager**: PM2.
- **Frontend**: Vanilla HTML5 + JavaScript (ES6+).
  - **Styling**: Tailwind CSS (通过 CDN 引入，无构建步骤).
  - **Icons**: SVG 直接嵌入 HTML。
- **Scripting**: Bash (用于安装、自动更新和 Cron 任务)。

## 3. Architecture & File Structure (架构与文件)
- **Root**:
  - `scripts/install.sh`: 一键安装脚本 (处理 PM2, 防火墙, Cron, 目录创建).
  - `files/server.js`: 单文件后端服务 (API + 静态资源托管).
  - `files/public/index.html`: 单文件前端 UI (包含所有 JS/CSS 逻辑).
- **Runtime Paths (Default)**:
  - **App Dir**: `/opt/st-remote-backup`
  - **Data Dir (Target)**: `/root/sillytavern/data` (可配置)
  - **Backup Dir**: `/opt/st-remote-backup/backups`
  - **Config**: 环境变量或 `config.json` 传递 (PORT, DATA_DIR, BASIC_USER, R2_* 等).

## 4. Key Logic & Constraints (核心逻辑与约束)

### A. Authentication (鉴权)
- **Mechanism**: HTTP Basic Auth。
- **Critical Implementation Details**:
  - 后端 (`server.js`) **严禁** 发送 `WWW-Authenticate` 响应头，以防止浏览器弹出原生登录框。
  - 前端 (`index.html`) 在 Fetch 请求头中手动构造 `Authorization: Basic base64(u:p)`。
  - 静态资源 (`/`, `index.html`) 不鉴权，API (`/backup`, `/list` 等) 必须鉴权。

### B. Backup Strategy (备份策略)
- **Format**: `.tar.gz` (Gzip level 1，追求速度).
- **Exclusions**:
  - Must Exclude: `.git`, `node_modules`.
  - Cache/Temp: `_cache`, `_uploads`, `_storage`, `coverage`, etc.
  - Self: Exclude existing archives inside the data directory (`*.tar.gz`, `*.zip`).
- **Retention**: 改为“每天一份”命名策略，同一天重复备份会覆盖当天归档，不再使用“固定保留 5 份”模式。
- **Remote Storage**: 备份完成后可上传到 Cloudflare R2，任意部署节点只要填写相同 R2 信息即可列出、下载和恢复远端备份。

### C. Restore Strategy (恢复策略)
- **Method**: 覆盖式恢复 (Overlay)。
- **Behavior**: `tar.x` 解压覆盖同名文件，**不删除** 备份中不存在的本地文件 (为了安全性)。

## 5. Coding Standards (代码规范)

### Backend (Node.js)
- 使用 `CommonJS` (`require`) 模块规范。
- 优先使用 `fs.promises` 或 `async/await` 处理文件 I/O。
- 所有的 `console.log` 已被重写以推入内存日志数组 (`LOG_BUF`)，保持此模式以支持前端日志面板。
- 错误处理：API 必须返回 JSON `{ ok: false, error: "msg" }` 而非直接 Crash。

### Frontend (HTML/JS)
- **No Build Tools**: 不要引入 Webpack/Vite/React/Vue。保持单文件 `index.html` 结构。
- **Layout**: 必须适配移动端 (Responsive)，使用 Tailwind 的 `sm:`, `md:` 断点。
- **Interaction**: 使用 `fetch` 与后端通信，操作前需弹窗确认 (自定义模态框，非 `confirm()`)。

### Shell Script (Bash)
- 必须包含 `set -euo pipefail`。
- 必须检测 `sudo` 权限。
- 安装脚本需具备幂等性 (Idempotent)：支持重复运行以进行更新。

## 6. Workflow Guidelines (工作流指南)
- **Modifying UI**: 直接编辑 `files/public/index.html`。注意不要破坏 Tailwind 类名。
- **Modifying Backend**: 编辑 `files/server.js`。
- **Testing**:
  - 本地测试时，需确保 Node 环境 >= 18。
  - 模拟生产环境路径或使用相对路径进行调试。
- **Adding Features**:
  - 如果添加新 API，记得在 `authGuard` 中处理鉴权，并在前端添加对应按钮/逻辑。
