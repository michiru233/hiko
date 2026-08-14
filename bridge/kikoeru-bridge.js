/**
 * Kikoeru Android 桥接层：在 Capacitor WebView 中实现 window.kikoeru。
 * 签名与 desktop 的 preload.js 保持一一对应（接口契约见 .zcode/plans/plan-kikoeru-android-capacitor.md）。
 * 由 scripts/sync-web.js 拷贝到 web/ 并在 app.js 之前加载。
 */
(() => {
  if (window.kikoeru) return;

  document.documentElement.dataset.platform = 'android';

  const cap = window.Capacitor;

  // 移动端布局激活：Android 实机 WebView 视口差异大，不依赖固定断点，
  // 按"较宽阈值 + 触屏"判定；旋转时跟随 innerWidth 更新。
  const applyMobile = () => {
    const isMobile = window.innerWidth <= 1000;
    document.documentElement.classList.toggle('mobile', isMobile);
    document.documentElement.classList.toggle('desktop', !isMobile);
    return isMobile;
  };
  applyMobile();
  window.addEventListener('resize', applyMobile);
  window.addEventListener('orientationchange', () => setTimeout(applyMobile, 300));
  window.__kikoeruMobileHandled = true;

  // Android 系统返回手势/按键：逐层关闭浮层（确认框→右键菜单→多选→设置→详情→抽屉），
  // 无浮层时最小化到后台（等同系统默认返回）。
  const closeTopOverlay = () => {
    const q = sel => document.querySelector(sel);
    if (q('#confirmOverlay')?.classList.contains('open')) { q('#confirmCancel')?.click(); return true; }
    if (q('#ctxMenu')?.classList.contains('open')) { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })); return true; }
    if (q('#multiBar')?.classList.contains('open')) { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })); return true; }
    if (q('#settingsOverlay')?.classList.contains('open')) { q('#settingsClose')?.click(); return true; }
    if (q('#details')?.classList.contains('open')) { q('#closeDetail')?.click(); return true; }
    const win = q('.window');
    if (document.documentElement.classList.contains('mobile') && win && !win.classList.contains('sidebar-hidden')) {
      q('#sidebarToggle')?.click();
      return true;
    }
    return false;
  };
  const appPlugin = cap && cap.Plugins && cap.Plugins.App;
  if (appPlugin && appPlugin.addListener) {
    appPlugin.addListener('backButton', () => {
      if (!closeTopOverlay() && appPlugin.minimizeApp) appPlugin.minimizeApp();
    });
  }

  const plugin = cap && cap.Plugins && cap.Plugins.Kikoeru;

  function unwrap(result) {
    if (result && typeof result === 'object' && 'value' in result && Object.keys(result).length === 1) {
      return result.value;
    }
    return result;
  }

  function call(method, ...args) {
    if (!plugin || typeof plugin[method] !== 'function') {
      return Promise.reject(new Error(`Kikoeru 原生插件 ${method} 未就绪`));
    }
    return plugin[method](...args).then(unwrap);
  }

  const notImplemented = method => Promise.reject(new Error(`${method} 尚未实现（开发中）`));

  window.kikoeru = {
    platform: 'android',
    isAndroid: true,

    // ---- M0：库持久化 / 版本 ----
    loadLibrary: () => call('loadLibrary').then(r => (r && r.albums) || []),
    saveAlbums: albums => call('saveAlbums', { albums }),
    getVersion: () => call('getVersion').then(r => (r && r.version) || '0.0.0'),

    // ---- M1：导入（SAF 树选择，返回与桌面同构）----
    importAudioFolder: () => call('importAudioFolder').then(r => ({
      canceled: r.canceled !== false,
      albums: r.albums || [],
      scannedPath: r.scannedPath || null,
    })),

    // ---- M4：数据操作 ----
    removeAlbum: (id, deleteFiles) => call('removeAlbum', { id, deleteFiles }),
    removeAlbums: (ids, deleteFiles) => call('removeAlbums', { ids, deleteFiles }),
    cleanMissing: () => call('cleanMissing'),
    openDataDir: () => call('openDataDir'),
    revealInFolder: id => call('revealInFolder', { id }),

    // ---- M3：刮削 ----
    scrapeDlsite: (ids, force) => call('scrapeDlsite', { ids, force }),
    getScrapeConfig: () => call('getScrapeConfig').then(r => ({ proxy: (r && r.proxy) || '' })),
    setScrapeConfig: config => call('setScrapeConfig', { proxy: (config && config.proxy) || '' }).then(() => ({ proxy: (config && config.proxy) || '' })),

    // ---- 事件（与 desktop IPC 事件同名同结构；用插件级 addListener 才能收到 notifyListeners）----
    onImportRequested: () => {}, // Android 无桌面菜单，空实现
    onImportProgress: cb => plugin && plugin.addListener('import:progress', data => cb(data)),
    onDlsiteProgress: cb => plugin && plugin.addListener('dlsite:progress', data => cb(data)),
  };
})();
