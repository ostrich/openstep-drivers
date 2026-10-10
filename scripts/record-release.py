#!/usr/bin/env python3
"""Attach shared source identity and native build evidence to assembled archives."""
import argparse
import gzip
import hashlib
import io
import json
import tarfile
from pathlib import Path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archives', required=True, type=Path)
    parser.add_argument('--sources', required=True, type=Path)
    parser.add_argument('--native-records', required=True, type=Path)
    parser.add_argument('--receipt', required=True, type=Path)
    args = parser.parse_args()
    sources = json.loads(args.sources.read_text())
    records = json.loads(args.native_records.read_text())
    snapshot = digest(json.dumps(sources, sort_keys=True, separators=(',', ':')).encode())
    receipt = {'schema': 1, 'source_snapshot_sha256': snapshot,
               'compiler': 'NeXT cc-744.13, GCC 2.7.2.1',
               'native_builder': 'OPENSTEP 4.2 Intel Developer Tools, QEMU KVM',
               'fresh_runtime_tests': False,
               'runtime_validation': 'Prior evidence retained through byte-identical installed payload comparison',
               'firmware_rebuilt': False, 'archives': {}}
    for archive in sorted(args.archives.glob('*.tar.gz')):
        with tarfile.open(archive, 'r:gz') as tar:
            entries = [(m, tar.extractfile(m).read() if m.isfile() else None)
                       for m in tar.getmembers()]
        assert all(m.isdir() or m.isfile() for m, _ in entries)
        assert len({m.name for m, _ in entries}) == len(entries)
        assert all(not Path(m.name).is_absolute() and '..' not in Path(m.name).parts
                   for m, _ in entries)
        services = archive.name.startswith('OpenStepVirtioServices-')
        prefix = 'OpenStepVirtioServices-0.1/' if services else ''
        names = ['VirtioConsole', 'OpenStepVirtioServices'] if services else [
            'EIDEBusMaster' if archive.name.startswith('EIDE-') else archive.name.split('-')[0]]
        build = {'schema': 1, 'source_snapshot_sha256': snapshot,
                 'compiler': receipt['compiler'],
                 'native_binaries_recompiled': all(records[n]['native_binaries_recompiled'] for n in names),
                 'components': {n: records[n] for n in names},
                 'source_sha256': sources}
        content = {m.name.removeprefix(prefix): digest(data)
                   for m, data in entries if data is not None and
                   m.name not in (prefix+'BUILD.json', prefix+'SHA256.json')}
        build['archive_contents_sha256'] = content
        data = (json.dumps(build, indent=2)+'\n').encode()
        info = tarfile.TarInfo(prefix+'BUILD.json')
        info.size = len(data)
        info.mode = 0o644
        entries = [(m, b) for m, b in entries if m.name not in (prefix+'BUILD.json', prefix+'SHA256.json')]
        entries.append((info, data))
        hashes = {m.name.removeprefix(prefix): digest(b) for m, b in entries if b is not None}
        data = (json.dumps(hashes, indent=2)+'\n').encode()
        info = tarfile.TarInfo(prefix+'SHA256.json')
        info.size = len(data)
        info.mode = 0o644
        entries.append((info, data))
        temporary = archive.with_suffix(archive.suffix+'.tmp')
        with temporary.open('xb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as gz, tarfile.open(fileobj=gz, mode='w', format=tarfile.USTAR_FORMAT) as tar:
            for member, payload in entries:
                member.uid = member.gid = 0
                member.uname = 'root'
                member.gname = 'wheel'
                member.mtime = 0
                tar.addfile(member, io.BytesIO(payload) if payload is not None else None)
        with tarfile.open(temporary, 'r:gz') as tar:
            for name, expected in hashes.items():
                assert digest(tar.extractfile(prefix+name).read()) == expected, name
        temporary.replace(archive)
        checksum = digest(archive.read_bytes())
        archive.with_name(archive.name+'.sha256').write_text(checksum+'  '+archive.name+'\n')
        receipt['archives'][archive.name] = {'sha256': checksum, 'components': names,
                                           'internal_hashes_verified': True}
    assert len(receipt['archives']) == 8, 'Expected eight driver/service distributions'
    args.receipt.write_text(json.dumps(receipt, indent=2)+'\n')
    print('Recorded and verified eight archives from snapshot '+snapshot)


if __name__ == '__main__':
    main()
