# SPDX-License-Identifier: MIT
"""Compile immutable object trees into native APK v2 packages."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

collection, destination = map(Path, sys.argv[1:3])
architecture = sys.argv[3]
destination.mkdir()


def transform(command, source, target):
    with source.open('rb') as incoming, target.open('wb') as outgoing:
        with subprocess.Popen(command, stdin=incoming, stdout=subprocess.PIPE) as process:
            shutil.copyfileobj(process.stdout, outgoing)
            status = process.wait()
            if status:
                raise subprocess.CalledProcessError(status, command)


for package in json.loads((collection / 'packages.json').read_text()):
    record = json.loads((collection / package / 'metadata.json').read_text())
    version = record['version'] + '-r0'
    subprocess.run(['apk', 'version', '--check', version], check=True)
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        root = work / 'root'
        shutil.copytree(collection / package / 'tree', root, symlinks=True)
        subprocess.run(['chmod', '-R', 'u+w', str(root)], check=True)
        files = subprocess.check_output(['find', '.', '-mindepth', '1', '-printf', r'%P\0'], cwd=root)
        subprocess.run(['tar', '--null', '--no-recursion', '--mtime=@1', '--owner=0', '--group=0',
                        '--numeric-owner', '--format=posix',
                        '--pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0',
                        '-cf', str(work / 'data.tar'), '-T', '-'], cwd=root, check=True,
                       input=b'\0'.join(sorted(files.rstrip(b'\0').split(b'\0'))) + b'\0')
        transform(['abuild-tar', '--hash'], work / 'data.tar', work / 'hashed.tar')
        transform(['gzip', '-n9'], work / 'hashed.tar', work / 'data.tar.gz')
        datahash = hashlib.sha256((work / 'data.tar.gz').read_bytes()).hexdigest()
        control = work / 'control'
        control.mkdir()
        metadata = (f'pkgname = {record["name"]}\npkgver = {version}\narch = {architecture}\n'
                    f'origin = {record["name"]}\npkgdesc = Native-owned Nix-built payload\n'
                    'license = LicenseRef-Unknown\nbuilddate = 1\npackager = Nix Impurifiers\n')
        metadata += ''.join(f'depend = {name}=1-r0\n' for name in record['dependencies'])
        metadata += 'size = ' + subprocess.check_output(['du', '--apparent-size', '-sb', str(root)], text=True).split()[0] + '\n'
        metadata += f'datahash = {datahash}\n'
        (control / '.PKGINFO').write_text(metadata)
        subprocess.run(['tar', '--sort=name', '--mtime=@1', '--owner=0', '--group=0', '--numeric-owner',
                        '-cf', str(work / 'control.tar'), '-C', str(control), '.PKGINFO'], check=True)
        transform(['abuild-tar', '--cut'], work / 'control.tar', work / 'cut.tar')
        transform(['gzip', '-n9'], work / 'cut.tar', work / 'control.tar.gz')
        artifact = destination / f'{record["name"]}-{version}.apk'
        with artifact.open('wb') as output:
            for fragment in ('control.tar.gz', 'data.tar.gz'):
                with (work / fragment).open('rb') as stream:
                    shutil.copyfileobj(stream, output)
