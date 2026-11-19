// render.js — rend une composition HTML image par image et l'encode en MP4 H.264 (1080×1920, 30 i/s).
//
//   node render.js <composition.html> <sortie.mp4>
//   node render.js <composition.html> <préfixe> --frames 2,6.5,11    (captures JPEG seules, pour vérifier)
//
// La page expose window.DURATION (secondes), window.render(t) ou window.renderAsync(t)
// (attend que les vidéos soient calées), et éventuellement window.ready() (chargement des médias).
// Les outils viennent de ~/.cache/video-pub (scripts/setup.sh).
const path = require('path');
const { spawn } = require('child_process');
const base = path.join(process.env.HOME, '.cache/video-pub/node_modules');
const puppeteer = require(path.join(base, 'puppeteer-core'));
const ffmpeg = require(path.join(base, 'ffmpeg-static'));

const [, , page_, out, flag, list] = process.argv;
if (!page_ || !out) { console.error('usage : node render.js <composition.html> <sortie.mp4> [--frames t1,t2]'); process.exit(2); }
const FPS = 30;

(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--allow-file-access-from-files', '--hide-scrollbars', '--autoplay-policy=no-user-gesture-required'],
  });
  const page = await browser.newPage();
  page.on('pageerror', (e) => console.error('erreur dans la page :', e.message));
  await page.setViewport({ width: 1080, height: 1920, deviceScaleFactor: 1 });
  await page.goto('file://' + path.resolve(page_), { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => window.ready && window.ready());
  const duration = await page.evaluate(() => window.DURATION);
  const step = (t) => page.evaluate((x) => (window.renderAsync || window.render)(x), t);

  if (flag === '--frames') {
    for (const s of list.split(',').map(Number)) {
      await step(s);
      await page.screenshot({ path: `${out}-${String(s).replace('.', '_')}.jpg`, type: 'jpeg', quality: 80 });
    }
    await browser.close();
    return;
  }

  const enc = spawn(ffmpeg, [
    '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'medium', '-crf', '18', '-movflags', '+faststart', out,
  ], { stdio: ['pipe', 'ignore', 'inherit'] });

  const total = Math.round(duration * FPS);
  for (let i = 0; i < total; i++) {
    await step(i / FPS);
    const buf = await page.screenshot({ type: 'jpeg', quality: 92 });
    if (!enc.stdin.write(buf)) await new Promise((r) => enc.stdin.once('drain', r));
  }
  enc.stdin.end();
  await new Promise((r) => enc.on('close', r));
  await browser.close();
  console.log(`ok : ${total} images, ${duration} s → ${out}`);
})();
