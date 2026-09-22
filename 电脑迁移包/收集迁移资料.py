"""收集本项目外部资料；不读取登录凭据，不关闭浏览器，不改源数据。"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile

package = Path(__file__).resolve().parent
project = package.parent
home = Path.home()
backup = package / '本地备份'
backup.mkdir(exist_ok=True)
copied, missing, failed = [], [], []

def copy(source, relative):
    source = Path(source)
    destination = backup / relative
    if not source.is_file():
        missing.append(str(source))
        return
    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        digest = hashlib.sha256(destination.read_bytes()).hexdigest()
        copied.append({'来源':str(source),'副本':str(destination.relative_to(package)),
                       '字节':destination.stat().st_size,'SHA256':digest})
    except OSError as error:
        failed.append({'来源':str(source),'错误':str(error)})

def tree(source, relative):
    source = Path(source)
    if source.exists():
        for file in source.rglob('*'):
            if file.is_file(): copy(file, Path(relative) / file.relative_to(source))

thread = '019f2a9d-7fed-7743-a98c-9348960da917'
tree(home/'.codex/generated_images'/thread, '原始出图')
tree(home/'.codex/visualizations/2026/07/04'/thread, '交互预览')
tree(home/'.codex/skills/let-claude-continue', '个人技能/let-claude-continue')
for skill in ['imagegen','openai-docs']:
    tree(home/'.codex/skills/.system'/skill, '内置技能快照/'+skill)

# 只备份本任务记录；其中的文字是历史资料，不应当作新指令执行。
attachments = set()
pattern = re.compile(r'[A-Za-z]:[\\/][^\r\n"<>|?*]{1,350}?\.(?:png|jpg|jpeg|webp|mp4|mov|pdf|blend)(?![A-Za-z0-9])', re.I)
def inspect(value):
    if isinstance(value,str): attachments.update(pattern.findall(value))
    elif isinstance(value,list):
        for item in value: inspect(item)
    elif isinstance(value,dict):
        for item in value.values(): inspect(item)
for session in (home/'.codex/sessions').rglob('*'+thread+'*'):
    if session.is_file():
        copy(session, Path('当前任务记录')/session.name)
        with session.open(encoding='utf-8') as stream:
            for line in stream:
                try: inspect(json.loads(line))
                except json.JSONDecodeError: pass
for name in sorted(attachments):
    source = Path(name)
    try:
        resolved = source.resolve()
        if resolved.is_relative_to(project) or resolved.is_relative_to(home/'.codex/generated_images'/thread): continue
        # 仅收集对话明确引用的图像/视频/模型，不扫描其他工作项目。
        if source.is_file():
            copy(source, Path('对话引用附件')/(hashlib.sha256(name.encode()).hexdigest()[:10]+'_'+source.name))
        else: missing.append(name)
    except OSError: missing.append(name)

# 查找浏览器按来源分隔的存储，只收集明确包含 novel_app 数据库的桶。
profiles = []
for browser in ['Google/Chrome','Microsoft/Edge']:
    base=Path(os.environ['LOCALAPPDATA'])/browser/'User Data'
    if base.exists(): profiles += [(browser.replace('/','_')+'_'+p.name,p) for p in base.iterdir()
        if p.is_dir() and (p.name=='Default' or p.name.startswith('Profile '))]
storage_findings=[]
codex_profile=Path(os.environ['APPDATA'])/'Codex/web/Codex/Default'
if codex_profile.exists(): profiles.append(('Codex内置浏览器',codex_profile))
for label, profile in profiles:
    quota=profile/'WebStorage/QuotaManager'
    if quota.exists():
        try:
            # 原浏览器持有独占锁时，在本地临时快照上查索引，不关闭浏览器。
            with tempfile.TemporaryDirectory() as temp:
                snapshot=Path(temp)/'QuotaManager'
                shutil.copy2(quota,snapshot)
                for suffix in ['-wal','-journal']:
                    sidecar=Path(str(quota)+suffix)
                    if sidecar.exists(): shutil.copy2(sidecar,Path(str(snapshot)+suffix))
                connection=sqlite3.connect(str(snapshot),timeout=2)
                rows=connection.execute('select id,storage_key from buckets').fetchall()
                connection.close()
            for identifier, origin in rows:
                bucket=profile/'WebStorage'/str(identifier)
                if not bucket.exists(): continue
                candidates=list(bucket.rglob('*'))
                matching=any(f.is_file() and f.stat().st_size<100_000_000 and
                    any(marker in f.read_bytes() for marker in [b'novel_app','novel_app'.encode('utf-16le')]) for f in candidates)
                if matching:
                    tree(bucket,Path('应用数据')/label/str(identifier))
                    storage_findings.append({'浏览器':label,'来源':origin,'桶':identifier})
        except (OSError,sqlite3.Error) as error:
            failed.append({'来源':str(quota),'错误':str(error)})
    indexed=profile/'IndexedDB'
    if indexed.exists():
        for folder in indexed.iterdir():
            if folder.is_dir() and re.match(r'https?_(localhost|127\.0\.0\.1|192\.168\.|10\.)',folder.name):
                if any(f.is_file() and f.stat().st_size<100_000_000 and b'novel_app' in f.read_bytes() for f in folder.rglob('*')):
                    tree(folder,Path('应用数据')/label/folder.name)
                    storage_findings.append({'浏览器':label,'来源':folder.name})

state=subprocess.run(['git','status','--short'],cwd=project,capture_output=True,text=True,encoding='utf-8').stdout
(backup/'迁移前工作区状态.txt').write_text(state,encoding='utf-8')
patch=subprocess.run(['git','diff','--binary'],cwd=project,capture_output=True).stdout
(backup/'迁移前未提交改动.patch').write_bytes(patch)
report={'已复制文件数':len(copied),'总字节':sum(f['字节'] for f in copied),
        '已复制':copied,'引用但未找到':sorted(set(missing)), '复制或读取失败':failed,'找到的应用存储':storage_findings}
(backup/'复制清单与校验.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='已复制' and k!='引用但未找到'},ensure_ascii=False))
print('缺失引用数量:',len(set(missing)))
