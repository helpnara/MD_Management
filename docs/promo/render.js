// 사용: node render.js stills t1,t2,... | node render.js video out.mp4 fps
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');
const [,, mode, arg, fpsArg] = process.argv;
const DIR = process.env.PROMO_DIR;
const PAGE = process.env.PROMO_PAGE || 'promo.html';
const W = parseInt(process.env.PROMO_W || '1080'), H = parseInt(process.env.PROMO_H || '1920');
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROME || undefined });
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(DIR, PAGE));
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(500);
  if (mode === 'stills') {
    for (const t of arg.split(',').map(Number)) {
      await page.evaluate(t => render(t), t);
      await page.screenshot({ path: path.join(DIR, `still-${t}.png`) });
    }
  } else {
    const fps = parseInt(fpsArg || '30');
    const dur = await page.evaluate(() => DURATION);
    const n = Math.round(dur * fps);
    const ff = spawn(process.env.FFMPEG, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'slow', '-crf', '18', '-movflags', '+faststart', arg], { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let i = 0; i < n; i++) {
      await page.evaluate(t => render(t), i / fps);
      const buf = await page.screenshot({ type: 'jpeg', quality: 94 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 150 === 0) console.log(`frame ${i}/${n}`);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
  }
  await browser.close();
})();
