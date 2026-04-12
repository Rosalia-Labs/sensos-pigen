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

## Supported Paths

There are two reasonable ways to get a SensOS Pi up:

- build a custom image with this repo and `pi-gen`
- flash a stock Raspberry Pi OS image with Raspberry Pi Imager, then install `sensos-client` afterward

The `pi-gen` path is leaner because it can pre-bake the SensOS-specific defaults,
hotspot behavior, and optional bundled `sensos-client` tarball into the image.
The Raspberry Pi Imager path is often smoother operationally because it uses the
standard Raspberry Pi provisioning flow first, but it usually brings along more
of the general Raspberry Pi OS environment unless you intentionally choose a Lite
image.

Important Wi-Fi tradeoff:

- if the Pi has only one Wi-Fi NIC, an automatically enabled hotspot can get in
  the way later when you want that same radio to join an upstream Wi-Fi network
  as a client
- if that handoff is not handled cleanly, the bootstrap hotspot may continue
  trying to reclaim the interface after you start configuring normal Wi-Fi
  client access
- if the Pi has two working Wi-Fi interfaces, setup is much easier because one
  NIC can host the hotspot while the other joins the upstream Wi-Fi network
- a direct Ethernet connection is often the simpler first-install path and
  reduces the need for an automatic hotspot entirely
- for devices that should ultimately join normal Wi-Fi instead of acting as an
  access point, disabling the bootstrap hotspot from the start is often the
  simpler operational choice on single-radio hardware

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

If the target Pi will later use its built-in Wi-Fi to join another network,
disable the automatic hotspot during image generation:

```bash
./bin/configure-pi-gen.sh --disable-hotspot
```

That is usually the better default if you expect to do first access and install
over a direct Ethernet cable. Keep the hotspot enabled only when Wi-Fi-based
field setup is worth the tradeoff. If the device has two working Wi-Fi
interfaces, that tradeoff is much smaller because the AP and client roles do
not have to compete for the same radio.

For single-radio devices, this is often the simplest path:

```bash
./bin/configure-pi-gen.sh --disable-hotspot
./bin/build-image.sh
```

That keeps the image lean and avoids unnecessary competition between
`config-wifi` and the bootstrap hotspot on the same interface.

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

## Alternative: Raspberry Pi Imager

If you do not need a pre-baked SensOS image, you can also:

1. Use Raspberry Pi Imager to flash a stock Raspberry Pi OS image.
2. Prefer a Raspberry Pi OS Lite image if you want to stay closer to the lean
   footprint of the `pi-gen` flow.
3. Boot the Pi, complete the normal Raspberry Pi OS first-boot setup, and get
   network access working.
4. Clone [`sensos-client`](/Users/tkeitt/Projects/sensos/sensos-client/README.md)
   onto the Pi and run [`./install`](/Users/tkeitt/Projects/sensos/sensos-client/install)
   as the bootstrap user:

```bash
git clone https://github.com/Rosalia-Labs/sensos-client.git
cd sensos-client
./install
```

Tradeoffs:

- Raspberry Pi Imager can be simpler and more reliable for initial flashing and
  first boot.
- A full Raspberry Pi OS desktop image brings the whole GUI stack and related
  packages, so it is not as lean as the custom `pi-gen` image.
- Choosing a Lite image narrows that gap and is the better fit when you plan to
  install `sensos-client` later on a stock OS base.
- This path also avoids starting with an automatic AP on the primary Wi-Fi NIC,
  which is often easier if the device is meant to join an existing Wi-Fi
  network later.
- If you have a laptop or adapter handy, a direct Ethernet link is often enough
  for initial access and install, so the hotspot becomes optional convenience
  rather than a requirement.
- In testing, Wi-Fi join behavior may depend as much on the target network
  security environment as on whether the base image came from `pi-gen` or a
  stock Raspberry Pi OS install.
- In particular, mixed WPA2/WPA3 mesh environments with roaming can be more
  troublesome than a simple standalone network. For first setup, a dedicated
  2.4 GHz guest network using WPA2 only may be the more predictable choice.

## Notes

- This repo expects an `arm64` `pi-gen` tree.
- The installed `pi-gen` release is recorded in [`VENDORED_PI_GEN`](/Users/keittth/Projects/sensos-pigen/VENDORED_PI_GEN).
- The custom hotspot stage lives in [`custom-stage/00-sensos-hotspot`](/Users/keittth/Projects/sensos-pigen/custom-stage/00-sensos-hotspot).
- `bin/build-image.sh` copies that stage into `pi-gen/stage2` for the build and removes it afterwards.
