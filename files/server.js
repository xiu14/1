const express = require('express');
const fs = require('fs');
const fsp = require('fs').promises;
const path = require('path');
const tar = require('tar');
const basicAuth = require('basic-auth');

const PORT = process.env.PORT || 8787;
const DATA_DIR = process.env.DATA_DIR || '/root/sillytavern/data';
const BACKUP_DIR = process.env.BACKUP_DIR || '/opt/st-remote-backup/backups';
const USER = process.env.BASIC_USER || '';
const PASS = process.env.BASIC_PASS || '';

async function ensureDir(dir) { await fsp.mkdir(dir, { recursive: true }).catch(()=>{}); }

// 内存日志环形缓冲（用于 /logs 页面展示）
const LOG_BUF = [];
const LOG_MAX = 2000;
const __origLog = console.log;
const __origErr = console.error;
function pushLog(level, msg) {
  const ts = new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false });
  const line = `${ts} [${level}] ${msg}`;
  LOG_BUF.push(line);
  if (LOG_BUF.length > LOG_MAX) LOG_BUF.splice(0, LOG_BUF.length - LOG_MAX);
  (level === 'error' ? __origErr : __origLog)(line);
}
console.log = (...a) => pushLog('info', a.join(' '));
console.error = (...a) => pushLog('error', a.join(' '));

// 排除规则
const EXCLUDE_SEGMENTS_ALWAYS = new Set(['.git', 'node_modules']);
const EXCLUDE_SEGMENTS_CACHE = new Set(['_cache','_uploads','_storage','_webpack','.cache','.parcel-cache','.vite','coverage']);
const EXCLUDE_PREFIXES = ['default-user/backups'];
const EXCLUDE_SUFFIXES = ['.zip','.tar','.tar.gz'];

function shouldInclude(relPath) {
  const p = relPath.replace(/^\.\/?/, '');
  if (EXCLUDE_PREFIXES.some(pre => p === pre || p.startsWith(pre + '/'))) return false;
  const parts = p.split('/');
  if (parts.some(seg => EXCLUDE_SEGMENTS_ALWAYS.has(seg))) return false;
  const isThirdParty = parts[0] === 'third-party';
  if (!isThirdParty && parts.some(seg => EXCLUDE_SEGMENTS_CACHE.has(seg))) return false;
  if (EXCLUDE_SUFFIXES.some(suf => p.endsWith(suf))) return false;
  return true;
}

// --- 核心修改：移除 WWW-Authenticate 头 ---
function authGuard(req, res, next) {
  if (!USER && !PASS) return next();
  const creds = basicAuth(req);
  if (creds && creds.name === USER && creds.pass === PASS) return next();
  
  // 关键修改：注释掉下面这行，禁止浏览器弹出原生登录框
  // res.set('WWW-Authenticate', 'Basic realm="st-backup"');
  
  return res.status(401).send('Unauthorized');
}

const app = express();
app.use(express.json({ limit: '1mb' }));

// 静态页面（UI 不鉴权，优先服务）
const PUBLIC_DIR = path.join(__dirname, 'public');
app.use('/', express.static(PUBLIC_DIR));

// 忽略 favicon 请求 (防止它触发 401 错误日志)
app.get('/favicon.ico', (req, res) => res.status(204).end());

// 接口鉴权
app.use(authGuard);

// 健康检查
app.get('/health', async (req, res) => {
  // console.log('[health] ok'); // 减少日志刷屏
  res.json({ ok: true, dataDir: DATA_DIR, backupDir: BACKUP_DIR });
});

// 获取最近日志
app.get('/logs', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit || '500', 10), LOG_MAX);
  res.json({ lines: LOG_BUF.slice(-limit) });
});

// 清空日志
app.delete('/logs', (req, res) => {
  LOG_BUF.length = 0;
  res.json({ ok: true });
});

// 创建备份
app.post('/backup', async (req, res) => {
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const name = `st-data-${ts}.tar.gz`;
  const out = path.join(BACKUP_DIR, name);
  const t0 = Date.now();
  try {
    await ensureDir(BACKUP_DIR);
    await tar.c({
      gzip: true,
      gzipOptions: { level: 1 },
      file: out,
      cwd: DATA_DIR,
      filter: (entryPath) => shouldInclude(entryPath)
    }, ['.']);
    const st = await fsp.stat(out);
    console.log(`[backup] done name=${name} size=${(st.size/1048576).toFixed(2)}MB time=${Date.now()-t0}ms`);
    res.json({ ok: true, file: name });
  } catch (e) {
    console.error('[backup] error:', e && e.stack || e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// 列表
app.get('/list', async (req, res) => {
  try {
    await ensureDir(BACKUP_DIR);
    const files = await fsp.readdir(BACKUP_DIR, { withFileTypes: true });
    const list = [];
    for (const d of files) {
      if (!d.isFile()) continue;
      const p = path.join(BACKUP_DIR, d.name);
      const st = await fsp.stat(p);
      list.push({ name: d.name, size: st.size, mtime: st.mtime });
    }
    list.sort((a,b)=> new Date(b.mtime)-new Date(a.mtime));
    console.log(`[list] ok count=${list.length}`);
    res.json({ ok: true, items: list });
  } catch (e) {
    console.error('[list] error:', e && e.stack || e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// 下载备份文件
app.get('/download', async (req, res) => {
  const name = (req.query.name || '').toString();
  if (!name) return res.status(400).send('name required');
  const safeName = path.basename(name); 
  const file = path.join(BACKUP_DIR, safeName);
  try {
    await fsp.access(file);
    console.log(`[download] start name=${safeName}`);
    res.download(file, safeName, (err) => {
      if (err) console.error(`[download] error name=${safeName}`, err);
    });
  } catch (e) {
    console.error(`[download] not found name=${safeName}`);
    res.status(404).send('File not found');
  }
});

// 恢复（覆盖式）
app.post('/restore', async (req, res) => {
  const name = (req.query.name || req.body?.name || '').toString();
  const t0 = Date.now();
  try {
    if (!name) return res.status(400).json({ ok: false, error: 'name required' });
    const file = path.join(BACKUP_DIR, path.basename(name));
    await fsp.access(file);
    await tar.x({ file, cwd: DATA_DIR });
    console.log(`[restore] done name=${name} time=${Date.now()-t0}ms`);
    res.json({ ok: true });
  } catch (e) {
    console.error('[restore] error:', e && e.stack || e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// 删除
app.delete('/delete', async (req, res) => {
  try {
    const name = (req.query.name || '').toString();
    if (!name) return res.status(400).json({ ok: false, error: 'name required' });
    const file = path.join(BACKUP_DIR, path.basename(name));
    await fsp.unlink(file);
    console.log(`[delete] done name=${name}`);
    res.json({ ok: true });
  } catch (e) {
    console.error('[delete] error:', e && e.stack || e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

app.listen(PORT, () => {
  console.log(`[st-remote-backup] listening on ${PORT}, DATA_DIR=${DATA_DIR}, BACKUP_DIR=${BACKUP_DIR}`);
});
