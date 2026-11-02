#!/usr/bin/env python3
"""Publish a BEep build to the AltStore source at alt.5x1.com (repo JRG5x1/alt).

usage: ci/publish.py <ipa> <alt checkout> "<what's new>"

The IPA's bundle ID picks the app: com.jiborevival.beep (BEep) or com.jiborevival.beep.beta
(BEep BETA). BEep's IPAs live in the site's apps/ folder. BETA builds (one per push) are release
downloads on JRG5x1/alt instead, keeping the site repo small; only the latest KEEP stay listed.
Everything else is read from the IPA itself, so the source always matches what's in it.
Commit and push the alt checkout afterwards.
"""
import datetime, json, os, plistlib, re, shutil, subprocess, sys, zipfile

KEEP = 5
ipa, alt, notes = sys.argv[1], sys.argv[2], sys.argv[3]

archive = zipfile.ZipFile(ipa)
plist = plistlib.loads(archive.read(next(n for n in archive.namelist() if re.match(r'Payload/[^/]+\.app/Info\.plist$', n))))
bundle, version, build = plist['CFBundleIdentifier'], plist['CFBundleShortVersionString'], plist['CFBundleVersion']
beta = bundle == 'com.jiborevival.beep.beta'
assert beta or bundle == 'com.jiborevival.beep', bundle

path = os.path.join(alt, 'source.json')
source = json.load(open(path))
app = next((a for a in source['apps'] if a['bundleIdentifier'] == bundle), None)
if app is None:  # first BETA: start from BEep's listing
    stable = next(a for a in source['apps'] if a['bundleIdentifier'] == 'com.jiborevival.beep')
    app = {k: v for k, v in stable.items() if k != 'versions'}
    app.update(name='BEep BETA', bundleIdentifier=bundle, iconURL='https://alt.5x1.com/images/beep-beta-icon.png',
               subtitle='Try new BEep features first.',
               localizedDescription='The newest BEep, published with every change before it reaches BEep. It installs next to BEep and can have bugs.\n\n' + stable['localizedDescription'],
               versions=[])
    source['apps'].append(app)
# AltStore refuses an app whose listed permissions differ from its Info.plist.
app.setdefault('appPermissions', {})['privacy'] = {k: v for k, v in plist.items() if k.endswith('UsageDescription')}

if beta:
    tag, name = 'beep-beta-' + build, 'BEep-BETA-%s-%s.ipa' % (version, build)
    shutil.copy(ipa, os.path.join(os.environ.get('TMPDIR', '/tmp'), name))
    subprocess.run(['gh', 'release', 'create', tag, '-R', 'JRG5x1/alt', '--title', 'BEep BETA %s (%s)' % (version, build),
                    '--notes', notes, os.path.join(os.environ.get('TMPDIR', '/tmp'), name)], check=True)
    url = 'https://github.com/JRG5x1/alt/releases/download/%s/%s' % (tag, name)
else:
    name = 'BEep-%s.ipa' % version
    shutil.copy(ipa, os.path.join(alt, 'apps', name))
    url = 'https://alt.5x1.com/apps/' + name

entry = {'version': version, 'buildVersion': build, 'date': datetime.date.today().isoformat(),
         'localizedDescription': notes, 'downloadURL': url, 'size': os.path.getsize(ipa),
         'minOSVersion': plist.get('MinimumOSVersion', '16.0')}
app['versions'] = [entry] + [v for v in app['versions'] if (v['version'], v['buildVersion']) != (version, build)]
if beta:
    for old in app['versions'][KEEP:]:
        subprocess.run(['gh', 'release', 'delete', 'beep-beta-' + old['buildVersion'], '-R', 'JRG5x1/alt', '--yes', '--cleanup-tag'])
    app['versions'] = app['versions'][:KEEP]
# Older SideStore reads the newest version from these.
app.update(version=version, versionDate=entry['date'], versionDescription=notes, downloadURL=url, size=entry['size'])

with open(path, 'w') as out:
    json.dump(source, out, indent=2, ensure_ascii=False)
    out.write('\n')
print('%s %s (%s) -> %s' % (app['name'], version, build, url))
