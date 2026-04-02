# Preconfigured Image Facility

## Goal

Add a facility that can produce a customized Raspberry Pi image file as an artifact, without requiring the final burn step to also be the configuration step.

This is primarily for a remote `sensos-server` workflow:

1. Build or keep a reusable base SensOS image on the server.
2. Call a local API on that server with a desired device configuration.
3. Produce a new preconfigured `.img` file.
4. Download that `.img` file elsewhere and burn it with a normal flasher.

The first target is `config-network`, specifically enough network state for a newly booted device to reach WireGuard and the rest of the API without exposing the API port publicly.

## Current State

The repo currently supports only build-time customization:

- [`bin/configure-pi-gen.sh`](/Users/keittth/Projects/sensos-pigen/bin/configure-pi-gen.sh) writes `pi-gen/config`.
- [`bin/build-image.sh`](/Users/keittth/Projects/sensos-pigen/bin/build-image.sh) builds a full image.
- [`custom-stage/00-sensos-hotspot/00-run.sh`](/Users/keittth/Projects/sensos-pigen/custom-stage/00-sensos-hotspot/00-run.sh) injects hotspot settings and optional secrets into the root filesystem during the `pi-gen` build.
- [`bin/burn-image.sh`](/Users/keittth/Projects/sensos-pigen/bin/burn-image.sh) only flashes an existing `.img`.

That works for shared defaults, but it does not support per-device image generation after the base image already exists.

## Proposed Direction

Split image handling into two layers:

1. Base image build
2. Post-build image customization

The base image remains a generic SensOS artifact produced by `pi-gen`.

The new layer takes:

- a source `.img`
- a structured configuration payload
- an output path

and produces:

- a new `.img` with the requested device-specific configuration baked in

That makes "customize image" a first-class operation separate from both "build image" and "burn image".

## Recommended Model

Introduce a new script, likely:

- [`bin/customize-image.sh`](/Users/keittth/Projects/sensos-pigen/bin/customize-image.sh)

It should:

1. Copy a base `.img` to a new output file.
2. Mount the image partitions using loop devices or a supported image-mounting helper.
3. Modify only a narrow set of files inside the mounted image.
4. Unmount cleanly.
5. Return the path to the finished `.img`.

This keeps the customization step deterministic and easy to wrap in an API.

## Configuration Strategy

Do not treat `config-network` as an ad hoc special case forever. Instead, define a small image customization schema now, even if only one section is implemented at first.

Example shape:

```json
{
  "device_id": "sensos-001",
  "config_network": {
    "mode": "wifi",
    "wifi": {
      "ssid": "field-net",
      "psk": "example-password",
      "country": "US"
    },
    "wireguard": {
      "enabled": true,
      "endpoint": "vpn.example.net:51820",
      "address": "10.20.0.14/32",
      "private_key": "...",
      "public_key": "...",
      "preshared_key": "...",
      "allowed_ips": [
        "10.20.0.0/24",
        "192.168.50.0/24"
      ]
    }
  }
}
```

Even if the initial CLI accepts flags instead of JSON, the internal representation should look like this so an API can pass the same payload later.

## First Implementation Slice: `config-network`

The first version should only support enough network bootstrap to make the device reachable through its intended private path.

Recommended scope:

- Wi-Fi client credentials for the target environment
- WireGuard client configuration
- Optional fallback hotspot policy

Recommended non-goals for v1:

- Full application provisioning
- User account mutation beyond what already happens in `pi-gen`
- Arbitrary file injection
- Package installation after the image is built

## How `config-network` Should Land in the Image

Avoid editing many live system files directly in the customizer. Instead, have the customizer write a single declarative payload into the image, and let the image itself apply it on first boot.

Suggested flow:

1. The customizer writes a file such as `/sensos/config/image-config.json`.
2. A new first-boot systemd service reads that file.
3. The service applies network configuration using the host OS tools already present in the image.
4. The service records success and disables itself.

This is safer than trying to perfectly reproduce all OS-specific network file formats from outside the image.

Benefits:

- The API/server only writes one payload file into the image.
- The booted image applies config using its own `nmcli`, filesystem layout, and service dependencies.
- Future config areas can reuse the same mechanism.

## Why First-Boot Application Is Better Than Direct Offline Mutation

Direct offline mutation looks simpler at first, but it couples the customizer to Raspberry Pi OS internals:

- exact partition layout
- NetworkManager connection file formats
- service enablement details
- file ownership and permissions

A first-boot apply model reduces that coupling. The customizer only needs to:

- mount the image
- copy one config file
- optionally copy a small number of secret files
- possibly toggle a marker file or enable one service

The image then handles the OS-specific work itself.

## Changes Needed in This Repo

### 1. Add a general image config payload path

Add a stable location in the image such as:

- `/sensos/config/image-config.json`

and possibly:

- `/sensos/config/secrets/`

### 2. Add a first-boot configurator service

Add a new custom stage component that installs:

- a service such as `sensos-image-config.service`
- a script such as `/usr/local/sbin/sensos-apply-image-config`

Responsibilities:

- detect whether `/sensos/config/image-config.json` exists
- validate it
- apply network settings
- log clearly to journald and a file under `/var/log/sensos-image-config.log`
- mark completion
- avoid reapplying on every boot unless explicitly requested

### 3. Add an offline customizer

Add:

- [`bin/customize-image.sh`](/Users/keittth/Projects/sensos-pigen/bin/customize-image.sh)

Responsibilities:

- select a base image
- copy it to an output file
- mount boot and root partitions
- write `/sensos/config/image-config.json`
- optionally copy secrets
- unmount safely

### 4. Keep burn separate

Do not merge customization into [`bin/burn-image.sh`](/Users/keittth/Projects/sensos-pigen/bin/burn-image.sh).

`burn-image.sh` should stay dumb:

- choose image
- confirm target device
- write bytes

That separation is useful for both local and remote workflows.

## CLI Sketch

Two reasonable interfaces:

### Minimal CLI for the first version

```bash
./bin/customize-image.sh \
  --input ./pi-gen/deploy/sensos.img \
  --output ./artifacts/sensos-device-001.img \
  --wifi-ssid field-net \
  --wifi-psk 'secret' \
  --wifi-country US \
  --wg-endpoint vpn.example.net:51820 \
  --wg-address 10.20.0.14/32 \
  --wg-private-key-file ./secrets/device-001.wg.key \
  --wg-public-key 'server-public-key' \
  --wg-preshared-key-file ./secrets/device-001.psk \
  --wg-allowed-ips 10.20.0.0/24,192.168.50.0/24
```

### Better API-aligned interface

```bash
./bin/customize-image.sh \
  --input ./pi-gen/deploy/sensos.img \
  --output ./artifacts/sensos-device-001.img \
  --config ./device-001.image-config.json
```

The second form is better long term. The API can generate the JSON directly, and the CLI stays thin.

## Suggested Runtime Behavior for `config-network`

On first boot:

1. If configured, import or create a Wi-Fi client connection.
2. If configured, install a WireGuard connection or config.
3. Attempt to bring up the intended network path.
4. Decide what to do with the hotspot:
   - leave enabled until private connectivity succeeds, then disable it
   - or disable it immediately if Wi-Fi + WireGuard are mandatory and known-good

The safer default is to keep the hotspot as a fallback until private connectivity is confirmed. Otherwise a bad Wi-Fi or WireGuard config can strand the device.

## Suggested Failure Policy

The first-boot configurator should fail soft for network setup:

- keep hotspot available if `config-network` fails
- write a status file such as `/sensos/config/image-config.status.json`
- never leave the machine in a state where neither hotspot nor intended client connectivity works

That gives a recovery path without exposing the API port publicly.

## Artifact Model

The customized `.img` file should be treated as a sensitive artifact because it may contain:

- Wi-Fi credentials
- WireGuard keys
- API password or related secrets
- device identity

Operationally:

- store under a dedicated `artifacts/` directory
- keep it out of git
- prefer short retention on the server
- consider producing a sidecar metadata file with only non-secret fields

## API Sketch

This repo does not need to own the API, but the image facility should be easy to wrap with one.

Example shape:

```http
POST /images
Content-Type: application/json
```

```json
{
  "base_image": "sensos-2026-04-02.img",
  "customization": {
    "device_id": "sensos-001",
    "config_network": {
      "mode": "wifi",
      "wifi": {
        "ssid": "field-net",
        "psk": "example-password",
        "country": "US"
      },
      "wireguard": {
        "enabled": true,
        "endpoint": "vpn.example.net:51820",
        "address": "10.20.0.14/32"
      }
    }
  }
}
```

Possible response:

```json
{
  "image_id": "img_01",
  "status": "ready",
  "download_path": "/images/img_01/download"
}
```

## Implementation Order

Recommended order:

1. Add first-boot image-config service and script to the base image.
2. Implement only payload ingestion plus `config-network`.
3. Add `bin/customize-image.sh` that injects the payload into an existing image.
4. Add artifact naming and cleanup conventions.
5. Only then expand to broader pre-burn configuration.

This keeps the risky parts narrow and makes the server-side API straightforward.

## Open Questions

- Should hotspot remain enabled permanently as an out-of-band recovery path, or only until private connectivity is confirmed?
- Should WireGuard be configured directly through NetworkManager or via standalone files and systemd units?
- Is `config-network` expected to support Ethernet, Wi-Fi, and cellular later, or just Wi-Fi first?
- Should the customized image be reproducible from a saved JSON payload plus a base image checksum?
- Does the API need synchronous image generation, or is a job queue model acceptable?

## Recommendation

The cleanest architecture is:

- keep `pi-gen` for reusable base images
- add a generic first-boot config applicator inside the image
- add an offline image customizer that injects a declarative payload
- keep image customization separate from burning

That gives you a path from today's hotspot-focused build to a broader "preconfigured image artifact" system without locking the project into brittle direct filesystem surgery for every future setting.
