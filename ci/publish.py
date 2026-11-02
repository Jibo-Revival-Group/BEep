#!/usr/bin/env python3
"""Publish a BEep build to apps.5x1.com (repo JRG5x1/alt).

usage: ci/publish.py <ipa or apk> <site checkout> "<what's new>"

iPhone (.ipa): the IPA's bundle ID picks the app in the AltStore source, source.json:
com.jiborevival.beep (BEep) or com.jiborevival.beep.beta (BEep BETA).
Android (.apk, named by CI BEep-<version>.apk or BEep-BETA-<version>-<build>.apk): android.json,
which the site's Android download buttons read.

BEep's builds live in the site's apps/ folder. BETA builds (one per push) are release downloads
on JRG5x1/alt instead, keeping the site repo small; only the latest KEEP stay listed.
alt.5x1.com, the old address, is a separate small site (JRG5x1/alt-redirect, checked out next to
the site) that forwards browsers here and keeps a copy of source.json, because AltStore can't
follow a page redirect; this script refreshes that copy. Commit and push both checkouts afterwards.

Android builds also go into the 5x1 F-Droid repo (apps.5x1.com/fdroid/repo). Its workspace, with the
index signing key, is FDROID (private, never in the site); the signed repo/ folder is synced into the
site's fdroid/repo. Needs the JDK and SDK in /root/android-tools.
"""
import datetime, json, os, plistlib, re, shutil, subprocess, sys, zipfile

KEEP = 5
SITE = 'https://apps.5x1.com'
build_file, site, notes = sys.argv[1], sys.argv[2], sys.argv[3]
mirror = os.path.join(os.path.dirname(os.path.abspath(site)), 'alt-redirect')
today = datetime.date.today().isoformat()


def beta_release(tag, title, file):
    path = os.path.join(os.environ.get('TMPDIR', '/tmp'), os.path.basename(file))
    if os.path.abspath(path) != os.path.abspath(file): shutil.copy(build_file, path)
    subprocess.run(['gh', 'release', 'create', tag, '-R', 'JRG5x1/alt', '--title', title, '--notes', notes, path], check=True)
    return 'https://github.com/JRG5x1/alt/releases/download/%s/%s' % (tag, os.path.basename(file))


def drop_old(versions, prefix):
    for old in versions[KEEP:]:
        subprocess.run(['gh', 'release', 'delete', prefix + old['buildVersion'], '-R', 'JRG5x1/alt', '--yes', '--cleanup-tag'])
    return versions[:KEEP]


FDROID = '/root/jibo-stuff/BEep-signing/fdroid'
TOOLS = '/root/android-tools'


def fdroid_publish(apk, package, version_code):
    if not os.path.isdir(FDROID):
        print('warning: no %s; F-Droid repo not updated' % FDROID); return
    repo = os.path.join(FDROID, 'repo')
    shutil.copy(apk, repo)
    changelogs = os.path.join(FDROID, 'metadata', package, 'en-US', 'changelogs')
    os.makedirs(changelogs, exist_ok=True)
    with open(os.path.join(changelogs, '%s.txt' % version_code), 'w') as out: out.write(notes + '\n')
    # Keep the newest KEEP builds of this app; F-Droid lists every APK left in repo/.
    pattern = re.compile(r'BEep-BETA-[\d.]+-(\d+)\.apk$' if package.endswith('.beta') else r'BEep-([\d.]+)\.apk$')
    mine = [f for f in os.listdir(repo) if pattern.match(f)]
    key = (lambda f: int(pattern.match(f).group(1))) if package.endswith('.beta') else (lambda f: [int(x) for x in pattern.match(f).group(1).split('.')])
    for old in sorted(mine, key=key)[:-KEEP]: os.remove(os.path.join(repo, old))
    env = dict(os.environ, JAVA_HOME=TOOLS + '/jdk', ANDROID_HOME=TOOLS + '/sdk', PATH=TOOLS + '/jdk/bin:' + os.environ['PATH'])
    subprocess.run([os.path.join(os.path.dirname(FDROID), 'fdroid-venv/bin/fdroid'), 'update'], cwd=FDROID, env=env, check=True)
    subprocess.run(['rsync', '-a', '--delete', repo + '/', os.path.join(site, 'fdroid', 'repo') + '/'], check=True)
    print('F-Droid repo updated: %s %s' % (package, version_code))


def write(path, value):
    with open(path, 'w') as out:
        json.dump(value, out, indent=2, ensure_ascii=False)
        out.write('\n')


if build_file.endswith('.apk'):
    match = re.match(r'BEep(-BETA)?-([\d.]+)(?:-(\d+))?\.apk$', os.path.basename(build_file))
    assert match, 'name the APK BEep-<version>.apk or BEep-BETA-<version>-<build>.apk'
    beta, version, build = bool(match.group(1)), match.group(2), match.group(3) or ''
    path = os.path.join(site, 'android.json')
    android = json.load(open(path)) if os.path.exists(path) else {}
    if beta:
        url = beta_release('beep-android-beta-' + build, 'BEep BETA for Android %s (%s)' % (version, build), build_file)
        entry = {'version': version, 'buildVersion': build, 'date': today, 'notes': notes, 'downloadURL': url, 'size': os.path.getsize(build_file)}
        android['betaVersions'] = drop_old([entry] + [v for v in android.get('betaVersions', []) if v['buildVersion'] != build], 'beep-android-beta-')
        android['beta'] = entry
    else:
        name = os.path.basename(build_file)
        shutil.copy(build_file, os.path.join(site, 'apps', name))
        android['stable'] = {'version': version, 'date': today, 'notes': notes, 'downloadURL': SITE + '/apps/' + name, 'size': os.path.getsize(build_file)}
    write(path, android)
    print('Android %s %s -> %s' % ('BEep BETA' if beta else 'BEep', version, (android['beta'] if beta else android['stable'])['downloadURL']))
    badging = subprocess.run([sorted(__import__('glob').glob(TOOLS + '/sdk/build-tools/*/aapt2'))[-1], 'dump', 'badging', build_file],
                             capture_output=True, text=True, check=True).stdout
    package, version_code = re.search(r"package: name='([^']+)' versionCode='(\d+)'", badging).groups()
    fdroid_publish(build_file, package, version_code)
    sys.exit(0)

archive = zipfile.ZipFile(build_file)
plist = plistlib.loads(archive.read(next(n for n in archive.namelist() if re.match(r'Payload/[^/]+\.app/Info\.plist$', n))))
bundle, version, build = plist['CFBundleIdentifier'], plist['CFBundleShortVersionString'], plist['CFBundleVersion']
beta = bundle == 'com.jiborevival.beep.beta'
assert beta or bundle == 'com.jiborevival.beep', bundle

path = os.path.join(site, 'source.json')
source = json.load(open(path))
app = next((a for a in source['apps'] if a['bundleIdentifier'] == bundle), None)
if app is None:  # first BETA: start from BEep's listing
    stable = next(a for a in source['apps'] if a['bundleIdentifier'] == 'com.jiborevival.beep')
    app = {k: v for k, v in stable.items() if k != 'versions'}
    app.update(name='BEep BETA', bundleIdentifier=bundle, iconURL=SITE + '/images/beep-beta-icon.png',
               subtitle='Try new BEep features first.',
               localizedDescription='The newest BEep, published with every change before it reaches BEep. It installs next to BEep and can have bugs.\n\n' + stable['localizedDescription'],
               versions=[])
    source['apps'].append(app)
# AltStore refuses an app whose listed permissions differ from its Info.plist.
app.setdefault('appPermissions', {})['privacy'] = {k: v for k, v in plist.items() if k.endswith('UsageDescription')}

if beta:
    url = beta_release('beep-beta-' + build, 'BEep BETA %s (%s)' % (version, build), 'BEep-BETA-%s-%s.ipa' % (version, build))
else:
    name = 'BEep-%s.ipa' % version
    shutil.copy(build_file, os.path.join(site, 'apps', name))
    url = SITE + '/apps/' + name

entry = {'version': version, 'buildVersion': build, 'date': today, 'localizedDescription': notes, 'downloadURL': url,
         'size': os.path.getsize(build_file), 'minOSVersion': plist.get('MinimumOSVersion', '16.0')}
app['versions'] = [entry] + [v for v in app['versions'] if (v['version'], v['buildVersion']) != (version, build)]
if beta: app['versions'] = drop_old(app['versions'], 'beep-beta-')
# Older SideStore reads the newest version from these.
app.update(version=version, versionDate=entry['date'], versionDescription=notes, downloadURL=url, size=entry['size'])

write(path, source)
if os.path.isdir(mirror): shutil.copy(path, os.path.join(mirror, 'source.json'))
else: print('warning: no %s checkout; alt.5x1.com/source.json not refreshed' % mirror)
print('%s %s (%s) -> %s' % (app['name'], version, build, url))
