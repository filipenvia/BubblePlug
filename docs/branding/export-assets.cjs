// Development-only exporter. Usage: NODE_PATH=/path/to/node_modules node export-assets.cjs
const sharp = require('sharp');
const path = require('path');
const fs = require('fs/promises');
const { execFileSync } = require('child_process');

async function main() {
  const root = path.resolve(__dirname, '../..');
  await sharp(path.join(__dirname, 'BubblePlug-github-banner.svg'))
    .png().toFile(path.join(__dirname, 'BubblePlug-github-banner.png'));
  await sharp(path.join(__dirname, 'BubblePlug-logo.svg'))
    .resize(1024, 1024).png().toFile(path.join(__dirname, 'BubblePlug-logo-vector-preview.png'));
  const iconset = path.join(root, 'build/branding/BubblePlug.iconset');
  await fs.mkdir(iconset, { recursive: true });
  const source = path.join(root, 'macos/Sources/PlugSpotApp/Resources/BubblePlug.png');
  for (const size of [16, 32, 128, 256, 512]) {
    for (const scale of [1, 2]) {
      await sharp(source).resize(size * scale, size * scale).png()
        .toFile(path.join(iconset, `icon_${size}x${size}${scale === 2 ? '@2x' : ''}.png`));
    }
  }
  execFileSync('/usr/bin/iconutil', ['-c', 'icns', iconset, '-o', path.join(root, 'macos/Resources/BubblePlug.icns')]);
}
main().catch(error => { console.error(error); process.exit(1); });
