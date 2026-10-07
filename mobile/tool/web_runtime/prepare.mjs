import {mkdir, copyFile, readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
const target = path.resolve(root, '../../web/vendor');
await mkdir(target, {recursive: true});
for (const [pkg, bundle] of [
  ['tfjs-core', 'tf-core.min.js'],
  ['tfjs-backend-cpu', 'tf-backend-cpu.min.js'],
  ['tfjs-tflite', 'tf-tflite.min.js'],
]) {
  const source = path.join(root, 'node_modules/@tensorflow', pkg);
  await copyFile(path.join(source, 'dist', bundle), path.join(target, bundle));
  await copyFile(path.join(source, 'README.md'), path.join(target, `${pkg}-README.md`));
  const files = await readdir(source);
  for (const name of files.filter(name => /^LICENSE/.test(name))) {
    await copyFile(path.join(source, name), path.join(target, `${pkg}-${name}`));
  }
  if (pkg === 'tfjs-tflite') {
    for (const name of await readdir(path.join(source, 'wasm'))) {
      if (/\.(js|wasm)$/.test(name)) {
        await copyFile(path.join(source, 'wasm', name), path.join(target, name));
      }
    }
  }
}
