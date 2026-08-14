const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const packagePath = path.join(root, 'package.json');
const lockPath = path.join(root, 'package-lock.json');

const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
const [major, minor] = String(pkg.version || '0.1.0').split('.').map(Number);
const nextVersion = `${major || 0}.${(minor || 0) + 1}.0`;
const nextCode = (minor || 0) + 1;
pkg.version = nextVersion;
fs.writeFileSync(packagePath, `${JSON.stringify(pkg, null, 2)}\n`);

if (fs.existsSync(lockPath)) {
  const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
  lock.version = nextVersion;
  if (lock.packages?.['']) lock.packages[''].version = nextVersion;
  fs.writeFileSync(lockPath, `${JSON.stringify(lock, null, 2)}\n`);
}

// 同步 Android 版本号（android/app/build.gradle）
const gradlePath = path.join(root, 'android', 'app', 'build.gradle');
if (fs.existsSync(gradlePath)) {
  let gradle = fs.readFileSync(gradlePath, 'utf8');
  gradle = gradle.replace(/versionCode \d+/, `versionCode ${nextCode}`);
  gradle = gradle.replace(/versionName "[^"]*"/, `versionName "${nextVersion}"`);
  fs.writeFileSync(gradlePath, gradle);
}

console.log(`Kikoeru version bumped to ${nextVersion}（Android versionCode ${nextCode}）`);
