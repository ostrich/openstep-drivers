# KernelMappingFix

Corrects stale memory mappings behind intermittent checksum and process-start
failures observed in OPENSTEP 4.2 under hardware virtualization. It applies the
fix in memory through a small DriverKit module, leaving the original kernel
file unchanged. It does not require a particular disk, network or video driver.

**Especially important for QEMU/KVM: installing this fix is strongly
recommended.** Failures were reproduced under KVM on an affected host, while
equivalent TCG control workloads passed. The module works with both KVM and TCG.

## Install

Download `KernelMappingFix-0.1-1.pkg.I.tar.gz` from
[Releases](https://github.com/ostrich/openstep-drivers/releases/latest), extract
it with `gnutar -xzf`, and install the included package as root. Then run:

```sh
/usr/local/sbin/kernel-mapping-fix-configure enable
```

Shut down cleanly and boot again. Check the loaded module with:

```sh
/usr/local/sbin/kernel-mapping-fixctl --status
```

Normal status is `result=1 image=2`, with equal before/after CR0 values. The
[package README](module/README.txt) explains status codes, disabling the module
and package removal. Installation does not enable boot loading automatically.

This release supports the original Intel OPENSTEP 4.2 kernel with SHA-256:

```text
33469393c0843fc741942c3ae9d91d838467d72abd647dcf2e5bf499a3f14890
```

The module checks the relevant code and symbol addresses before writing. It
refuses conflicting code and multiprocessor configurations, and recognizes the
same fix already applied. Keep it loaded until shutdown. There is no live undo;
disable boot registration and reboot to return to stock behavior.

The fix starts when the module loads. It cannot protect earlier boot activity
or repair corruption that has already occurred. Other mapping and permission
changes are outside this patch's scope.

## What it changes

The original removal path invalidates address translations before clearing its
page-table entries. Speculative translation can refill an old mapping between
those operations and retain it after the memory is reused.

The fix applies to every caller of the removal helper:

1. Clear PTEs, then invalidate translations before deallocating mappings.
2. Clear retired PDEs and invalidate before their tables enter the reuse list.
3. Skip the obsolete early invalidation in `pmap_remove`.

Small ranges use `INVLPG`; larger ranges and retired tables reload CR3, following
the kernel's existing size-based policy. The module excludes interrupts while
applying the patch, restores write protection, and verifies the result. Its
added routines live in unused kernel padding, with no calls into module code.
It does not disable integrity checks, retry failures or modify applications.

`ordered-invalidation.patch` gives the corresponding historical source changes,
including compiler memory barriers. The original instructions were checked
against the supported kernel, rather than inferred solely from source similarity.

## Build

Generating the patch inputs needs Python 3, GNU binutils and your own copy of
the supported kernel. From this directory on Linux:

```sh
python3 generate-module-inputs.py original-kernel module/patch-inputs.h
```

Copy `module/` to an OPENSTEP 4.2 Developer Tools guest and run `make` there.
The output is `module/KernelMappingFix.config/` and
`module/kernel-mapping-fixctl`. No SDK or compatibility library is needed to
run the binary package.

For host-side packaging, use `nextpkg` from
[nextstep-toolchain](https://github.com/ostrich/nextstep-toolchain). Copy
`KernelMappingFix_reloc` and `kernel-mapping-fixctl` into a host build directory:

```sh
python3 package.py --build build-results --output package-output \
  --nextpkg /path/to/nextstep-toolchain/bin/nextpkg
```

The package uses canonical private driver paths. `/usr/Devices` is a system
alias, not a second payload directory. The boot helper preserves other drivers
and makes a backup before changing registration.

For an optional separate kernel-file output, rather than the module:

```sh
python3 patch.py original-kernel patched-kernel --record patch.json
python3 test-patch.py original-kernel
```

This refuses unsupported inputs and existing outputs, preserves the original
file, and records every edit. Kernel images and SDK files are not distributed.

## Tests

Portable boot-helper tests run without an SDK:

```sh
python3 test-configure.py
```

Native dynamic application under KVM and boot loading under KVM and TCG passed
4,500 launch checks, 600 snapshot checks and 600 patterned-file read processes.
Kernel files remained unchanged, and write protection was restored exactly.
Read-only mode, already-fixed detection, conflicting-code refusal, native package
installation, receipt/file checks and removal-hook behavior were also verified.
A boot with loading disabled restored stock code. Test guests halted cleanly
and passed filesystem checks. Two native builds produced identical binaries.

These are bounded tests of the supported kernel and removal path, not a claim
that every OPENSTEP memory-management operation is correct. See the
[validation record](../docs/kernel-mapping-fix-validation.json).
