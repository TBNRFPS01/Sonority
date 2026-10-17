// Original, procedural artwork and audio fixtures. No third-party music or images.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const iconDir = path.join(root, 'App/Assets.xcassets/AppIcon.appiconset');
fs.mkdirSync(iconDir, { recursive: true });
function crc32(bytes) {
    let crc = 0xFFFFFFFF;
    for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xEDB88320 : 0); }
    return (crc ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
    const kind = Buffer.from(type), length = Buffer.alloc(4), crc = Buffer.alloc(4);
    length.writeUInt32BE(data.length); crc.writeUInt32BE(crc32(Buffer.concat([kind, data])));
    return Buffer.concat([length, kind, data, crc]);
}
const size = 1024, pixels = Buffer.alloc((size * 3 + 1) * size);
const bars = [{ x: 290, h: 135 }, { x: 400, h: 270 }, { x: 510, h: 440 }, { x: 620, h: 270 }, { x: 730, h: 135 }];
for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
        const glow = Math.max(0, 1 - Math.hypot(x - 600, y - 320) / 780);
        let coverage = 0;
        for (const bar of bars) {
            const dy = Math.max(0, Math.abs(y - 512) - (bar.h / 2 - 22));
            coverage = Math.max(coverage, Math.min(1, Math.max(0, 22.5 - Math.hypot(x - bar.x, dy))));
        }
        const background = [10 + glow * 20, 20 + glow * 36, 17 + glow * 24];
        const foreground = [195, 226, 188];
        const offset = y * (size * 3 + 1) + 1 + x * 3;
        for (let channel = 0; channel < 3; channel++) pixels[offset + channel] = Math.round(background[channel] * (1 - coverage) + foreground[channel] * coverage);
    }
}
const header = Buffer.alloc(13); header.writeUInt32BE(size, 0); header.writeUInt32BE(size, 4); header[8] = 8; header[9] = 2;
fs.writeFileSync(path.join(iconDir, 'AppIcon.png'), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]));
fs.writeFileSync(path.join(iconDir, 'Contents.json'), JSON.stringify({ images: [{ filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }], info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
fs.writeFileSync(path.join(iconDir, '../Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
const fixtureDir = path.join(root, 'Fixtures'); fs.mkdirSync(fixtureDir, { recursive: true });
for (const [rate, channels] of [[44100, 1], [48000, 2]]) {
    const duration = 8, frames = rate * duration, dataSize = frames * channels * 2;
    const wav = Buffer.alloc(44 + dataSize);
    wav.write('RIFF'); wav.writeUInt32LE(36 + dataSize, 4); wav.write('WAVEfmt ', 8); wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(channels, 22);
    wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * channels * 2, 28); wav.writeUInt16LE(channels * 2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(dataSize, 40);
    for (let frame = 0; frame < frames; frame++) {
        const t = frame / rate, envelope = Math.min(1, t * 10, (duration - t) * 10);
        for (let channel = 0; channel < channels; channel++) wav.writeInt16LE(Math.round(2500 * envelope * Math.sin(2 * Math.PI * (channel ? 330 : 220) * t)), 44 + (frame * channels + channel) * 2);
    }
    fs.writeFileSync(path.join(fixtureDir, `TEST-TONE-${rate}-${channels}ch.wav`), wav);
}
fs.writeFileSync(path.join(fixtureDir, 'TEST-TONE.lrc'), '[ar:Sonority test fixture]\n[ti:Generated test tone]\n[00:00.00]Test begins\n[00:02.00]Tap this line to seek to two seconds\n[00:04.00]Try the bass and EQ controls\n[00:06.00]The fixture ends at eight seconds\n');
fs.writeFileSync(path.join(fixtureDir, 'TEST-TONE.translation.lrc'), '[00:00.00]La prueba comienza\n[00:02.00]Toca esta línea para ir a dos segundos\n[00:04.00]Prueba los controles de graves y ecualización\n[00:06.00]La prueba termina a los ocho segundos\n');
console.log('Generated original app icon, two labeled 8-second audio fixtures, and original/translation LRC files. Fixtures are never auto-loaded.');
