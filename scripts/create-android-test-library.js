// 生成 Android 导入测试数据：RJ 命名专辑、深层目录 RJ 提取、无 RJ 专辑。
// 用法：node scripts/create-android-test-library.js [目标目录]
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const target = process.argv[2] || '/tmp/kikoeru-android-test';

function createWav(filePath, frequency, seconds) {
  const sampleRate = 44100;
  const samples = sampleRate * seconds;
  const dataSize = samples * 2;
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write('WAVEfmt ', 8);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);
  for (let index = 0; index < samples; index += 1) {
    const fade = Math.min(1, index / 1200, (samples - index) / 1200);
    buffer.writeInt16LE(Math.round(Math.sin(2 * Math.PI * frequency * index / sampleRate) * 7000 * fade), 44 + index * 2);
  }
  fs.writeFileSync(filePath, buffer);
}

function crc32(buf) {
  let table = crc32.table;
  if (!table) {
    table = crc32.table = [];
    for (let n = 0; n < 256; n += 1) {
      let c = n;
      for (let k = 0; k < 8; k += 1) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
      table[n] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const typeBuf = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

function createPng(width, height, [r, g, b]) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const raw = Buffer.alloc(height * (1 + width * 3));
  for (let y = 0; y < height; y += 1) {
    const rowStart = y * (1 + width * 3);
    raw[rowStart] = 0;
    for (let x = 0; x < width; x += 1) {
      raw[rowStart + 1 + x * 3] = r;
      raw[rowStart + 2 + x * 3] = g;
      raw[rowStart + 3 + x * 3] = b;
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', zlib.deflateSync(raw)),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

const album1 = path.join(target, 'RJ01000112_雨夜耳语');
const album2 = path.join(target, 'deep', 'RJ01234567_深层音声', 'inner', '测试音声');
const album3 = path.join(target, '无RJ号码专辑');

fs.mkdirSync(album1, { recursive: true });
fs.mkdirSync(album2, { recursive: true });
fs.mkdirSync(album3, { recursive: true });

createWav(path.join(album1, '01_开场.wav'), 440, 3);
createWav(path.join(album1, '02_轻语.wav'), 554.37, 4);
createWav(path.join(album1, '03_安眠.wav'), 659.25, 5);
fs.writeFileSync(path.join(album1, 'cover.png'), createPng(400, 400, [48, 95, 114]));

createWav(path.join(album2, '01_第一轨.wav'), 523.25, 3);
createWav(path.join(album2, '02_第二轨.wav'), 587.33, 4);
fs.writeFileSync(path.join(album2, 'front.png'), createPng(400, 400, [200, 100, 90]));

createWav(path.join(album3, '01_仅此一轨.wav'), 440, 6);

console.log(`测试库已生成：${target}`);
