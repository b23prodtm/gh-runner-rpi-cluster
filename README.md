# gh-runner-rpi-cluster

A self-hosted GitHub Actions runner, containerized and deployed via [balena Cloud](https://www.balena.io/cloud), designed to scale across a small fleet of Raspberry Pi 4/5 boards (ARM64, 4GB+ RAM recommended).

## Why this project exists

GitHub-hosted runners build ARM targets under QEMU emulation, which is slow and occasionally **crashes or times out on long-running ARM builds**. The goal here is to offload those builds onto real ARM hardware — a small Raspberry Pi cluster — so long/heavy builds finish reliably instead of dying on a remote emulated runner.

Each device registers itself as an **ephemeral** runner: it pulls a fresh registration token from the GitHub API on boot, runs one job, deregisters, and repeats. This avoids stale/offline runners piling up after reboots or balenaOS updates, which are common on a fleet.

## Multi-arch template layout

This project does not commit a static `Dockerfile` or `docker-compose.yml`. Instead it ships **templates** rendered per architecture:

```
common.env                 # variables shared by every architecture
aarch64.env                # RPi 4/5, 64-bit balenaOS (primary target)
armhf.env                  # RPi 2/3, 32-bit balenaOS
x86_64.env                 # x86_64 (e.g. Intel NUC), optional dev/extra capacity
docker-compose.template    # -> rendered per arch
gh-runner/
  Dockerfile.template     # -> rendered per arch
  entrypoint.sh
build/                    # rendered output, one self-contained dir per arch
  aarch64/
    docker-compose.yml
    common.env
    aarch64.env
    gh-runner/{Dockerfile, entrypoint.sh}
  armhf/
    docker-compose.yml
    common.env
    armhf.env
    gh-runner/{Dockerfile, entrypoint.sh}
  x86_64/
    docker-compose.yml
    common.env
    x86_64.env
    gh-runner/{Dockerfile, entrypoint.sh}
scripts/
  update_templates.sh     # fallback renderer if balena-cloud-apps isn't installed
```

Each `$(BALENA_ARCH).env` file defines, at minimum:

| Variable | Meaning |
|---|---|
| `BALENA_ARCH` | balena architecture slug (`aarch64`, `armhf`, `x86_64`) |
| `PLATFORM` | Docker platform string for `--platform` / buildx (`linux/arm64`, ...) |
| `PRIMARY_HUB` | Base image registry/repo — standard DockerHub `ubuntu`, **not** a `balenalib/*` image |
| `PRIMARY_TAG` | Base image tag (`22.04`) |
| `RUNNER_ARCH` | Suffix GitHub uses for the runner tarball (`arm64`, `arm`, `x64`) |

`common.env` holds everything that doesn't vary by architecture (currently `RUNNER_VERSION`, `RUNNER_LABELS_BASE`).

Templates use `%%TOKEN%%` placeholders (e.g. `%%BALENA_ARCH%%`, `%%PLATFORM%%`, `%%PRIMARY_HUB%%`) so the same two `.template` files produce a correct `Dockerfile`/`docker-compose.yml` for any target board.

The rendered output — `build/<arch>/docker-compose.yml` and `build/<arch>/gh-runner/Dockerfile` for each of the 3 archs — **is committed to git**. It is not gitignored. If you edit the `.template` files or an `<arch>.env` file, re-run the render step and commit the updated `build/` output alongside the templates so they stay in sync.

### Rendering the templates

`update_templates` only takes a `project_root` — no target argument. Every `<arch>.env` file found next to `common.env` is processed **in sequence, in the same run** (currently `aarch64`, `armhf`, `x86_64`). `balena_deploy` keeps its `<project_root> [options] [target]` signature — call it without a target to deploy all rendered archs, or with one (e.g. `balena_deploy . aarch64`) to push a single arch.

If you have the `balena-cloud-apps` package installed, use its own tooling as the source of truth (binaries typically at `/opt/local/bin/`):

```bash
update_templates .
balena_deploy .
```

If it isn't on your PATH, `scripts/update_templates.sh` is a plain-bash fallback with the same contract and invocation shape (project_root only, all archs rendered in one pass, output under `build/<arch>/`):

```bash
./scripts/update_templates.sh .
balena push <your-app-name>
```

### Why the base image changed

Earlier iterations of this project used `balenalib/raspberrypi4-64-ubuntu`. That family of images is deprecated in favor of building multi-arch straight from the **standard DockerHub `ubuntu` image** with `--platform` / buildx, which is what `PRIMARY_HUB` + `PRIMARY_TAG` + `PLATFORM` now drive.

## Requirements

- A balena Cloud account and an application/fleet targeting **Raspberry Pi 4 (64-bit)** or **Raspberry Pi 5**.
- One or more Raspberry Pi 4/5 boards with **at least 4GB RAM**.
- A fast SD card (A2-rated) or, preferably, boot/data from a USB3 SSD.
- A GitHub [fine-grained personal access token](https://github.com/settings/tokens?type=beta) with **Administration: Read & write** permission on the target repository.

## Deployment

1. Render the templates for your target arch (see above).
2. Push this project to a GitHub repository.
3. Create a balena application, add your device(s), and flash balenaOS.
4. Push to balena:
   ```bash
   balena_deploy . aarch64
   # or: balena push <your-app-name>
   ```
5. In the balena dashboard, set as **Fleet Environment Variables**:

   | Variable | Description |
   |---|---|
   | `GH_OWNER` | GitHub user or organization |
   | `GH_REPO` | Repository name the runner will serve |
   | `GH_PAT` | Fine-grained PAT with `administration:write` |
   | `RUNNER_LABELS` | Optional, defaults to `self-hosted,balena,<arch>` |

6. Target the runner from a workflow:
   ```yaml
   jobs:
     build:
       runs-on: [self-hosted, aarch64]
   ```

## Notes on Docker-in-Docker

The compose template uses the `io.balena.features.balena-socket` label plus `privileged: true` to expose the host's balenaEngine socket inside the container, rather than running full Docker-in-Docker — lighter on Raspberry Pi hardware and the standard balena pattern for build-capable containers.

## Optional USB storage for `runner-work`

Repeated `_work` I/O wears out SD cards. The compose template now includes a `balena-storage` sidecar, adapted from the one used in [b23prodtm/acake2php](https://github.com/b23prodtm/acake2php), that redirects the `runner-work` named volume onto a USB drive mounted under `/mnt/external-drives`.

```yaml
balena-storage:
  image: betothreeprod/balena-storage:latest
  privileged: true
  env_file:
    - common.env
    - %%BALENA_ARCH%%.env
  volumes:
    - runner-work:/mnt/external-drives
```

- `privileged: true` is required for the service to detect and mount external media.
- `env_file` pulls in `common.env` and the arch-specific `<arch>.env`, so `scripts/update_templates.sh` now copies both files into each `build/<arch>/` directory next to the rendered `docker-compose.yml`.
- `gh-runner` depends on `balena-storage`, so the mount attempt happens before the runner starts writing to `/data/_work`.

Three things from the original acake2php service are still intentionally omitted here because they do not apply to this repository:
- `build.x-bake` / `context: balena-storage` / `dockerfile: Dockerfile.%%BALENA_ARCH%%`, because this repository currently pulls the published `betothreeprod/balena-storage:latest` image instead of building it locally.
- `networks: [cake]`, because that network is specific to acake2php.
- The commented-out `backup-db.sh` healthcheck, because it is tied to acake2php's database backup workflow.

## Building a Raspberry Pi cluster (4/5, 4GB+ RAM)

If you're scaling this to multiple boards behind a D-Link router:

### 1. Find the Raspberry Pis on your network

```bash
sudo nmap -sn 192.168.0.0/24
sudo arp-scan --localnet | grep -i "raspberry\|b8:27:eb\|dc:a6:32\|e4:5f:01"
```
Adjust the subnet to match your D-Link router's DHCP range.

### 2. Reserve static IPs on the D-Link router

In the D-Link admin UI (usually `http://192.168.0.1`), go to **Network Settings → DHCP Reservation** and bind each Pi's MAC address to a fixed IP.

### 3. Wire, don't rely solely on Wi-Fi, if possible

Ethernet is more reliable for CI workloads — a Wi-Fi drop mid-build kills a runner mid-job.

### 4. Scale via balena fleets, not individual devices

Once 2+ Pis are in the same balena application, a single `balena_deploy . aarch64` (or `balena push`) updates the whole fleet. Use per-device (not fleet) variables for `RUNNER_LABELS` if you want to target specific boards for specific jobs.

## Security notes

- `GH_PAT` should be scoped to the single repository it serves.
- Runners are ephemeral and self-deregister; `RUNNER_NAME` is unique per device automatically.
- Because jobs run with Docker socket access, only use self-hosted runners like this on **private repositories**, or repos where every contributor who can open a PR is fully trusted.

## Reusing this as a template for future balena projects

This repository is meant to double as the reference layout for future balena Cloud projects built off it. When starting a new one:

- Use the `balena-cloud-apps` package (`update_templates`, `balena_deploy`) rather than hand-writing per-arch Dockerfiles/compose files.
- Keep the same multi-arch template structure: `common.env` + one `$(BALENA_ARCH).env` per target board, `Dockerfile.template` / `docker-compose.template` with `%%BALENA_ARCH%%` / `%%PLATFORM%%` / `%%PRIMARY_HUB%%` / `%%PRIMARY_TAG%%` placeholders, base images from the standard DockerHub registry rather than deprecated `balenalib/*` images.
- Following this format keeps deployment consistent across projects and makes it straightforward to select self-hosted runners (as done here) for any future project that needs native-ARM builds instead of emulated GitHub-hosted ones.
