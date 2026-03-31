# ST Remote Backup

一个独立的 SillyTavern 备份服务，提供网页界面用于：

- 本地打包备份
- 上传到 Cloudflare R2
- 查看备份列表
- 下载备份
- 从本地或 R2 恢复备份
- 删除本地或 R2 备份

现在的仓库结构以根目录为准：

- `server.js`
- `public/index.html`
- `scripts/install.sh`
- `package.json`
- `package-lock.json`
- `ecosystem.config.js`

旧版 `files/` 目录已经不再使用。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/xiu14/1/main/scripts/install.sh | bash
```

默认安装参数：

- 端口：`8787`
- 数据目录：`/root/sillytavern/data`
- 备份目录：`/root/st-remote-backup/backups`
- 默认账号：`st`
- 默认密码：`2025`

安装完成后访问：

```text
http://你的服务器IP:8787/
```

## 通过 Git 拉取更新

如果你是直接在服务器上 `git clone` / `git pull`，推荐流程：

```bash
cd /root/st-remote-backup
git pull
npm ci --omit=dev
pm2 restart st-backup --update-env
```

## 安装脚本参数

```bash
bash scripts/install.sh \
  --port 8787 \
  --data /root/sillytavern/data \
  --backup-dir /root/st-remote-backup/backups \
  --user st \
  --pass 2025 \
  --cron "0 4 * * *"
```

支持参数：

- `-p, --port`
- `-d, --data`
- `-b, --backup-dir`
- `-u, --user`
- `-w, --pass`
- `--cron`
- `--no-firewall`

## 当前备份逻辑

- 备份格式：`.tar.gz`
- 本地保留：如果未配置 R2，则本地保留最新一份；如果已配置 R2 且上传成功，本地归档会作为临时文件自动删除
- 命名策略：R2 端按天一份，同一天重复备份会覆盖当天归档
- 可选上传到 Cloudflare R2
- 任意部署节点只要填写相同的 R2 信息和本地数据目录，就能拉取并恢复备份

## R2 配置方式

在网页设置里填写：

- `Account ID`
- `Bucket`
- `Access Key ID`
- `Secret Access Key`
- `Prefix`

保存后重启服务即可生效。
