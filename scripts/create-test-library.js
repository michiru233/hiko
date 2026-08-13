const fs = require('fs');
const path = require('path');

const target = process.argv[2] || '/tmp/kikoeru-import-test/端到端测试专辑';
fs.mkdirSync(target, { recursive: true });

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

createWav(path.join(target, '01 测试音频 A.wav'), 440, 3);
createWav(path.join(target, '02 测试音频 B.wav'), 554.37, 4);

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600"><rect width="600" height="600" fill="#305f72"/><circle cx="300" cy="260" r="150" fill="#f1c75b"/><circle cx="300" cy="260" r="48" fill="#305f72"/><text x="300" y="500" text-anchor="middle" font-family="Arial" font-size="42" fill="white">IMPORT TEST</text></svg>`;
fs.writeFileSync(path.join(target, 'cover.svg'), svg);
console.log(target);
