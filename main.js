const { app, BrowserWindow, dialog, ipcMain, Menu, shell, nativeImage, net, session } = require('electron');
const crypto = require('crypto');
const fs = require('fs/promises');
const path = require('path');
const { pathToFileURL, fileURLToPath } = require('url');

const audioExtensions = new Set(['.mp3', '.m4a', '.wav', '.flac', '.ogg', '.aac', '.opus', '.webm']);
const imageExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp', '.gif']);

function stableId(value) {
  return crypto.createHash('sha1').update(value).digest('hex').slice(0, 16);
}

function libraryPath() {
  return path.join(app.getPath('userData'), 'library.json');
}

function toFileUrl(filePath) {
  return pathToFileURL(filePath).href;
}

async function loadLibrary() {
  try {
    const data = JSON.parse(await fs.readFile(libraryPath(), 'utf8'));
    return Array.isArray(data.albums) ? data.albums : [];
  } catch {
    return [];
  }
}

async function saveLibrary(albums) {
  await fs.mkdir(path.dirname(libraryPath()), { recursive: true });
  await fs.writeFile(libraryPath(), JSON.stringify({ albums }, null, 2));
}

async function findFiles(folderPath) {
  let entries;
  try {
    entries = await fs.readdir(folderPath, { withFileTypes: true });
  } catch {
    return [];
  }
  const nested = await Promise.all(entries.filter(entry => !entry.name.startsWith('.')).map(async entry => {
    const fullPath = path.join(folderPath, entry.name);
    return entry.isDirectory() ? findFiles(fullPath) : [fullPath];
  }));
  return nested.flat();
}

function selectFolderArtwork(files) {
  const artwork = files.filter(filePath => imageExtensions.has(path.extname(filePath).toLowerCase()));
  return artwork.find(filePath => /(cover|front|folder|album|封面)/i.test(path.basename(filePath))) || artwork[0] || null;
}

function mostCommon(values) {
  const counts = new Map();
  for (const value of values) {
    if (!value) continue;
    counts.set(value, (counts.get(value) || 0) + 1);
  }
  let best = null;
  let bestCount = 0;
  for (const [value, count] of counts) if (count > bestCount) { best = value; bestCount = count; }
  return best;
}

// 从文件夹路径 / 标题 / 文件名中提取 DLsite RJ 号（检查路径所有层级）
function extractRjCode(...values) {
  for (const value of values) {
    const match = String(value || '').match(/RJ\d{5,}/i);
    if (match) return match[0].toUpperCase();
  }
  return null;
}

// 专辑兜底取 RJ 号（老专辑 rjCode 缺失时从路径/标题/曲目名再提取）
function albumRjCode(album) {
  if (album.rjCode) return album.rjCode;
  const trackNames = (album.tracks || []).map(track => track.name || '').join(' ');
  return extractRjCode(album.sourcePath, album.title, trackNames);
}

// 嵌入封面缩放到 500px 内并转 JPEG，避免超大 base64 拖垮导入与 library.json
function coverDataUrl(picture) {
  try {
    const image = nativeImage.createFromBuffer(picture.data);
    if (image.isEmpty()) return null;
    const { width, height } = image.getSize();
    const max = 500;
    let resized = image;
    if (width > max || height > max) {
      const scale = max / Math.max(width, height);
      resized = image.resize({ width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)), quality: 'good' });
    }
    const jpeg = resized.toJPEG(82);
    if (!jpeg.length || jpeg.length > 300 * 1024) return null;
    return `data:image/jpeg;base64,${jpeg.toString('base64')}`;
  } catch {
    return null;
  }
}

async function scanAlbum(albumPath, files) {
  const { parseFile } = await import('music-metadata');
  const audioPaths = files
    .filter(filePath => audioExtensions.has(path.extname(filePath).toLowerCase()))
    .sort((a, b) => path.basename(a).localeCompare(path.basename(b), undefined, { numeric: true }));
  if (!audioPaths.length) return null;

  const albumNames = [];
  const albumArtists = [];
  const artists = [];
  const tracks = [];
  for (const [index, filePath] of audioPaths.entries()) {
    let metadata = null;
    try {
      metadata = await parseFile(filePath, { duration: true, skipCovers: false });
    } catch {
      // A playable local file should remain importable even if its tags are malformed.
    }
    if (metadata) {
      albumNames.push(metadata.common.album);
      albumArtists.push(metadata.common.albumartist || null);
      artists.push(metadata.common.artist || null);
    }
    const picture = metadata?.common.picture?.[0];
    tracks.push({
      index,
      name: metadata?.common.title || path.basename(filePath, path.extname(filePath)),
      url: toFileUrl(filePath),
      duration: metadata?.format.duration || 0,
      cover: picture ? coverDataUrl(picture) : null
    });
  }

  const embeddedCover = tracks.find(track => track.cover)?.cover || null;
  const folderArtwork = selectFolderArtwork(files);
  return {
    id: `local-${stableId(albumPath)}`,
    sourcePath: albumPath,
    title: mostCommon(albumNames) || path.basename(albumPath),
    artist: mostCommon(artists) || mostCommon(albumArtists) || '本地导入',
    albumArtist: mostCommon(albumArtists) || '',
    rjCode: extractRjCode(albumPath, path.basename(albumPath), path.basename(audioPaths[0] || '')),
    group: '本地文件夹',
    genre: '未分类',
    duration: tracks.length,
    totalDuration: tracks.reduce((total, track) => total + track.duration, 0),
    played: 0,
    favorite: false,
    date: Date.now(),
    tracks,
    localCover: embeddedCover || (folderArtwork ? toFileUrl(folderArtwork) : null),
    color: ['#c4b8e8', '#4b416c'],
    shape: 'radio'
  };
}

function groupFilesByFolder(files) {
  const groups = new Map();
  for (const filePath of files) {
    const albumPath = path.dirname(filePath);
    if (!groups.has(albumPath)) groups.set(albumPath, []);
    groups.get(albumPath).push(filePath);
  }
  return groups;
}

async function scanFolder(folderPath, files, onProgress) {
  const groups = groupFilesByFolder(files);
  const albums = [];
  let processed = 0;
  for (const [albumPath, albumFiles] of groups) {
    try {
      const album = await scanAlbum(albumPath, albumFiles);
      if (album) albums.push(album);
    } catch (error) {
      // 单张专辑扫描失败不应中断整个导入
      console.error('[import] 专辑扫描失败，已跳过', albumPath, error.message);
    }
    processed += 1;
    if (onProgress) onProgress(processed);
  }
  return albums;
}

async function importAudioFolder(win) {
  console.log('[import] opening native folder dialog');
  if (win && !win.isDestroyed()) win.focus();
  const options = {
    title: '导入音声文件夹',
    buttonLabel: '导入',
    properties: ['openDirectory', 'multiSelections']
  };
  const result = win && !win.isDestroyed()
    ? await dialog.showOpenDialog(win, options)
    : await dialog.showOpenDialog(options);
  console.log('[import] dialog result', result.canceled, result.filePaths.length || 'none');
  if (result.canceled || !result.filePaths.length) return { canceled: true, albums: [] };

  // 预扫描统计每个文件夹的专辑数（只列目录，不解析元数据，速度快）
  const folderFiles = [];
  for (const folderPath of result.filePaths) {
    folderFiles.push({ folderPath, files: await findFiles(folderPath) });
  }
  const totalAlbums = folderFiles.reduce((sum, item) => sum + groupFilesByFolder(item.files).size, 0);

  const albums = [];
  let processed = 0;
  const folderTotal = folderFiles.length;
  const sendProgress = folderIndex => {
    if (!win || win.isDestroyed()) return;
    win.webContents.send('import:progress', { folderIndex, folderTotal, processed, total: totalAlbums });
  };
  sendProgress(0);
  for (let i = 0; i < folderFiles.length; i += 1) {
    const { folderPath, files } = folderFiles[i];
    const folderAlbums = await scanFolder(folderPath, files, () => {
      processed += 1;
      sendProgress(i + 1);
    });
    albums.push(...folderAlbums);
  }
  const existing = await loadLibrary();
  const merged = new Map(existing.map(album => [album.id, album]));
  albums.forEach(album => merged.set(album.id, album));
  await saveLibrary([...merged.values()]);
  return { canceled: false, albums, scannedPath: result.filePaths[0] };
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 980,
    minHeight: 680,
    titleBarStyle: 'hiddenInset',
    backgroundColor: '#f6f5f2',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: false }
  });
  win.webContents.on('console-message', (_event, level, message) => {
    console.log(`[renderer:${level}] ${message}`);
  });
  win.webContents.on('preload-error', (_event, preloadPath, error) => {
    console.error(`Preload failed: ${preloadPath}`, error);
  });
  win.loadFile(path.join(__dirname, 'index.html'));
}

ipcMain.handle('library:removeAlbums', async (_event, { ids, deleteFiles }) => {
  const idSet = new Set((Array.isArray(ids) ? ids : []).map(String));
  if (!idSet.size) return { ok: true, removed: 0, deletedFiles: 0 };
  const albums = await loadLibrary();
  const removed = albums.filter(a => idSet.has(String(a.id)));
  const kept = albums.filter(a => !idSet.has(String(a.id)));
  let deletedFiles = 0;
  if (deleteFiles) {
    for (const album of removed) {
      const targets = new Set();
      for (const track of album.tracks || []) {
        if (track.url && track.url.startsWith('file:')) targets.add(fileURLToPath(track.url));
      }
      if (album.localCover && album.localCover.startsWith('file:')) targets.add(fileURLToPath(album.localCover));
      for (const filePath of targets) {
        try { await fs.rm(filePath, { force: true }); deletedFiles += 1; } catch { /* 文件可能已不存在 */ }
      }
      if (album.sourcePath) {
        try { await fs.rmdir(album.sourcePath); } catch { /* 目录非空则保留 */ }
      }
    }
  }
  await saveLibrary(kept);
  return { ok: true, removed: removed.length, deletedFiles };
});

// ---- DLsite 标签刮削 ----
function scrapeConfigPath() {
  return path.join(app.getPath('userData'), 'scrape-config.json');
}
async function loadScrapeConfig() {
  try {
    return JSON.parse(await fs.readFile(scrapeConfigPath(), 'utf8'));
  } catch {
    return { proxy: 'http://127.0.0.1:7890' };
  }
}
async function saveScrapeConfig(config) {
  await fs.mkdir(path.dirname(scrapeConfigPath()), { recursive: true });
  await fs.writeFile(scrapeConfigPath(), JSON.stringify({ proxy: String(config?.proxy || '') }, null, 2));
}
async function fetchWithProxy(url, proxy) {
  const headers = { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36' };
  // 优先使用系统代理直连
  try {
    const res = await net.fetch(url, { headers });
    if (res.ok) return await res.text();
  } catch { /* 落到显式代理 */ }
  if (proxy) {
    const s = session.defaultSession;
    await s.setProxy({ proxyRules: proxy });
    try {
      const res = await net.fetch(url, { headers });
      if (res.ok) return await res.text();
    } finally {
      await s.setProxy({ proxyRules: '' }); // 恢复系统代理
    }
  }
  throw new Error('无法连接 DLsite');
}
function parseDlsiteTags(html) {
  const tags = [];
  const regex = /genre\/\d+\/from\/work\.genre\/ana_flg\/all"[^>]*>([^<]+)<\/a>/gi;
  let match;
  while ((match = regex.exec(html)) !== null) {
    const tag = match[1].trim();
    if (tag && !tags.includes(tag)) tags.push(tag);
  }
  return tags;
}
function parseDlsiteTitle(html) {
  const match = html.match(/id="work_name"[^>]*>([^<]+)</);
  return match ? match[1].trim() : null;
}

ipcMain.handle('dlsite:scrape', async (event, { ids, force }) => {
  const idSet = new Set((Array.isArray(ids) ? ids : []).map(String));
  const albums = await loadLibrary();
  const targets = [];
  let noRj = 0;
  for (const album of albums) {
    if (!idSet.has(String(album.id))) continue;
    const rj = albumRjCode(album);
    if (!rj) { noRj += 1; continue; }
    album.rjCode = rj;
    targets.push(album);
  }
  const win = BrowserWindow.fromWebContents(event.sender);
  const config = await loadScrapeConfig();
  const results = { scraped: 0, failed: 0, skipped: 0, noRj, details: [] };
  let processed = 0;
  const sendProgress = () => {
    if (!win || win.isDestroyed()) return;
    win.webContents.send('dlsite:progress', { processed, total: targets.length });
  };
  sendProgress();
  for (const album of targets) {
    processed += 1;
    if (!force && Array.isArray(album.tags) && album.tags.length) {
      results.skipped += 1;
      sendProgress();
      continue;
    }
    try {
      const html = await fetchWithProxy(`https://www.dlsite.com/maniax/work/=/product_id/${album.rjCode}.html`, config.proxy);
      const tags = parseDlsiteTags(html);
      const title = parseDlsiteTitle(html);
      album.tags = tags;
      album.dlsiteTitle = title;
      results.details.push({ id: album.id, rj: album.rjCode, tags, title });
      if (tags.length) results.scraped += 1;
      else results.failed += 1;
    } catch (error) {
      results.failed += 1;
      results.details.push({ id: album.id, rj: album.rjCode, error: error.message });
    }
    await new Promise(resolve => setTimeout(resolve, 400)); // 礼貌限速
    sendProgress();
  }
  await saveLibrary(albums);
  return results;
});
ipcMain.handle('scrape:getConfig', () => loadScrapeConfig());
ipcMain.handle('scrape:setConfig', async (_event, config) => {
  await saveScrapeConfig(config);
  return loadScrapeConfig();
});

// 在 Finder 中打开专辑所在文件夹
ipcMain.handle('library:revealInFolder', async (_event, id) => {
  const albums = await loadLibrary();
  const album = albums.find(a => String(a.id) === String(id));
  if (!album) return { ok: false, error: 'not-found' };
  if (album.sourcePath) {
    const error = await shell.openPath(album.sourcePath);
    return { ok: !error, error: error || null };
  }
  const track = (album.tracks || []).find(t => t.url && t.url.startsWith('file:'));
  if (track) {
    shell.showItemInFolder(fileURLToPath(track.url));
    return { ok: true };
  }
  return { ok: false, error: '无本地文件' };
});

ipcMain.handle('library:load', () => loadLibrary());
ipcMain.handle('library:saveAlbums', async (_event, albums) => {
  if (Array.isArray(albums)) await saveLibrary(albums);
  return { ok: true };
});
ipcMain.handle('library:removeAlbum', async (_event, { id, deleteFiles }) => {
  const albums = await loadLibrary();
  const album = albums.find(a => String(a.id) === String(id));
  if (!album) return { ok: false, reason: 'not-found' };
  const kept = albums.filter(a => String(a.id) !== String(id));
  let deletedFiles = 0;
  if (deleteFiles) {
    const targets = new Set();
    for (const track of album.tracks || []) {
      if (track.url && track.url.startsWith('file:')) targets.add(fileURLToPath(track.url));
    }
    if (album.localCover && album.localCover.startsWith('file:')) targets.add(fileURLToPath(album.localCover));
    for (const filePath of targets) {
      try { await fs.rm(filePath, { force: true }); deletedFiles += 1; } catch { /* 文件可能已不存在 */ }
    }
    if (album.sourcePath) {
      try { await fs.rmdir(album.sourcePath); } catch { /* 目录非空则保留 */ }
    }
  }
  await saveLibrary(kept);
  return { ok: true, deletedFiles };
});
ipcMain.handle('library:cleanMissing', async () => {
  const albums = await loadLibrary();
  let removedAlbums = 0;
  let removedTracks = 0;
  const kept = [];
  for (const album of albums) {
    const tracks = Array.isArray(album.tracks) ? album.tracks : [];
    const alive = [];
    for (const track of tracks) {
      if (track.url && track.url.startsWith('file:')) {
        try {
          await fs.access(fileURLToPath(track.url));
          alive.push(track);
        } catch {
          removedTracks += 1;
        }
      } else {
        alive.push(track);
      }
    }
    let localCover = album.localCover;
    if (localCover && localCover.startsWith('file:')) {
      try {
        await fs.access(fileURLToPath(localCover));
      } catch {
        localCover = null;
      }
    }
    if (alive.length === 0 && tracks.length > 0) {
      removedAlbums += 1;
      continue;
    }
    kept.push(alive.length === tracks.length ? album : { ...album, tracks: alive, duration: alive.length, localCover });
  }
  await saveLibrary(kept);
  return { removedAlbums, removedTracks };
});
ipcMain.handle('app:version', () => app.getVersion());
ipcMain.handle('app:openDataDir', () => shell.openPath(path.dirname(libraryPath())));
ipcMain.handle('library:importFolder', event => {
  console.log('[ipc] library:importFolder received');
  return importAudioFolder(BrowserWindow.fromWebContents(event.sender));
});

app.whenReady().then(() => {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: app.name, submenu: [{ role: 'about' }, { type: 'separator' }, { role: 'quit' }] },
    { label: '文件', submenu: [{ label: '导入音声文件夹', accelerator: 'CmdOrCtrl+O', click: () => {
      BrowserWindow.getFocusedWindow()?.webContents.send('library:requestImport');
    }}] },
    { label: '视图', submenu: [{ role: 'reload' }, { role: 'toggleDevTools' }] }
  ]));
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
