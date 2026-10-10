#!/usr/bin/env python3
"""Add VirtioBlk to a copy of the user's OPENSTEP 4.2 driver floppy."""
import argparse
import hashlib
import io
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path


def main():
    if not __debug__:
        raise SystemExit("Run without -O; floppy validation must remain enabled")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True, help='Original 1.44 MiB driver floppy')
    parser.add_argument('--package', type=Path, required=True, help='VirtioBlk distribution tar.gz')
    parser.add_argument('--nextufs', type=Path, required=True, help='nextufs executable with writable FUSE support')
    parser.add_argument('--output', type=Path, required=True, help='New image; must not already exist')
    args = parser.parse_args()
    base, output = args.base.resolve(), args.output.resolve()
    assert base.stat().st_size == 1474560, 'Expected a 1.44 MiB driver floppy'
    if output.exists():
        raise FileExistsError(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='driver-floppy-', dir=output.parent) as directory:
        work = Path(directory)
        image, mount = work/'floppy.img', work/'mount'
        mount.mkdir()
        with tarfile.open(args.package) as archive:
            native = archive.extractfile('VirtioBlk.pkg/VirtioBlk.tar.Z').read()
        packed = work/'payload.tar.Z'; packed.write_bytes(native)
        blob = subprocess.check_output(['zcat', str(packed)])
        files = {}
        prefix = 'private/Drivers/i386/VirtioBlk.config/'
        with tarfile.open(fileobj=io.BytesIO(blob)) as archive:
            for member in archive:
                name = Path(member.name).as_posix()
                assert not Path(name).is_absolute() and '..' not in Path(name).parts
                assert member.isdir() or member.isfile(), name
                if member.isfile() and name.startswith(prefix):
                    relative = name.removeprefix(prefix)
                    assert relative not in files
                    files[relative] = archive.extractfile(member).read()
        assert 'VirtioBlk_reloc' in files and 'Default.table' in files and 'Instance0.table' in files
        shutil.copyfile(base, image)
        tool = str(args.nextufs.resolve())
        subprocess.run([tool, 'mount', str(image), str(mount), '-o', 'rw,mode=su'], check=True)
        try:
            catalog = mount/'private/Drivers/i386'
            assert (catalog/'EIDE.config').is_dir() and (catalog/'PCIBus.config').is_dir()
            # Reclaim space without removing any driver in the stock boot list.
            for name in ('S3ViRGEDisplayDriver.config', 'DPTSCSIDriver.config'):
                candidate = catalog/name
                if candidate.is_dir(): shutil.rmtree(candidate)
            target = catalog/'VirtioBlk.config'
            target.mkdir()
            for name, data in files.items():
                path = target/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                path.chmod(0o644)
            for name, data in files.items():
                assert (target/name).read_bytes() == data
            helper = Path(__file__).resolve().parents[1]/'virtio/package-blk/configure-install.sh'
            shutil.copyfile(helper, mount/'configure-install.sh')
            (mount/'configure-install.sh').chmod(0o644)
        finally:
            subprocess.run(['fusermount3', '-u', str(mount)], check=True)
        subprocess.run([tool, 'fsck', '-n', str(image)], check=True)
        with output.open('xb') as destination, image.open('rb') as source:
            shutil.copyfileobj(source, destination)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_name(output.name+'.sha256').write_text(digest+'  '+output.name+'\n')
    print(output)


if __name__ == '__main__':
    main()
