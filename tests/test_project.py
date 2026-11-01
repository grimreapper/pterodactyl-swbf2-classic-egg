#!/usr/bin/env python3
import ast, hashlib, importlib.util, json, os, re, shlex, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
EGG=ROOT/'egg-swbf2-classic-2005.json'; INSTALL=ROOT/'scripts/install.sh'; IR=ROOT/'scripts/install_runtime.py'
START=ROOT/'scripts/start.sh'; RT=ROOT/'scripts/runtime.py'; BUILD=ROOT/'scripts/build_release.py'
README=ROOT/'README.md'; CLIENT=ROOT/'CLIENT-SETUP.md'; VALIDATION=ROOT/'VALIDATION.md'; MAPS=ROOT/'SUPPORTED-MAPS.md'
ORIGINAL='eeb3bd768ec6ebdf7d0bca39a34a354c4d465b74f244702727ef6b70cbaea04a'
PAYLOAD={'BattlefrontII.exe':b'synthetic executable','license.txt':b'synthetic fixture, not vendor text','data/_LVL_PC/core.lvl':b'core','data/_LVL_PC/mission.lvl':b'mission','data/_LVL_PC/shell.lvl':b'shell','data/_LVL_PC/SIDE/rep.lvl':b'side','data/_LVL_PC/UTA/uta1.lvl':b'world'}

def run(cmd,cwd=ROOT,env=None,timeout=30): return subprocess.run(cmd,cwd=cwd,env=env,text=True,capture_output=True,timeout=timeout)
def load(path,name):
 s=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def tree(root,files=None):
 for rel,data in (files or PAYLOAD).items():
  p=root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(data)
def exe(path,text): path.write_text(text); path.chmod(0o755)
def commands(root,python_log=False):
 d=root/'commands'; d.mkdir(); log=root/'commands.log'; exe(d/'apt-get','#!/bin/sh\nprintf "apt-get %s\\n" "$*" >> "$TEST_COMMAND_LOG"\n')
 if python_log: exe(d/'python3',f'#!/bin/sh\nprintf "python3 %s\\n" "$*" >> "$TEST_COMMAND_LOG"\nexec {shlex.quote(sys.executable)} "$@"\n')
 return d,log
def builder(): return load(BUILD,'build_release')
def test_installer(root):
 h=hashlib.sha256(PAYLOAD['BattlefrontII.exe']).hexdigest(); p=root/'test-install.sh'; p.write_text(builder().build_install_content(h)); p.chmod(0o755); return p,h
def candidates():
 r=run(['git','ls-files','--cached','--others','--exclude-standard']); r.check_returncode(); return [ROOT/x for x in r.stdout.splitlines() if x and (ROOT/x).is_file()]
def install_fixture(root):
 server=root/'server'; server.mkdir(); tree(server/'swbf2-original-server'); script,h=test_installer(root); path,log=commands(root,True)
 env={**os.environ,'SERVER_DIR':str(server),'ACCEPT_LUCASARTS_LICENSE':'YES','NONCOMMERCIAL_USE':'YES','TEST_COMMAND_LOG':str(log),'PATH':f"{path}:{os.environ['PATH']}"}
 return server,h,path,log,env,run(['bash',str(script)],env=env)

class Architecture(unittest.TestCase):
 def test_archive_mode_absent(self):
  self.assertFalse((ROOT/'scripts/safe_extract.py').exists()); text='\n'.join(p.read_text(errors='replace') for p in candidates() if p!=Path(__file__)).lower()
  for x in ('swbf2-original-server.tar.gz','tarfile','pax metadata','archive mode','archive hash'): self.assertNotIn(x,text)
 def test_required_sources(self):
  for p in (EGG,INSTALL,IR,START,RT,BUILD,README,CLIENT,VALIDATION): self.assertTrue(p.is_file(),p)
 def test_egg_transaction_root_and_neutral_name(self):
  egg=json.loads(EGG.read_text()); self.assertEqual(egg['startup'],'bash ./swbf2-runtime/start.sh'); self.assertEqual(egg['name'],'Star Wars Battlefront II Classic (2005) BYOC')
  d=egg['description'].lower()
  for x in ('bring-your-own-content','not legal advice','remaining content','not authenticated'): self.assertIn(x,d)
 def test_deterministic_renderer_embeds_canonical_sources(self):
  b=builder(); a=b.build_install_content(); self.assertEqual(a,b.build_install_content()); self.assertIn(IR.read_text().rstrip(),a)
  assignment=re.search(r'^START_SCRIPT = (.+)$',a,re.M); self.assertIsNotNone(assignment); self.assertEqual(ast.literal_eval(assignment.group(1)),START.read_text())
  self.assertEqual(a.rstrip()+'\n',INSTALL.read_text()); self.assertEqual(a,json.loads(EGG.read_text())['scripts']['installation']['script'])
 def test_sources_parse(self):
  for p in (INSTALL,START): self.assertEqual(run(['bash','-n',str(p)]).returncode,0)
  for p in (IR,RT,BUILD,Path(__file__)): self.assertEqual(run([sys.executable,'-m','py_compile',str(p)]).returncode,0)
  json.loads(EGG.read_text())

class DirectorySafety(unittest.TestCase):
 def setUp(self): self.m=load(IR,f'ir{id(self)}'); self.h=hashlib.sha256(PAYLOAD['BattlefrontII.exe']).hexdigest()
 def copy(self,s,d): self.m.copy_and_verify_tree(s,d,self.h)
 def test_success(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); tree(r/'source'); self.copy(r/'source',r/'stage')
   for p,v in PAYLOAD.items(): self.assertEqual((r/'stage'/p).read_bytes(),v)
 def test_root_symlink_rejected(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); tree(r/'real'); (r/'source').symlink_to(r/'real',target_is_directory=True)
   with self.assertRaisesRegex(self.m.ValidationError,'real directory|symlink'): self.copy(r/'source',r/'stage')
 def test_links_and_specials_rejected(self):
  for kind in ('symlink','hardlink','fifo'):
   with self.subTest(kind=kind),tempfile.TemporaryDirectory() as td:
    r=Path(td); s=r/'source'; tree(s)
    if kind=='symlink': (s/'bad').symlink_to('license.txt')
    elif kind=='hardlink': os.link(s/'license.txt',s/'bad')
    else: os.mkfifo(s/'bad')
    with self.assertRaisesRegex(self.m.ValidationError,'symlink|hardlink|special|regular'): self.copy(s,r/'stage')
 def test_collision_and_alternate_exe_rejected(self):
  for rel,msg in (('Data','case collision'),('BattlefrontII.patched.exe','alternate')):
   with self.subTest(rel=rel),tempfile.TemporaryDirectory() as td:
    r=Path(td); s=r/'source'; tree(s); p=s/rel; p.mkdir() if rel=='Data' else p.write_bytes(b'x')
    with self.assertRaisesRegex(self.m.ValidationError,msg): self.copy(s,r/'stage')
 def test_structure_and_hash_enforced(self):
  for missing in ('license.txt','data/_LVL_PC/core.lvl','data/_LVL_PC/SIDE/rep.lvl'):
   with self.subTest(missing=missing),tempfile.TemporaryDirectory() as td:
    r=Path(td); s=r/'source'; tree(s); (s/missing).unlink()
    with self.assertRaisesRegex(self.m.ValidationError,'required'): self.copy(s,r/'stage')
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); tree(r/'source')
   with self.assertRaisesRegex(self.m.ValidationError,'checksum'): self.m.copy_and_verify_tree(r/'source',r/'stage',ORIGINAL)
 def test_caps_enforced(self):
  for const,value,msg in (('MAX_FILES',6,'file-count'),('MAX_TOTAL_BYTES',10,'total-size'),('MAX_DEPTH',2,'depth'),('MAX_PATH_LENGTH',20,'path')):
   with self.subTest(const=const),tempfile.TemporaryDirectory() as td:
    r=Path(td); tree(r/'source'); module=load(IR,f'cap_{const}_{id(r)}'); setattr(module,const,value)
    with self.assertRaisesRegex(module.ValidationError,msg): module.copy_and_verify_tree(r/'source',r/'stage',self.h)
 def test_change_during_copy_fails(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); s=r/'source'; tree(s); original=self.m._copy_regular_file; done=[False]
   def mutate(sfd,st,dfd,name,rel):
    if not done[0] and rel!='BattlefrontII.exe': done[0]=True; os.utime(s/rel,ns=(st.st_atime_ns,st.st_mtime_ns+1))
    return original(sfd,st,dfd,name,rel)
   self.m._copy_regular_file=mutate
   with self.assertRaisesRegex(self.m.ValidationError,'changed'): self.copy(s,r/'stage')
 def test_installer_snapshot_nofollow(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); src=r/'i.exe'; src.write_bytes(b'fixture'); h=hashlib.sha256(src.read_bytes()).hexdigest(); self.m.snapshot_installer(src,r/'snap',7,h)
   link=r/'link'; link.symlink_to(src)
   with self.assertRaisesRegex(self.m.ValidationError,'symlink|regular'): self.m.snapshot_installer(link,r/'snap2',7,h)
   self.assertEqual((r/'snap').read_bytes(),b'fixture')
   self.assertEqual(hashlib.sha256((r/'snap').read_bytes()).hexdigest(),h)
 def test_installer_snapshot_detects_source_change(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); src=r/'i.exe'; src.write_bytes(b'fixture'); h=hashlib.sha256(src.read_bytes()).hexdigest(); original=self.m.os.read; changed=[False]
   def mutate(fd,size):
    data=original(fd,size)
    if data and not changed[0]: changed[0]=True; src.write_bytes(b'changed')
    return data
   self.m.os.read=mutate
   try:
    with self.assertRaisesRegex(self.m.ValidationError,'changed'): self.m.snapshot_installer(src,r/'snap',7,h)
   finally: self.m.os.read=original

class Installer(unittest.TestCase):
 def env(self,root,path,log): return {**os.environ,'SERVER_DIR':str(root),'ACCEPT_LUCASARTS_LICENSE':'YES','NONCOMMERCIAL_USE':'YES','TEST_COMMAND_LOG':str(log),'PATH':f"{path}:{os.environ['PATH']}"}
 def test_acknowledgments_precede_packages(self):
  with tempfile.TemporaryDirectory() as td:
   r=run(['bash',str(INSTALL)],env={**os.environ,'SERVER_DIR':td}); self.assertNotEqual(r.returncode,0); self.assertIn('ACCEPT_LUCASARTS_LICENSE',r.stderr)
 def test_missing_source_intended_error(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); path,log=commands(r); out=run(['bash',str(INSTALL)],env=self.env(r,path,log)); self.assertNotEqual(out.returncode,0)
   for x in ('swbattlefrontiipcserver_v1_1.exe','swbf2-original-server','real directory'): self.assertIn(x,out.stderr)
   self.assertNotIn('tar.gz',out.stderr)
 def test_directory_e2e_and_fake_wine_argv(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td); server,h,path,log,env,out=install_fixture(root); self.assertEqual(out.returncode,0,out.stderr); runtime=server/'swbf2-runtime'
   self.assertTrue((runtime/'server/BattlefrontII.exe').is_file()); self.assertIn('source=directory',(runtime/'.swbf2-byoc-verified').read_text())
   lines=log.read_text().splitlines(); self.assertLess(next(i for i,x in enumerate(lines) if x.startswith('apt-get install') and 'python3' in x),next(i for i,x in enumerate(lines) if x.startswith('python3 ')))
   argv=root/'wine.argv'; exe(path/'wine','#!/bin/sh\nprintf "%s\\n" "$@" > "$TEST_WINE_ARGV"\n')
   out=run(['bash',str(runtime/'start.sh')],cwd=runtime,env={**env,'TEST_WINE_ARGV':str(argv),'ADMIN_PASSWORD':'Admin"\nSecret','SERVER_NAME':'Bad"\nName','MAP_ROTATION':'uta1c_con tan1c_con'})
   self.assertEqual(out.returncode,0,out.stderr); cfg=(runtime/'server/settings/ServerSettings.cfg').read_text(); self.assertIn('/gamename "Bad\' Name"',cfg); self.assertIn('/adminpw "Admin\' Secret"',cfg)
   self.assertEqual(argv.read_text().splitlines(),['./BattlefrontII.exe','/win','/norender','/nosound','/nointro','/autonet','dedicated','/resolution','640','480'])
 def test_wrong_installer_intended_error_not_apt_failure(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); (r/'swbattlefrontiipcserver_v1_1.exe').write_bytes(b'x'); path,log=commands(r); out=run(['bash',str(INSTALL)],env=self.env(r,path,log)); self.assertNotEqual(out.returncode,0)
   self.assertIn('installer size mismatch',out.stderr.lower()); self.assertNotIn('permission denied',out.stderr.lower()); self.assertNotIn('curl',log.read_text())
   self.assertFalse(any(p.name.startswith(('.swbf2-work-','.swbf2-release-')) for p in r.iterdir()))
 def test_ambiguous_sources(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); (r/'swbattlefrontiipcserver_v1_1.exe').write_bytes(b'x'); tree(r/'swbf2-original-server'); path,log=commands(r); out=run(['bash',str(INSTALL)],env=self.env(r,path,log)); self.assertIn('exactly one',out.stderr.lower())
 def test_production_hash_override_rejected(self):
  text=INSTALL.read_text()+START.read_text()+IR.read_text()+RT.read_text(); self.assertNotIn('SWBF2_BYOC_TEST',text)
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); tree(r/'swbf2-original-server'); path,log=commands(r); env=self.env(r,path,log); env['SWBF2_BYOC_TEST_EXE_SHA256']=hashlib.sha256(PAYLOAD['BattlefrontII.exe']).hexdigest(); out=run(['bash',str(INSTALL)],env=env); self.assertIn('checksum mismatch',out.stderr.lower())
 def test_old_generated_symlinks_never_followed(self):
  for rel in ('start.sh','.swbf2-byoc-verified','UNOFFICIAL-SERVER-NOTICE.txt'):
   with self.subTest(rel=rel),tempfile.TemporaryDirectory() as td:
    r=Path(td); server=r/'server'; server.mkdir(); tree(server/'swbf2-original-server'); old=server/'swbf2-runtime'; old.mkdir(); sentinel=r/'sentinel'; sentinel.write_text('preserve'); (old/rel).symlink_to(sentinel)
    script,_=test_installer(r); path,log=commands(r); out=run(['bash',str(script)],env=self.env(server,path,log)); self.assertEqual(out.returncode,0,out.stderr); self.assertEqual(sentinel.read_text(),'preserve')
    self.assertFalse(any(p.name.startswith(('.swbf2-work-','.swbf2-release-')) for p in server.iterdir()))
 def test_generated_failure_rolls_back(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); server=r/'server'; server.mkdir(); tree(server/'swbf2-original-server'); current=server/'swbf2-runtime'; current.mkdir(); (current/'sentinel').write_text('old')
   script,_=test_installer(r); script.write_text(script.read_text().replace('            write_release_files(release_fd, mode)',"            raise ValidationError('injected generated-output failure')",1)); path,log=commands(r); out=run(['bash',str(script)],env=self.env(server,path,log)); self.assertNotEqual(out.returncode,0); self.assertIn('injected generated-output failure',out.stderr); self.assertEqual((current/'sentinel').read_text(),'old')
   self.assertFalse(any(p.name.startswith(('.swbf2-work-','.swbf2-release-')) for p in server.iterdir()))

class StartupRaces(unittest.TestCase):
 def module(self,r):
  p=r/'runtime.py'; p.write_text(RT.read_text().replace(ORIGINAL,hashlib.sha256(PAYLOAD['BattlefrontII.exe']).hexdigest())); return load(p,f'rt{id(r)}')
 def release(self,r):
  x=r/'swbf2-runtime'; x.mkdir(); tree(x/'server'); h=hashlib.sha256(PAYLOAD['BattlefrontII.exe']).hexdigest(); (x/'start.sh').write_text('fixture'); (x/'.swbf2-byoc-verified').write_text(f'source=directory\nBattlefrontII.exe sha256={h}\n'); return x
 def env(self): return {'ACCEPT_LUCASARTS_LICENSE':'YES','NONCOMMERCIAL_USE':'YES','ADMIN_PASSWORD':'test-admin-password','SERVER_NAME':'Test'}
 def test_base_swap_cannot_redirect_notice(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); release=self.release(r); m=self.module(r); outside=r/'outside'; outside.mkdir(); (outside/'UNOFFICIAL-SERVER-NOTICE.txt').write_text('preserve'); moved=r/'moved'; original=m.atomic_write; done=[False]
   def swap(fd,name,data,mode):
    if not done[0]: done[0]=True; release.rename(moved); release.symlink_to(outside,target_is_directory=True)
    return original(fd,name,data,mode)
   m.atomic_write=swap
   with self.assertRaisesRegex(m.ValidationError,'changed'): m.run_runtime(release/'start.sh',self.env(),launch=lambda *a:None)
   self.assertEqual((outside/'UNOFFICIAL-SERVER-NOTICE.txt').read_text(),'preserve')
 def test_settings_swap_stays_pinned_and_fails_closed(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); release=self.release(r); settings=release/'server/settings'; settings.mkdir(); m=self.module(r); outside=r/'outside'; outside.mkdir(); (outside/'ServerSettings.cfg').write_text('preserve'); moved=release/'server/settings-moved'; original=m.atomic_write; done=[False]
   def swap(fd,name,data,mode):
    if name=='ServerSettings.cfg' and not done[0]: done[0]=True; settings.rename(moved); settings.symlink_to(outside,target_is_directory=True)
    return original(fd,name,data,mode)
   m.atomic_write=swap
   with self.assertRaisesRegex(m.ValidationError,'settings.*changed'): m.run_runtime(release/'start.sh',self.env(),launch=lambda *a:None)
   self.assertEqual((outside/'ServerSettings.cfg').read_text(),'preserve'); self.assertTrue((moved/'ServerSettings.cfg').is_file())
 def test_output_symlinks_replaced_without_following(self):
  for rel in ('server/settings/ServerSettings.cfg','server/settings/ServerRotation.cfg','UNOFFICIAL-SERVER-NOTICE.txt'):
   with self.subTest(rel=rel),tempfile.TemporaryDirectory() as td:
    r=Path(td); release=self.release(r); (release/'server/settings').mkdir(); sentinel=r/'sentinel'; sentinel.write_text('preserve'); target=release/rel; target.symlink_to(sentinel); m=self.module(r); m.run_runtime(release/'start.sh',self.env(),launch=lambda *a:None)
    self.assertEqual(sentinel.read_text(),'preserve'); self.assertTrue(target.is_file()); self.assertFalse(target.is_symlink())
 def test_symlinked_settings_rejected(self):
  with tempfile.TemporaryDirectory() as td:
   r=Path(td); release=self.release(r); real=release/'server/real'; real.mkdir(); (release/'server/settings').symlink_to(real,target_is_directory=True); m=self.module(r)
   with self.assertRaisesRegex(m.ValidationError,'settings.*real directory'): m.run_runtime(release/'start.sh',self.env(),launch=lambda *a:None)

class DocsRelease(unittest.TestCase):
 def test_readme_precise_directory_workflow(self):
  t=README.read_text().lower()
  for x in ('failed first install','swbattlefrontiipcserver_v1_1.exe','swbf2-original-server','real directory','sftp','reinstall','accept_lucasarts_license=yes','noncommercial_use=yes','only `battlefrontii.exe` is authenticated','structural','not legal advice','proprietary content is never downloaded','direct-connect join was verified on 2026-11-01'): self.assertIn(x,t)
  self.assertNotIn('tar.gz',t)
  self.assertNotIn('real client join remains unverified',t)
 def test_download_scope(self):
  t=INSTALL.read_text().lower(); urls=re.findall(r'https://[^\s\"\']+',t); self.assertEqual(len(urls),2); self.assertTrue(all(x.startswith('https://raw.githubusercontent.com/hifi/iss_extract/') for x in urls))
 def test_client_urls_and_no_server_patch(self):
  urls=set(re.findall(r'https?://[^\s)>]+',CLIENT.read_text())); self.assertEqual(urls,{'https://info.swbfgamers.com/downloads.html','https://info.swbfgamers.com/faq.html'}); t=CLIENT.read_text().lower(); self.assertNotIn('server patch',t); self.assertNotRegex(t,r'replace all instances|hex[ -]?edit|https?://[^\s)]+\.(?:exe|zip|7z|rar)\b')
  self.assertIn('direct-connect join was verified on 2026-11-01',t); self.assertNotIn('real client join remains unverified',t)
  self.assertIn('direct-connect join was verified on 2026-11-01',RT.read_text().lower())
 def test_validation_exact_count(self):
  match=re.search(r'completed (\d+) unit tests',VALIDATION.read_text()); self.assertIsNotNone(match); self.assertEqual(int(match.group(1)),unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]).countTestCases())
 def test_manifest(self):
  entries={relative:digest for digest,relative in (line.split('  ',1) for line in (ROOT/'SHA256SUMS').read_text().splitlines())}; expected={str(p.relative_to(ROOT)) for p in candidates() if p.name!='SHA256SUMS'}; self.assertEqual(set(entries),expected)
  for p,h in entries.items(): self.assertEqual(hashlib.sha256((ROOT/p).read_bytes()).hexdigest(),h,p)
 def test_public_privacy_and_proprietary_scan(self):
  all_texts=[]; release_texts=[]
  for p in candidates():
   self.assertNotIn(p.suffix.lower(),{'.cab','.dll','.exe','.msi','.rar','.7z','.iso'},p); data=p.read_bytes(); self.assertFalse(data.startswith(b'MZ'),p)
   if b'\0' not in data:
    decoded=data.decode(errors='replace'); all_texts.append(decoded)
    if p!=Path(__file__): release_texts.append(decoded)
  t='\n'.join(all_texts); release='\n'.join(release_texts).lower()
  for forbidden in ('mod'+'db.com','ds-'+'servers.com','dbolical.com','swbf'+'spy.com','patch_'+'swbfspy','privacy-'+'safe'): self.assertNotIn(forbidden,release)
  self.assertIsNone(re.search(r'/home/[A-Za-z0-9._-]+',t)); self.assertIsNone(re.search(r'\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b',t))
  self.assertIsNone(re.search(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',t,re.I))
  domains={d.lower() for d in re.findall(r'[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+)',t)}; self.assertLessEqual(domains,{'example.invalid'})
  self.assertNotRegex(t,r'(?i)(api[_-]?key|token|password)\s*[:=]\s*[\'\"][A-Za-z0-9_\-]{16,}')
 def test_maps(self):
  p=r'\b[a-z]{3}[0-9][cg]_(?:con|ctf|1flag|hunt|eli|ass)\b'; runtime=set(re.findall(p,RT.read_text())); docs=set(re.findall(p,MAPS.read_text())); self.assertEqual(len(runtime),85); self.assertEqual(runtime,docs)

if __name__=='__main__': unittest.main(verbosity=2)
