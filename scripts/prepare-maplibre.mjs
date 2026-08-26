import { copyFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const sourceDir = resolve('node_modules/maplibre-gl/dist');
const publicDir = resolve('public');

mkdirSync(publicDir, { recursive: true });

for (const file of ['maplibre-gl-worker.mjs', 'maplibre-gl-shared.mjs']) {
  copyFileSync(resolve(sourceDir, file), resolve(publicDir, file));
}
