const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('kikoeru', {
  loadLibrary: () => ipcRenderer.invoke('library:load'),
  removeAlbums: (ids, deleteFiles) => ipcRenderer.invoke('library:removeAlbums', { ids, deleteFiles }),
  saveAlbums: albums => ipcRenderer.invoke('library:saveAlbums', albums),
  removeAlbum: (id, deleteFiles) => ipcRenderer.invoke('library:removeAlbum', { id, deleteFiles }),
  cleanMissing: () => ipcRenderer.invoke('library:cleanMissing'),
  getVersion: () => ipcRenderer.invoke('app:version'),
  openDataDir: () => ipcRenderer.invoke('app:openDataDir'),
  importAudioFolder: () => {
    console.log('[preload] requesting folder import');
    return ipcRenderer.invoke('library:importFolder');
  },
  onImportRequested: callback => ipcRenderer.on('library:requestImport', callback),
  onImportProgress: callback => ipcRenderer.on('import:progress', (_event, data) => callback(data)),
  scrapeDlsite: (ids, force) => ipcRenderer.invoke('dlsite:scrape', { ids, force }),
  onDlsiteProgress: callback => ipcRenderer.on('dlsite:progress', (_event, data) => callback(data)),
  getScrapeConfig: () => ipcRenderer.invoke('scrape:getConfig'),
  setScrapeConfig: config => ipcRenderer.invoke('scrape:setConfig', config),
  revealInFolder: id => ipcRenderer.invoke('library:revealInFolder', id)
});
