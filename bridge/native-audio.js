/**
 * Kikoeru Android 播放 shim：把 app.js 对 <audio id="audio"> 的调用桥接到原生 Media3 引擎。
 * 由 scripts/sync-web.js 拷贝到 web/ 并在 app.js 之前加载。
 *
 * 只对 '#audio' 这一个 selector 做特判返回 shim，其余 document.querySelector 行为不变。
 */
(() => {
  if (!window.Capacitor) return;
  const cap = window.Capacitor;
  const plugin = cap.Plugins && cap.Plugins.Kikoeru;

  class NativeAudio {
    constructor() {
      this._paused = true;
      this._duration = 0;
      this._currentTime = 0;
      this._volume = 1;
      this._muted = false;
      this._src = '';
      this._listeners = new Map();
      this._observeNowPlaying();
    }

    // ---- EventTarget 近似 ----
    addEventListener(type, cb) {
      if (!this._listeners.has(type)) this._listeners.set(type, new Set());
      this._listeners.get(type).add(cb);
    }
    removeEventListener(type, cb) {
      const set = this._listeners.get(type);
      if (set) set.delete(cb);
    }
    _dispatch(type, data = {}) {
      const cbs = this._listeners.get(type);
      if (!cbs) return;
      const event = Object.assign({ type }, data);
      cbs.forEach(cb => {
        try { cb(event); } catch (e) { console.error('[native-audio] listener error', e); }
      });
    }

    // ---- 属性 ----
    get paused() { return this._paused; }
    get duration() { return this._duration; }
    get currentTime() { return this._currentTime; }
    set currentTime(value) {
      this._currentTime = value;
      if (plugin) plugin.playbackSeek({ position: value }).catch(() => {});
    }
    get volume() { return this._muted ? 0 : this._volume; }
    set volume(value) {
      this._volume = value;
      if (plugin) plugin.playbackVolume({ volume: value }).catch(() => {});
    }
    get muted() { return this._muted; }
    set muted(value) {
      this._muted = value;
      if (plugin) plugin.playbackVolume({ volume: value ? 0 : this._volume }).catch(() => {});
    }
    get src() { return this._src; }
    set src(url) {
      if (!url || url === this._src) return;
      this._src = url;
      this._currentTime = 0;
      this._duration = 0;
      if (plugin) plugin.playbackLoad({ uri: url }).catch(() => {});
      this._dispatch('emptied');
    }

    // ---- 方法 ----
    play() {
      this._paused = false;
      if (plugin) {
        if (!window.__kikoeruNotifRequested) {
          window.__kikoeruNotifRequested = true;
          plugin.requestNotificationPermission().catch(() => {});
        }
        return plugin.playbackPlay().catch(() => { this._paused = true; });
      }
      return Promise.resolve();
    }
    pause() {
      this._paused = true;
      if (plugin) plugin.playbackPause().catch(() => {});
      this._dispatch('pause');
    }
    load() {}

    // ---- 原生事件 → DOM 事件 ----
    bindNative() {
      // 注意：必须用插件的 addListener（Capacitor.Plugins.Kikoeru.addListener），
      // 全局 Capacitor.addListener 不会注册到插件事件表，事件收不到。
      const listen = (name, handler) => {
        if (!plugin || !plugin.addListener) return;
        const handle = plugin.addListener(name, data => handler(data || {}));
        if (handle && typeof handle.catch === 'function') handle.catch(() => {});
      };
      listen('audio:timeupdate', ({ currentTime, duration }) => {
        this._currentTime = currentTime || 0;
        if (duration && duration !== this._duration) this._duration = duration;
        this._dispatch('timeupdate');
      });
      listen('audio:loadedmetadata', ({ duration }) => {
        if (duration) this._duration = duration;
        this._dispatch('loadedmetadata');
      });
      listen('audio:state', ({ playing }) => {
        const wasPaused = this._paused;
        this._paused = !playing;
        if (playing && wasPaused) this._dispatch('play');
        if (!playing && !wasPaused) this._dispatch('pause');
      });
      listen('audio:ended', () => {
        this._paused = true;
        this._dispatch('ended');
      });
      listen('audio:command', ({ command }) => {
        if (command === 'next') document.getElementById('nextBtn')?.click();
        else if (command === 'prev') document.getElementById('prevBtn')?.click();
      });
    }

    // ---- 观察播放条，把元数据推给原生（通知/锁屏封面标题） ----
    _observeNowPlaying() {
      const read = () => {
        try {
          if (!plugin || !plugin.playbackMetadata) return;
          const title = document.querySelector('#nowTitle')?.textContent || '';
          const artist = document.querySelector('#nowArtist')?.textContent || '';
          const img = document.querySelector('#nowCover img');
          const cover = img ? (img.getAttribute('src') || img.src) : '';
          plugin.playbackMetadata({ title, artist, cover }).catch(() => {});
        } catch (e) { /* 观察回调异常不应影响播放 */ }
      };
      const start = () => {
        const target = document.querySelector('#nowTitle');
        if (!target) {
          setTimeout(start, 300);
          return;
        }
        read();
        const observer = new MutationObserver(read);
        ['#nowTitle', '#nowArtist', '#nowCover'].forEach(sel => {
          const el = document.querySelector(sel);
          if (el) observer.observe(el, { childList: true, subtree: true, attributes: true });
        });
      };
      setTimeout(start, 0);
    }
  }

  const shim = new NativeAudio();
  shim.bindNative();

  // 让 $('#audio') / getElementById('audio') 返回 shim（只特判这一个 id）
  const docQuery = Document.prototype.querySelector;
  Document.prototype.querySelector = function (selector) {
    if (selector === '#audio') return shim;
    return docQuery.call(this, selector);
  };
  const docGet = Document.prototype.getElementById;
  Document.prototype.getElementById = function (id) {
    if (id === 'audio') return shim;
    return docGet.call(this, id);
  };

  // 移除真实 <audio> 元素（若有）
  document.addEventListener('DOMContentLoaded', () => {
    const real = docGet.call(document, 'audio');
    if (real) real.remove();
  });
})();
