# Remote Backup for SillyTavern (port 8787)

一个独立的备份微服务：通过浏览器页面 http://IP:8787/ 一键【创建备份 / 查看 / 恢复 / 删除】，并可配置每天定时自动备份（仅保留最近 N 份）。无需依赖 Git/Gitee/LFS，也不依赖 SillyTavern 的插件系统。

## 特性
- 一键安装脚本，开箱即用（pm2 后台守护、自启）
- 网页 UI 操作（页面内输入账号密码登录，不弹出浏览器 Basic 框）
- **网页端配置管理**：端口、目录、账号密码、备份保留份数，一键保存并重启生效
- **下载/恢复进度条**：实时显示进度百分比和已传输大小
- 排除 `.git/ node_modules/`、缓存与已有归档，备份专注核心数据
- 覆盖式恢复：备份中存在的文件覆盖同名文件，本地多余文件保留（更安全）
- 可选每日自动备份，保留最近 N 份
- 页面内置"服务日志"面板，可自动刷新

---

## 1) 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/xiu14/1/main/scripts/install.sh | bash
```

**默认配置：**
| 配置项 | 默认值 |
|--------|--------|
| 端口 | 8787 |
| 数据目录 | /root/sillytavern/data |
| 备份目录 | /opt/st-remote-backup/backups |
| 账号/密码 | st / 2025 |
| 备份保留 | 5 份 |

安装完成后访问：`http://你的服务器IP:8787/`

> 提示：云安全组请在控制台放行 8787/TCP。

---

## 2) 安装后配置（推荐）

安装后所有配置都可以在网页上修改，**无需记住命令行参数**：

1. 浏览器访问 `http://你的IP:8787/`
2. 用默认账号密码 `st / 2025` 登录
3. 点击操作区的"**设置**"按钮（齿轮图标）
4. 修改需要调整的配置项（密码留空则不修改）
5. 点击"**保存配置**" → "**重启**"

> 如果修改了端口，重启后需要改用新端口访问。

---

## 3) 更新已安装的服务

```bash
# 重新运行安装脚本即可更新到最新版本
curl -fsSL https://raw.githubusercontent.com/xiu14/1/main/scripts/install.sh | bash
```

或手动更新：
```bash
cd /opt/st-remote-backup
curl -fsSL https://raw.githubusercontent.com/xiu14/1/main/files/server.js -o server.js
curl -fsSL https://raw.githubusercontent.com/xiu14/1/main/files/public/index.html -o public/index.html
pm2 restart st-backup --update-env
```

---

## 4) 使用

| 操作 | 网页 | 接口 |
|------|------|------|
| 创建备份 | 点击"创建备份" | `POST /backup` |
| 备份列表 | 自动显示 | `GET /list` |
| 恢复备份 | 点击"恢复" | `POST /restore?name=xxx.tar.gz` |
| 删除备份 | 点击"删除" | `DELETE /delete?name=xxx.tar.gz` |
| 下载备份 | 点击"下载" | `GET /download?name=xxx.tar.gz` |
| 修改配置 | 点击"设置" | `POST /config` |
| 重启服务 | 设置内"重启" | `POST /restart` |

接口示例：
```bash
curl -u 'st:2025' http://IP:8787/health
curl -u 'st:2025' -X POST http://IP:8787/backup
```

---

## 5) 自动备份（可选）

安装时追加定时任务参数：
```bash
curl -fsSL https://raw.githubusercontent.com/xiu14/1/main/scripts/install.sh -o install.sh
bash install.sh --cron "0 8 * * *" --keep 5
```

这将每天 08:00 自动备份，保留最近 5 份。

---

## 6) 命令行安装参数（高级用户）

```bash
bash install.sh \
  -p 8787 \
  -d '/root/sillytavern/data' \
  -b '/opt/st-remote-backup/backups' \
  -u st -w 2025 \
  --cron "0 8 * * *" \
  --keep 5
```

| 参数 | 说明 |
|------|------|
| `-p, --port` | 监听端口 |
| `-d, --data` | SillyTavern 数据目录 |
| `-b, --backup-dir` | 备份目录 |
| `-u, --user` | Basic 用户名 |
| `-w, --pass` | Basic 密码 |
| `--cron` | 定时任务表达式 |
| `--keep` | 备份保留份数 |
| `--no-firewall` | 跳过自动放行防火墙 |

> 💡 通常不需要这些参数，安装后在网页设置中修改更方便。

---

## 7) 卸载

```bash
pm2 delete st-backup || true
sudo rm -rf /opt/st-remote-backup
# 如需移除定时：crontab -e 删除对应行
```

---

## 8) 常见问题

**外网访问不了 8787？**
- 确保云安全组放行 8787/TCP

**跨服务器恢复？**
- 将 A 的 `.tar.gz` 复制到 B 的 `/opt/st-remote-backup/backups/`，然后在 B 的网页点"恢复"

**恢复会删除多余文件吗？**
- 不会。只覆盖同名文件，备份中不存在的本地文件保留

---

## 9) 安全建议
- 修改默认账号密码（安装后在网页设置中修改）
- 重要生产环境建议用反向代理 + HTTPS
