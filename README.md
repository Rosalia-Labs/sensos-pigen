# sensos-pigen

Small SensOS-specific wrappers around a user-provided `pi-gen` arm64 release.

This repo does not use `pi-gen` as a submodule, and it does not track the `pi-gen/` directory. You download or extract a `pi-gen` release into [`pi-gen`](/Users/keittth/Projects/sensos-pigen/pi-gen), and this repo adds only the minimal SensOS-specific logic needed to:

- fixed first-user support so the image can boot with a preconfigured user
- optional hotspot support, enabled by default
- thin wrapper scripts for configure, build, and burn

Defaults:

- first user: `sensos`
- first user password: `sensos`
- first-boot rename disabled
- SSH enabled
- hotspot enabled
- hotspot SSID: `sensos`
- hotspot password: `sensossensos`
- optional API password file: `custom-stage/00-sensos-hotspot/files/keys/api_password`

## Setup

Install the latest tagged `pi-gen` arm64 release into [`pi-gen`](/Users/keittth/Projects/sensos-pigen/pi-gen):

```bash
./bin/install-pi-gen.sh
```

Install a specific tag when needed:

```bash
./bin/install-pi-gen.sh --tag 2025-10-01-raspios-bookworm-arm64
```

The installed release metadata is recorded in [`VENDORED_PI_GEN`](/Users/keittth/Projects/sensos-pigen/VENDORED_PI_GEN).

## Workflow

Generate the pi-gen config:

```bash
./bin/configure-pi-gen.sh
```

Override defaults when needed:

```bash
./bin/configure-pi-gen.sh \
  --img-name sensos \
  --first-user-name sensos \
  --first-user-pass sensos \
  --hotspot-ssid sensos \
  --hotspot-password sensossensos
```

Build the image:

```bash
./bin/build-image.sh
```

By default, the build also clones
`https://github.com/Rosalia-Labs/sensos-client.git`, creates a compressed
tarball from that checkout, and installs it into
`/home/sensos/sensos-client.tar.gz` inside the image. The archive preserves a
top-level `sensos-client/` directory so extracting it does not spill files into
the current working directory. Override the source repo
or ref, or disable that behavior when needed:

```bash
./bin/build-image.sh --client-repo-url https://github.com/Rosalia-Labs/sensos-client.git --client-ref main
./bin/build-image.sh --no-client-tarball
```

To bake an API password into the image, create [`custom-stage/00-sensos-hotspot/files/keys/api_password`](/Users/keittth/Projects/sensos-pigen/custom-stage/00-sensos-hotspot/files/keys/api_password) before building. It will be installed to `/sensos/keys/api_password` in the image if present. The [`custom-stage/00-sensos-hotspot/files/keys/.gitignore`](/Users/keittth/Projects/sensos-pigen/custom-stage/00-sensos-hotspot/files/keys/.gitignore) file keeps that secret out of git by default.

Flash the resulting `.img` from [`pi-gen/deploy`](/Users/keittth/Projects/sensos-pigen/pi-gen/deploy):

```bash
./bin/burn-image.sh --device /dev/rdiskN
```

## Notes

- This repo expects an `arm64` `pi-gen` tree.
- The installed `pi-gen` release is recorded in [`VENDORED_PI_GEN`](/Users/keittth/Projects/sensos-pigen/VENDORED_PI_GEN).
- The custom hotspot stage lives in [`custom-stage/00-sensos-hotspot`](/Users/keittth/Projects/sensos-pigen/custom-stage/00-sensos-hotspot).
- `bin/build-image.sh` copies that stage into `pi-gen/stage2` for the build and removes it afterwards.
