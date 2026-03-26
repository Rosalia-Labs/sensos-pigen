# sensos-pigen

Small SensOS-specific wrappers around a user-provided `pi-gen` release.

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

## Setup

Download a `pi-gen` release and place it at [`pi-gen`](/Users/keittth/Projects/sensos-pigen/pi-gen).

The currently recommended release is recorded in [`VENDORED_PI_GEN`](/Users/keittth/Projects/sensos-pigen/VENDORED_PI_GEN).

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

Flash the resulting `.img` from [`pi-gen/deploy`](/Users/keittth/Projects/sensos-pigen/pi-gen/deploy):

```bash
./bin/burn-image.sh --device /dev/rdiskN
```

## Notes

- The recommended `pi-gen` release is recorded in [`VENDORED_PI_GEN`](/Users/keittth/Projects/sensos-pigen/VENDORED_PI_GEN).
- The custom hotspot stage lives in [`custom-stage/00-sensos-hotspot`](/Users/keittth/Projects/sensos-pigen/custom-stage/00-sensos-hotspot).
- `bin/build-image.sh` copies that stage into `pi-gen/stage2` for the build and removes it afterwards.
