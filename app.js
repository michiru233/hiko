const albums=[];
let activeFilter='all',activeView='全部音声',selected=null,playing=true;const $=s=>document.querySelector(s),grid=$('#albumGrid');
const audio=$('#audio');
let importedQueue=[],queueIndex=-1,playMode=localStorage.getItem('kikoeru-mode')||'list';
let multiSelect=false;const multiIds=new Set();
let volume=Number(localStorage.getItem('kikoeru-volume')||0.8);
audio.volume=volume;
function coverSvg(a){const[c1,c2]=a.color;const sh={moon:`<circle cx="76" cy="76" r="30" fill="${c1}"/><circle cx="87" cy="68" r="27" fill="${c2}"/><circle cx="128" cy="34" r="2" fill="#fff"/><circle cx="110" cy="54" r="1.5" fill="#fff"/>`,window:`<rect x="34" y="25" width="84" height="104" rx="3" fill="#f4d7ca"/><path d="M76 25v104M34 76h84" stroke="${c2}" stroke-width="3" opacity=".45"/>`,radio:`<rect x="38" y="46" width="76" height="55" rx="8" fill="#e6f4ec"/><circle cx="76" cy="73" r="16" fill="${c2}"/><circle cx="76" cy="73" r="6" fill="#d2ecdc"/>`,cat:`<path d="M40 111L49 55l20 16 14-18 24 17 8 41z" fill="#fff1c8"/><circle cx="65" cy="82" r="3" fill="${c2}"/><circle cx="91" cy="82" r="3" fill="${c2}"/>`,star:`<path d="M76 27l10 30 31 1-24 19 8 30-25-17-25 17 8-30-24-19 31-1z" fill="#e9ddff"/><circle cx="76" cy="75" r="11" fill="${c2}"/>`,herb:`<path d="M76 130V61M76 90C50 83 48 64 48 64s19-2 28 19M76 76c23-11 30-29 30-29s-21 2-30 19" fill="none" stroke="#f1f6d8" stroke-width="7" stroke-linecap="round"/>`,sea:`<path d="M0 102q30-22 60 0t60 0t60 0v60H0z" fill="#d4f0f1"/><path d="M0 115q30-22 60 0t60 0t60 0" fill="none" stroke="#fff" stroke-width="3"/><circle cx="135" cy="39" r="20" fill="#fff1ba"/>`,book:`<path d="M33 47q22-9 43 7v64q-21-15-43-5zM119 47q-22-9-43 7v64q21-15 43-5z" fill="#f8f2ed"/><path d="M76 54v63" stroke="${c2}" stroke-width="3"/>`,heart:`<path d="M76 119C35 91 42 54 62 54c8 0 13 5 14 11 2-6 7-11 15-11 20 0 27 37-15 65z" fill="#ffe4df" stroke="${c2}" stroke-width="3"/>`,pillow:`<rect x="38" y="49" width="76" height="51" rx="24" fill="#eee7ff" transform="rotate(-8 76 75)"/>`,fire:`<path d="M76 119c-20-16-14-34 0-48 2 12 10 15 9 25 10-13 14-25 7-39 24 22 24 45 1 62z" fill="#ffd7a6"/><path d="M76 115c-11-12-6-24 1-31 2 8 6 11 8 16 5-8 4-14 3-19 13 14 9 28-12 34z" fill="#e98062"/>`,sun:`<circle cx="76" cy="77" r="24" fill="#fff6ca"/><g stroke="#fff6ca" stroke-width="4" stroke-linecap="round"><path d="M76 31v13M76 110v13M30 77h13M109 77h13M43 44l9 9M100 101l9 9M109 44l-9 9M52 101l-9 9"/></g>`};return`<svg viewBox="0 0 152 152" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="g${a.id}" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/></linearGradient></defs><rect width="152" height="152" fill="url(#g${a.id})"/><circle cx="128" cy="125" r="48" fill="#ffffff18"/><circle cx="23" cy="18" r="36" fill="#ffffff10"/>${sh[a.shape]}<text x="12" y="142" fill="#ffffffb8" font-family="sans-serif" font-size="8" letter-spacing="1.6">KIKOERU · ${String(a.id).padStart(2,'0')}</text></svg>`}
function filtered(){let d=albums.filter(a=>{if(activeView==='收藏夹'&&!a.favorite)return false;if(['ASMR','剧情向','治愈系','环境音'].includes(activeView)&&a.genre!==activeView)return false;if(activeFilter==='unplayed'&&a.played>=a.duration)return false;if(activeFilter==='favorite'&&!a.favorite)return false;const q=$('#searchInput').value.trim().toLowerCase();return!q||[a.title,a.artist,a.group,a.genre].some(v=>v.toLowerCase().includes(q))});const s=$('#sortSelect').value;if(s==='title')d.sort((a,b)=>a.title.localeCompare(b.title));if(s==='duration')d.sort((a,b)=>b.duration-a.duration);return d}
function render(){const d=filtered();$('#resultText').textContent=`显示 ${d.length} 张专辑`;$('#clearBtn').style.display=($('#searchInput').value||activeFilter!=='all'||activeView!=='全部音声')?'block':'none';$('#countAll').textContent=albums.length;$('#countFav').textContent=albums.filter(a=>a.favorite).length;$('#countAsmr').textContent=albums.filter(a=>a.genre==='ASMR').length;$('#countStory').textContent=albums.filter(a=>a.genre==='剧情向').length;$('#countHeal').textContent=albums.filter(a=>a.genre==='治愈系').length;$('#countAmbient').textContent=albums.filter(a=>a.genre==='环境音').length;$('#heroCount').textContent=albums.filter(a=>a.favorite).length;grid.innerHTML=d.length?d.map((a,i)=>`<article class="album-card${multiSelect&&multiIds.has(String(a.id))?' selected':''}" data-id="${a.id}" style="animation-delay:${i*35}ms"><div class="cover-wrap">${multiSelect?`<button class="multi-check${multiIds.has(String(a.id))?' on':''}" data-multi="${a.id}">${multiIds.has(String(a.id))?'✓':''}</button>`:''}${coverSvg(a)}<div class="cover-overlay"><button class="quick-play" data-play="${a.id}">▶</button><button class="fav" data-fav="${a.id}">${a.favorite?'♥':'♡'}</button></div></div><div class="album-info"><div class="album-title">${a.title}${a.albumArtist?`<span class="artist-inline">${a.albumArtist}</span>`:''}</div><div class="album-sub">${a.artist} · ${a.group}</div><div class="tags"><span class="tag purple">${a.genre}</span><span class="tag">${a.totalDuration?formatDuration(a.totalDuration):`${a.duration} 首`}</span></div>${a.tags&&a.tags.length?`<div class="tags dlsite-tags">${a.tags.slice(0,3).map(t=>`<span class="tag teal">${t}</span>`).join('')}${a.tags.length>3?`<span class="tag teal more">+${a.tags.length-3}</span>`:''}</div>`:''}</div></article>`).join(''):(albums.length?`<div class="empty"><strong>没有找到匹配的音声</strong><span>试试其他关键词或清除筛选条件</span></div>`:`<div class="empty"><strong>还没有导入任何音声</strong><span>点击右上角 ↥ 按钮，选择你的音声文件夹</span></div>`);document.querySelectorAll('.album-card').forEach(c=>c.addEventListener('click',e=>{if(e.target.closest('[data-play]')||e.target.closest('[data-fav]')||e.target.closest('[data-multi]'))return;const a=albums.find(x=>String(x.id)===String(c.dataset.id));if(multiSelect){toggleMulti(String(a.id));return;}openDetail(a)}));document.querySelectorAll('[data-play]').forEach(b=>b.addEventListener('click',e=>{e.stopPropagation();selected=albums.find(x=>x.id==b.dataset.play);playing=true;updatePlayer()}));document.querySelectorAll('[data-fav]').forEach(b=>b.addEventListener('click',e=>{e.stopPropagation();const a=albums.find(x=>x.id==b.dataset.fav);a.favorite=!a.favorite;if(window.kikoeru?.saveAlbums)window.kikoeru.saveAlbums(albums);render()}));document.querySelectorAll('[data-multi]').forEach(b=>b.addEventListener('click',e=>{e.stopPropagation();toggleMulti(b.dataset.multi)}))}
function albumCover(a){return a.currentCover||a.localCover||null}
function openDetail(a){
  selected=a;
  const sourceCover=albumCover(a); const detailCover=sourceCover?`<img src="${sourceCover}" alt="${a.title}" />`:coverSvg(a);
  const tracks=a.tracks||[{name:`序章 · ${a.title}`},{name:'午后的阳光'},{name:'轻声的约定'}];
  const progress=a.totalDuration?Math.round((a.played/(a.totalDuration||1))*100):0;
  $('#detailContent').innerHTML=`<div class="detail-cover">${detailCover}</div><div class="detail-kicker">${a.genre.toUpperCase()} · ALBUM ${String(a.id).padStart(2,'0')}</div><h2>${a.title}${a.albumArtist?`<span class="artist-inline">${a.albumArtist}</span>`:''}</h2><div class="detail-artist">${a.artist} · ${a.group}</div><div class="detail-actions"><button class="primary" id="detailPlay">▶ 从头播放</button><button class="secondary" id="detailFav">${a.favorite?'♥ 已收藏':'♡ 收藏'}</button></div><div class="detail-row"><span>总时长</span><strong>${a.tracks?`${tracks.length} 首${a.totalDuration?` · ${formatDuration(a.totalDuration)}`:''}`:`${a.duration} 分钟`}</strong></div><div class="detail-row"><span>完成进度</span><strong>${progress}%</strong></div>${a.tags&&a.tags.length?`<div class="detail-tags">${a.tags.map(t=>`<span class="tag teal">${t}</span>`).join('')}</div>`:''}${albumRj(a)?`<div class="detail-rj">DLsite ${albumRj(a)}${a.dlsiteTitle?` · ${a.dlsiteTitle}`:''}</div>`:''}<div class="track-list">${tracks.map((t,i)=>{const active=a.tracks&&selected===a&&queueIndex===i;return`<div class="track ${active?'active':''}" data-track-row="${i}"><button class="track-play" data-track-play="${i}" title="${active&&!audio.paused?'暂停':'播放'}">${active&&!audio.paused?'Ⅱ':'▶'}</button><span class="track-no">${String(i+1).padStart(2,'0')}</span><span class="track-title">${t.name}</span><span class="track-time">${t.duration?formatTime(t.duration):'--:--'}</span></div>`}).join('')}</div>`;
  $('#details').classList.add('open');
  $('#detailPlay').onclick=()=>{if(a.tracks)chooseImported(a,0);else{playing=true;updatePlayer()};};
  $('#detailFav').onclick=()=>{a.favorite=!a.favorite;if(window.kikoeru?.saveAlbums)window.kikoeru.saveAlbums(albums);openDetail(a);render()};
  document.querySelectorAll('[data-track-play]').forEach(button=>button.addEventListener('click',e=>{
    e.stopPropagation();
    const index=Number(button.dataset.trackPlay);
    if(a.tracks){
      if(selected===a&&queueIndex===index&&!audio.paused){audio.pause();playing=false;openDetail(a);return;}
      chooseImported(a,index);
    }
  }));
}
function formatTime(seconds){if(!Number.isFinite(seconds)||seconds<0)return'00:00';const min=Math.floor(seconds/60);const sec=Math.floor(seconds%60).toString().padStart(2,'0');return`${min}:${sec}`}
function formatDuration(seconds){if(!Number.isFinite(seconds)||seconds<=0)return'--';const totalMin=Math.round(seconds/60);const h=Math.floor(totalMin/60),m=totalMin%60;if(h&&m)return`${h}小时${m}分钟`;if(h)return`${h}小时`;return`${m}分钟`;}
function updateTimeline(current=audio.currentTime||0,total=audio.duration||selected.tracks?.[queueIndex]?.duration||0){$('#currentTime').textContent=formatTime(current);$('#totalTime').textContent=formatTime(total);const pct=total?Math.max(0,Math.min(100,current/total*100)):0;if(total){$('#progressInput').value=pct;$('#progressInput').style.setProperty('--fill',pct+'%');}}
function updatePlayer(){if(!selected){$('#nowCover').innerHTML='';$('#nowTitle').textContent='未在播放';$('#nowArtist').textContent='';$('#playBtn').textContent='▶';updateTimeline(0,0);return;}const sourceCover=albumCover(selected);const cover=sourceCover?`<img src="${sourceCover}" alt="${selected.title}" />`:coverSvg(selected);$('#nowCover').innerHTML=cover;$('#nowTitle').textContent=`${selected.title} · ${queueIndex>=0?String(queueIndex+1).padStart(2,'0'):'01'}`;$('#nowArtist').textContent=`${selected.artist} · ${importedQueue[queueIndex]?.name||'待选择音频'}`;$('#playBtn').textContent=playing?'Ⅱ':'▶';updateTimeline();if($('#details').classList.contains('open')&&selected.tracks)openDetail(selected)}
document.querySelectorAll('.nav-item[data-view]').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.nav-item').forEach(x=>x.classList.remove('active'));b.classList.add('active');activeView=b.dataset.view;$('#viewTitle').textContent=activeView;$('#heroTitle').textContent=activeView;render()}));document.querySelectorAll('.filter').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.filter').forEach(x=>x.classList.remove('active'));b.classList.add('active');activeFilter=b.dataset.filter;render()}));$('#searchInput').addEventListener('input',render);$('#sortSelect').addEventListener('change',render);$('#clearBtn').addEventListener('click',()=>{$('#searchInput').value='';activeFilter='all';activeView='全部音声';document.querySelectorAll('.filter').forEach(x=>x.classList.toggle('active',x.dataset.filter==='all'));$('#viewTitle').textContent='全部音声';$('#heroTitle').textContent='全部音声';render()});$('#closeDetail').onclick=()=>$('#details').classList.remove('open');$('#playBtn').onclick=()=>{playing=!playing;updatePlayer()};document.addEventListener('keydown',e=>{if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='k'){e.preventDefault();$('#searchInput').focus()}});render();updatePlayer();

// Local folder import and real audio playback.
$('#volumeInput').value = Math.round(volume * 100);
$('#volumeValue').textContent = `${Math.round(volume * 100)}%`;
function setVolume(value){
  volume = Math.max(0, Math.min(1, value)); audio.volume = volume; audio.muted = volume === 0;
  $('#volumeInput').value = Math.round(volume * 100); $('#volumeValue').textContent = `${Math.round(volume * 100)}%`;
  $('#volumeBtn').textContent = volume === 0 ? '◖̸' : volume < .5 ? '◔' : '◖';
  localStorage.setItem('kikoeru-volume', String(volume));
}
const audioExt = /\.(mp3|m4a|wav|flac|ogg|aac|opus|webm)$/i;
const imageExt = /\.(jpg|jpeg|png|webp|gif)$/i;
function safeId(value){ return `local-${value.toLowerCase().replace(/[^a-z0-9]+/g,'-')}-${Date.now()}`; }
function chooseImported(album, index=0){
  if(!album.tracks?.length) return;
  importedQueue = album.tracks; queueIndex = Math.max(0, Math.min(index, importedQueue.length-1));
  selected = album; const track = importedQueue[queueIndex]; selected.currentCover=track.cover||null; audio.src = track.url; audio.play().catch(()=>{}); playing = true; updatePlayer(); render();
}
async function importedAlbum(files, folderName){
  const audioFiles = files.filter(f=>audioExt.test(f.name));
  if(!audioFiles.length) return null;
  const cover = files.find(f=>imageExt.test(f.name) && /(cover|front|封面|folder)/i.test(f.name)) || files.find(f=>imageExt.test(f.name));
  const title = folderName || audioFiles[0].name.replace(/\.[^.]+$/,'');
  const tracks = audioFiles.sort((a,b)=>a.name.localeCompare(b.name,undefined,{numeric:true})).map((file,i)=>({name:file.name.replace(/\.[^.]+$/,''),url:URL.createObjectURL(file),index:i}));
  const obj = {id:safeId(title),title,artist:'本地导入',group:'本地文件夹',genre:'未分类',duration:tracks.length,totalDuration:0,played:0,favorite:false,date:Date.now(),tracks,color:['#c4b8e8','#4b416c'],shape:'radio'};
  if(!obj.localCover&&cover){ obj.localCover = URL.createObjectURL(cover); }
  return obj;
}
async function importFolder(fileList){
  const groups = new Map();
  [...fileList].forEach(file=>{ if(!audioExt.test(file.name) && !imageExt.test(file.name)) return; const parts=(file.webkitRelativePath||file.name).split('/'); const folder=parts.length>1?parts[parts.length-2]:'导入音声'; if(!groups.has(folder)) groups.set(folder,[]); groups.get(folder).push(file); });
  let added=0; for(const [name,files] of groups){const album=await importedAlbum(files,name);if(album){albums.unshift(album);added++;}}
  if(added){resetLibraryView();render();showToast(`已导入 ${added} 张专辑，已显示在全部音声`);}else{showToast('没有在所选文件夹中找到可导入的音频文件');}
}
$('#folderInput').addEventListener('change',async e=>{await importFolder(e.target.files);e.target.value='';});
function resetLibraryView(){activeFilter='all';$('#searchInput').value='';activeView='全部音声';$('#viewTitle').textContent='全部音声';$('#heroTitle').textContent='全部音声';document.querySelectorAll('.filter').forEach(item=>item.classList.toggle('active',item.dataset.filter==='all'));document.querySelectorAll('.nav-item[data-view]').forEach(item=>item.classList.toggle('active',item.dataset.view==='全部音声'));}
function mergeLibrary(importedAlbums){
  const importedIds=new Set(importedAlbums.map(album=>album.id));
  albums.splice(0,albums.length,...importedAlbums,...albums.filter(album=>!importedIds.has(album.id)));
}
async function importFromDesktop(){
  try{
    showToast('正在扫描音声文件夹...');
    const result=await window.kikoeru.importAudioFolder();
    hideImportBar();
    if(result.canceled)return;
    if(!result.albums?.length){showToast('没有在所选文件夹中找到支持的音频文件');return;}
    mergeLibrary(result.albums);resetLibraryView();render();showToast(`已导入 ${result.albums.length} 张专辑，已显示在全部音声`);
  }catch(error){hideImportBar();showToast(`导入失败：${error.message||'无法读取文件夹'}`);}
}
$('#importBtn').onclick=()=>{
  if(window.kikoeru?.importAudioFolder){importFromDesktop();return;}
  if(window.location.protocol==='file:'){showToast('桌面导入接口未加载，请重新启动应用');console.error('Kikoeru preload API is unavailable');return;}
  $('#folderInput').click();
};
function showToast(message){const toast=$('#toast');toast.textContent=message;toast.classList.add('show');clearTimeout(showToast.timer);showToast.timer=setTimeout(()=>toast.classList.remove('show'),3200);}
window.kikoeru?.onImportRequested(importFromDesktop);
window.kikoeru?.loadLibrary().then(savedAlbums=>{if(savedAlbums?.length){mergeLibrary(savedAlbums);render();}}).catch(()=>{});
function displayCover(album){ return album.localCover ? `<img src="${album.localCover}" alt="" />` : coverSvg(album); }
const originalRender = render;
render = function(){ originalRender(); document.querySelectorAll('.album-card').forEach(card=>{const a=albums.find(x=>String(x.id)===String(card.dataset.id)); if(a?.localCover){const node=card.querySelector('.cover-wrap svg'); if(node) node.outerHTML=`<img src="${a.localCover}" alt="${a.title}" />`;}}); };
const originalUpdatePlayer = updatePlayer;
updatePlayer = function(){ originalUpdatePlayer(); const track=importedQueue[queueIndex]; if(track) $('#nowArtist').textContent=`${selected.artist} · ${track.name}`; };
$('#playBtn').onclick=()=>{ if(importedQueue.length && audio.src){ if(audio.paused) audio.play().catch(()=>{}); else audio.pause(); playing=!audio.paused; updatePlayer(); } else { playing=!playing; updatePlayer(); } };
$('#prevBtn').onclick=()=>stepTrack(-1);
$('#nextBtn').onclick=()=>stepTrack(1);
$('#volumeBtn').onclick=e=>{e.stopPropagation();$('.volume-control').classList.toggle('open');};
$('#volumeInput').addEventListener('input',e=>setVolume(Number(e.target.value)/100));
document.addEventListener('click',e=>{if(!e.target.closest('.volume-control'))$('.volume-control').classList.remove('open');if(!e.target.closest('.mode-control'))$('.mode-control').classList.remove('open');});
audio.addEventListener('timeupdate',()=>{if(draggingProgress)return;if(audio.duration){selected.played=audio.currentTime;updateTimeline(audio.currentTime,audio.duration);}});
audio.addEventListener('loadedmetadata',()=>{const track=importedQueue[queueIndex];if(track){track.duration=audio.duration;selected.totalDuration=selected.tracks.reduce((total,item)=>total+(item.duration||0),0);updateTimeline(0,audio.duration);if($('#details').classList.contains('open'))openDetail(selected);}});
audio.addEventListener('play',()=>{playing=true;updatePlayer();});
audio.addEventListener('pause',()=>{playing=false;updatePlayer();});
audio.addEventListener('ended',()=>{if(!importedQueue.length)return;if(playMode==='single'){audio.currentTime=0;audio.play();return;}stepTrack(1);});
let draggingProgress=false;
function showProgressTooltip(pct,preview){
  const tip=$('#progressTooltip');
  tip.textContent=formatTime(preview);
  const input=$('#progressInput'),tl=$('#timeline');
  const r=input.getBoundingClientRect(),tr=tl.getBoundingClientRect();
  tip.style.left=(r.left-tr.left+r.width*pct/100)+'px';
  tip.classList.add('show');
}
function hideProgressTooltip(){$('#progressTooltip').classList.remove('show');}
$('#progressInput').addEventListener('input',e=>{
  draggingProgress=true;
  const total=audio.duration||selected.tracks?.[queueIndex]?.duration||0;
  const pct=Number(e.target.value);
  $('#progressInput').style.setProperty('--fill',pct+'%');
  const preview=total*pct/100;
  updateTimeline(preview,total);
  showProgressTooltip(pct,preview);
});
$('#progressInput').addEventListener('change',e=>{
  draggingProgress=false;
  hideProgressTooltip();
  if(audio.duration){audio.currentTime=audio.duration*Number(e.target.value)/100;updateTimeline(audio.currentTime,audio.duration);}
});
$('#progressInput').addEventListener('blur',hideProgressTooltip);
const baseCardClick = document.querySelectorAll('.album-card');
document.addEventListener('click',e=>{const play=e.target.closest('[data-play]');if(play){const a=albums.find(x=>String(x.id)===String(play.dataset.play));if(a?.tracks) chooseImported(a);}});

// ---- 偏好设置 ----
const settingsOverlay = $('#settingsOverlay');
const savedTheme = localStorage.getItem('kikoeru-theme') || 'light';
const savedAccent = localStorage.getItem('kikoeru-accent') || '#6559d8';
function applyTheme(theme){
  document.documentElement.dataset.theme = theme;
  localStorage.setItem('kikoeru-theme', theme);
  document.querySelectorAll('.theme-option').forEach(btn => btn.classList.toggle('active', btn.dataset.themeOpt === theme));
  $('#themeBtn').textContent = theme === 'dark' ? '☾' : '☼';
}
function applyAccent(color){
  document.documentElement.style.setProperty('--accent', color);
  localStorage.setItem('kikoeru-accent', color);
  document.querySelectorAll('.swatch').forEach(btn => btn.classList.toggle('active', btn.dataset.accent === color));
}
applyTheme(savedTheme);
applyAccent(savedAccent);
$('#settingsBtn').onclick = () => settingsOverlay.classList.add('open');
$('#settingsClose').onclick = () => settingsOverlay.classList.remove('open');
settingsOverlay.addEventListener('click', e => { if (e.target === settingsOverlay) settingsOverlay.classList.remove('open'); });
document.querySelectorAll('.theme-option').forEach(btn => btn.addEventListener('click', () => applyTheme(btn.dataset.themeOpt)));
document.querySelectorAll('.swatch').forEach(btn => btn.addEventListener('click', () => applyAccent(btn.dataset.accent)));
$('#themeBtn').onclick = () => applyTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
$('#openDataDir').onclick = async () => {
  if (window.kikoeru?.openDataDir) await window.kikoeru.openDataDir();
  else showToast('打开数据目录仅桌面版可用');
};
(async () => {
  try {
    if (window.kikoeru?.getVersion) {
      $('#appVersion').textContent = await window.kikoeru.getVersion();
    } else {
      const res = await fetch('package.json');
      $('#appVersion').textContent = (await res.json()).version || '—';
    }
  } catch { $('#appVersion').textContent = '—'; }
})();

// ---- 播放模式 ----
const modeLabels = { list: '列表', single: '单曲', shuffle: '随机', album: '专辑' };
const modeNames = { list: '列表循环', single: '单曲循环', shuffle: '随机播放', album: '专辑循环' };
function applyMode(mode){
  playMode = mode;
  localStorage.setItem('kikoeru-mode', mode);
  $('#modeBtn').textContent = modeLabels[mode] || '列表';
  $('#modeBtn').title = modeNames[mode] || '';
  document.querySelectorAll('.mode-option').forEach(btn => btn.classList.toggle('active', btn.dataset.mode === mode));
}
function playRandomTrack(album){
  if(!album.tracks?.length) return;
  let idx = 0;
  if(album.tracks.length > 1){
    do { idx = Math.floor(Math.random() * album.tracks.length); } while(idx === queueIndex);
  }
  chooseImported(album, idx);
}
function playNextAlbum(dir){
  const start = albums.findIndex(a => String(a.id) === String(selected.id));
  for(let i = 1; i <= albums.length; i += 1){
    const next = albums[(start + dir * i + albums.length) % albums.length];
    if(next?.tracks?.length){ chooseImported(next, 0); return; }
  }
}
function stepTrack(dir){
  if(!importedQueue.length) return;
  const album = selected;
  if(playMode === 'shuffle'){ playRandomTrack(album); return; }
  let idx = queueIndex + dir;
  const len = album.tracks.length;
  if(idx >= len){
    if(playMode === 'album'){ playNextAlbum(1); return; }
    idx = 0;
  } else if(idx < 0){
    if(playMode === 'album'){ playNextAlbum(-1); return; }
    idx = len - 1;
  }
  chooseImported(album, idx);
}
applyMode(playMode);
$('#modeBtn').onclick = () => document.querySelector('.mode-control').classList.toggle('open');
document.querySelectorAll('.mode-option').forEach(btn => btn.addEventListener('click', () => {
  applyMode(btn.dataset.mode);
  document.querySelector('.mode-control').classList.remove('open');
}));

// ---- 清理失效记录 ----
$('#cleanMissing').onclick = async () => {
  if(!window.kikoeru?.cleanMissing){ showToast('清理失效记录仅桌面版可用'); return; }
  try {
    const result = await window.kikoeru.cleanMissing();
    const saved = await window.kikoeru.loadLibrary();
    const demo = albums.filter(a => !String(a.id).startsWith('local-'));
    albums.splice(0, albums.length, ...demo, ...saved);
    render();
    if(result.removedAlbums || result.removedTracks) showToast(`已清理 ${result.removedAlbums} 张专辑、${result.removedTracks} 条失效曲目`);
    else showToast('库中暂无失效记录');
  } catch(error){ showToast(`清理失败：${error.message || '未知错误'}`); }
};

// ---- 右键菜单与删除专辑 ----
const ctxMenu = $('#ctxMenu');
function closeCtxMenu(){ ctxMenu.classList.remove('open'); }
function showCtxMenu(x, y, items, albumId){
  ctxMenu.dataset.albumId = albumId;
  ctxMenu.innerHTML = items.map(item => `<button class="ctx-item${item.danger ? ' danger' : ''}" data-ctx="${item.action}">${item.label}</button>`).join('');
  ctxMenu.classList.add('open');
  const r = ctxMenu.getBoundingClientRect();
  ctxMenu.style.left = Math.min(x, window.innerWidth - r.width - 8) + 'px';
  ctxMenu.style.top = Math.min(y, window.innerHeight - r.height - 8) + 'px';
}
document.addEventListener('click', closeCtxMenu);
document.addEventListener('contextmenu', closeCtxMenu);
document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeCtxMenu(); if (multiSelect) exitMultiSelect(); } });
ctxMenu.addEventListener('click', e => {
  const btn = e.target.closest('[data-ctx]');
  if (!btn) return;
  const action = btn.dataset.ctx;
  const id = ctxMenu.dataset.albumId;
  closeCtxMenu();
  if (action === 'delete-only') deleteAlbum(id, false);
  else if (action === 'delete-files') deleteAlbum(id, true);
  else if (action === 'scrape-tags') scrapeDlsite([id], true);
  else if (action === 'reveal-folder') {
    if (window.kikoeru?.revealInFolder) window.kikoeru.revealInFolder(id);
    else showToast('打开文件夹仅桌面版可用');
  }
});
grid.addEventListener('contextmenu', e => {
  const card = e.target.closest('.album-card');
  if (!card) return;
  e.preventDefault();
  e.stopPropagation();
  const a = albums.find(x => String(x.id) === String(card.dataset.id));
  if (!a) return;
  const items = [];
  const rj = albumRj(a);
  if (rj) items.push({ action: 'scrape-tags', label: '刮削 DLsite 标签' });
  if (a.sourcePath || a.tracks?.some(t => t.url && t.url.startsWith('file:'))) {
    items.push({ action: 'reveal-folder', label: '打开所在文件夹' });
  }
  items.push({ action: 'delete-only', label: '从库中删除' });
  if (a.sourcePath || a.tracks?.some(t => t.url && t.url.startsWith('file:'))) {
    items.push({ action: 'delete-files', label: '删除专辑及源文件', danger: true });
  }
  showCtxMenu(e.clientX, e.clientY, items, a.id);
});

function confirmDialog(title, text, okLabel){
  return new Promise(resolve => {
    $('#confirmTitle').textContent = title;
    $('#confirmText').textContent = text;
    $('#confirmOk').textContent = okLabel;
    const overlay = $('#confirmOverlay');
    overlay.classList.add('open');
    const done = result => { overlay.classList.remove('open'); resolve(result); };
    $('#confirmOk').onclick = () => done(true);
    $('#confirmCancel').onclick = () => done(false);
    overlay.onclick = e => { if (e.target === overlay) done(false); };
  });
}
async function deleteAlbum(id, deleteFiles){
  const album = albums.find(a => String(a.id) === String(id));
  if (!album) return;
  const title = album.title;
  if (deleteFiles) {
    const ok = await confirmDialog('删除专辑及源文件', `将永久删除「${title}」的全部音频文件与文件夹，此操作不可恢复。确定继续吗？`, '删除');
    if (!ok) return;
  }
  try {
    let deletedFiles = 0;
    if (window.kikoeru?.removeAlbum) {
      const result = await window.kikoeru.removeAlbum(id, deleteFiles);
      if (result && !result.ok && result.reason !== 'not-found') { showToast('删除失败'); return; }
      deletedFiles = result?.deletedFiles || 0;
    }
    const idx = albums.findIndex(a => String(a.id) === String(id));
    if (idx >= 0) albums.splice(idx, 1);
    if (selected && String(selected.id) === String(id)) {
      audio.pause();
      importedQueue = [];
      queueIndex = -1;
      playing = false;
      selected = albums[0] || { id: 0, title: '音声库为空', artist: '', group: '', genre: '未分类', favorite: false, played: 0, duration: 0, color: ['#c4b8e8', '#4b416c'], shape: 'radio' };
    }
    render();
    showToast(deleteFiles ? `已删除「${title}」及 ${deletedFiles} 个源文件` : `已将「${title}」从库中删除`);
  } catch (error) { showToast(`删除失败：${error.message || '未知错误'}`); }
}

// ---- 多选模式与批量删除 ----
function enterMultiSelect(){
  multiSelect = true;
  multiIds.clear();
  $('#multiBar').classList.add('open');
  $('#multiSelectBtn').classList.add('active');
  $('#multiSelectBtn').textContent = '退出多选';
  render();
  updateMultiCount();
}
function exitMultiSelect(){
  multiSelect = false;
  multiIds.clear();
  $('#multiBar').classList.remove('open');
  $('#multiSelectBtn').classList.remove('active');
  $('#multiSelectBtn').textContent = '多选';
  render();
}
function toggleMulti(id){
  const key = String(id);
  if (multiIds.has(key)) multiIds.delete(key); else multiIds.add(key);
  render();
  updateMultiCount();
}
function updateMultiCount(){ $('#multiCount').textContent = `已选 ${multiIds.size} 张`; }
$('#multiSelectBtn').onclick = () => { if (multiSelect) exitMultiSelect(); else enterMultiSelect(); };
$('#multiCancel').onclick = exitMultiSelect;
$('#multiSelectAll').onclick = () => { filtered().forEach(a => multiIds.add(String(a.id))); render(); updateMultiCount(); };
async function deleteAlbums(ids, deleteFiles){
  const count = ids.length;
  if (!count) return;
  const ok = deleteFiles
    ? await confirmDialog('删除所选专辑及源文件', `将永久删除选中的 ${count} 张专辑的全部音频文件与文件夹，此操作不可恢复。确定继续吗？`, '删除')
    : await confirmDialog('删除所选专辑', `确定从库中删除选中的 ${count} 张专辑吗？源文件不受影响。`, '删除');
  if (!ok) return;
  try {
    let deletedFiles = 0;
    if (window.kikoeru?.removeAlbums) {
      const result = await window.kikoeru.removeAlbums(ids, deleteFiles);
      deletedFiles = result?.deletedFiles || 0;
    }
    const idSet = new Set(ids.map(String));
    const removedCount = albums.filter(a => idSet.has(String(a.id))).length;
    albums.splice(0, albums.length, ...albums.filter(a => !idSet.has(String(a.id))));
    if (selected && idSet.has(String(selected.id))) {
      audio.pause();
      importedQueue = [];
      queueIndex = -1;
      playing = false;
      selected = albums[0] || null;
    }
    exitMultiSelect();
    showToast(deleteFiles ? `已删除 ${removedCount} 张专辑及 ${deletedFiles} 个源文件` : `已从库中删除 ${removedCount} 张专辑`);
  } catch (error) { showToast(`删除失败：${error.message || '未知错误'}`); }
}
$('#multiDelete').onclick = () => deleteAlbums([...multiIds], false);
$('#multiDeleteFiles').onclick = () => deleteAlbums([...multiIds], true);
$('#multiScrape').onclick = () => scrapeDlsite([...multiIds], false);

// ---- 导入进度条 ----
let importBarHideTimer;
function showImportProgress(data){
  const bar = $('#importBar');
  bar.classList.add('open');
  const folderPart = data.folderTotal > 1 ? `（第 ${data.folderIndex} / ${data.folderTotal} 个文件夹）` : '';
  $('#importText').textContent = `正在导入 ${data.processed} / ${data.total} 张专辑${folderPart}`;
  $('#importFill').style.width = data.total ? `${Math.round(data.processed / data.total * 100)}%` : '0%';
  if (data.processed >= data.total) {
    clearTimeout(importBarHideTimer);
    importBarHideTimer = setTimeout(() => bar.classList.remove('open'), 1200);
  }
}
function hideImportBar(){
  clearTimeout(importBarHideTimer);
  $('#importBar').classList.remove('open');
}
window.kikoeru?.onImportProgress(showImportProgress);

// ---- DLsite 标签刮削 ----
function albumRj(a){
  if (a.rjCode) return a.rjCode;
  const match = /RJ\d{5,}/i.exec(`${a.sourcePath || ''} ${a.title || ''}`);
  return match ? match[0].toUpperCase() : null;
}
async function scrapeDlsite(ids, force){
  if (!ids.length) return;
  try {
    const result = await window.kikoeru.scrapeDlsite(ids.map(String), force);
    const scraped = new Map((result.details || []).filter(d => Array.isArray(d.tags)).map(d => [String(d.id), d]));
    albums.forEach(a => {
      const hit = scraped.get(String(a.id));
      if (hit) {
        a.tags = hit.tags;
        a.dlsiteTitle = hit.title || a.dlsiteTitle;
        a.rjCode = hit.rj || a.rjCode;
      }
    });
    render();
    hideImportBar();
    if (result.noRj === ids.length) { showToast('所选专辑均未检测到 RJ 号'); return; }
    showToast(`刮削完成：${result.scraped} 张成功，${result.failed} 张失败${result.noRj ? `，${result.noRj} 张无 RJ 号` : ''}${result.skipped ? `，${result.skipped} 张已刮过跳过` : ''}`);
  } catch (error) { hideImportBar(); showToast(`刮削失败：${error.message || '未知错误'}`); }
}
window.kikoeru?.onDlsiteProgress(({ processed, total }) => {
  const bar = $('#importBar');
  bar.classList.add('open');
  $('#importText').textContent = `正在刮削 ${processed} / ${total} 张专辑的标签`;
  $('#importFill').style.width = total ? `${Math.round(processed / total * 100)}%` : '0%';
  if (processed >= total) {
    clearTimeout(importBarHideTimer);
    importBarHideTimer = setTimeout(() => bar.classList.remove('open'), 800);
  }
});
// 刮削代理设置
if (window.kikoeru?.getScrapeConfig) {
  window.kikoeru.getScrapeConfig().then(config => { if (config) $('#scrapeProxy').value = config.proxy || ''; }).catch(() => {});
}
$('#scrapeProxy').addEventListener('change', () => {
  window.kikoeru?.setScrapeConfig({ proxy: $('#scrapeProxy').value.trim() });
  showToast('刮削代理已保存');
});

// ---- 侧栏显示/隐藏 ----
const sidebarToggle = $('#sidebarToggle');
function applySidebar(shown){
  document.querySelector('.window').classList.toggle('sidebar-hidden', !shown);
  localStorage.setItem('kikoeru-sidebar', shown ? 'shown' : 'hidden');
  sidebarToggle.textContent = shown ? '◀' : '▶';
  sidebarToggle.title = shown ? '隐藏侧栏' : '显示侧栏';
}
applySidebar(localStorage.getItem('kikoeru-sidebar') !== 'hidden');
sidebarToggle.onclick = () => applySidebar(document.querySelector('.window').classList.contains('sidebar-hidden'));
