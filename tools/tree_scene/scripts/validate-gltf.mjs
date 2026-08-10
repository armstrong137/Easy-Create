import { readFile } from 'node:fs/promises';
import process from 'node:process';

import validator from 'gltf-validator';

const file = process.argv[2];
if (!file) {
  throw new Error('需要提供 GLB 路径');
}

const bytes = await readFile(file);
const report = await validator.validateBytes(new Uint8Array(bytes), {
  uri: file,
  maxIssues: 200,
  ignoredIssues: [],
});
process.stdout.write(JSON.stringify(report));
process.exitCode = report.issues.numErrors > 0 ? 1 : 0;
