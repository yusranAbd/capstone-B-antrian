// Reproducible raster export of the QueueB geometric mark. No generated photos.
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("@playwright/test");
const root = path.resolve(__dirname, "..");
const svg = fs.readFileSync(
  path.join(__dirname, "branding/queueb-mark.svg"),
  "utf8",
);
const targets = [
  ["web/favicon.png", 32, false],
  ["web/icons/Icon-192.png", 192, false],
  ["web/icons/Icon-512.png", 512, false],
  ["web/icons/Icon-maskable-192.png", 192, true],
  ["web/icons/Icon-maskable-512.png", 512, true],
  ...[
    ["mdpi", 48],
    ["hdpi", 72],
    ["xhdpi", 96],
    ["xxhdpi", 144],
    ["xxxhdpi", 192],
  ].map(([dpi, size]) => [
    `android/app/src/main/res/mipmap-${dpi}/ic_launcher.png`,
    size,
    false,
  ]),
];
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  try {
    const page = await browser.newPage();
    for (const [relative, size, maskable] of targets) {
      const target = path.resolve(root, relative);
      if (!target.startsWith(root + path.sep) || !fs.existsSync(target))
        throw new Error("Unexpected icon target");
      const png = await page.evaluate(
        async ({ svg, size, maskable }) => {
          const image = new Image();
          image.src = "data:image/svg+xml;base64," + btoa(svg);
          await image.decode();
          const canvas = document.createElement("canvas");
          canvas.width = size;
          canvas.height = size;
          const ctx = canvas.getContext("2d");
          if (maskable) {
            ctx.fillStyle = "#F7F3EE";
            ctx.fillRect(0, 0, size, size);
            ctx.drawImage(
              image,
              size * 0.16,
              size * 0.16,
              size * 0.68,
              size * 0.68,
            );
          } else ctx.drawImage(image, 0, 0, size, size);
          return canvas.toDataURL("image/png").split(",")[1];
        },
        { svg, size, maskable },
      );
      fs.writeFileSync(target, Buffer.from(png, "base64"));
      process.stdout.write(relative + " " + size + "px\n");
    }
  } finally {
    await browser.close();
  }
})().catch((error) => {
  process.stderr.write(error.message + "\n");
  process.exitCode = 1;
});
