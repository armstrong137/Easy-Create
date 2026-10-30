import { readFile, writeFile } from 'node:fs/promises';
import { SourceMap } from 'node:module';
import { dirname, resolve } from 'node:path';

// 使用同次构建的源码映射还原采样位置；不把含剖析开销的时间当成性能门槛。
const profilePath = resolve(process.argv[2]);
const mapPath = resolve(process.argv[3] ?? resolve(dirname(profilePath), 'main.dart.js.map'));
const profile = JSON.parse(await readFile(profilePath, 'utf8'));
const sourceMap = new SourceMap(JSON.parse(await readFile(mapPath, 'utf8')));
const nodes = new Map(profile.nodes.map(node => [node.id, node]));
const parents = new Map();
for (const node of profile.nodes) {
  for (const child of node.children ?? []) parents.set(child, node.id);
}
const mapped = new Map(profile.nodes.map(node => {
  const frame = node.callFrame;
  const entry = frame.url.includes('main.dart.js')
    ? sourceMap.findEntry(frame.lineNumber, frame.columnNumber) : {};
  return [node.id, { functionName: entry.name || frame.functionName,
    source: entry.originalSource || frame.url || frame.functionName,
    line: entry.originalLine === undefined ? frame.lineNumber + 1 : entry.originalLine + 1 }];
}));
const self = new Map();
const inclusive = new Map();
for (let index = 0; index < profile.samples.length; index++) {
  let id = profile.samples[index];
  const duration = profile.timeDeltas[index];
  self.set(id, (self.get(id) ?? 0) + duration);
  const sources = new Set();
  while (id !== undefined) {
    sources.add(mapped.get(id).source);
    id = parents.get(id);
  }
  for (const source of sources) inclusive.set(source, (inclusive.get(source) ?? 0) + duration);
}
const report = {
  profilePath, mapPath,
  topSelf: [...self].sort((a, b) => b[1] - a[1]).slice(0, 40)
    .map(([id, microseconds]) => {
      const callers = [];
      let parent = parents.get(id);
      while (parent !== undefined && callers.length < 12) {
        callers.push(mapped.get(parent));
        parent = parents.get(parent);
      }
      return { ...mapped.get(id), microseconds, callers };
    }),
  inclusiveBySource: [...inclusive].sort((a, b) => b[1] - a[1])
    .map(([source, microseconds]) => ({ source, microseconds })),
  note: '包含时间按调用栈归属统计，各文件会重叠，不能相加或当作优化收益。',
};
const output = profilePath.replace(/\.cpuprofile$/, '-mapped.json');
await writeFile(output, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ output, topSelf: report.topSelf.slice(0, 12) }));
