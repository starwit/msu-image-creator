# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-11-09

Initial release.

### Added

- Build of an Ubuntu Server 26.04.1 autoinstall ISO (`make image`), configured through
  `env.sh` or environment variables (hostname, user, password, Tailscale key, SAE and
  K3s versions).
- First boot setup on the device: sets the hostname, joins Tailscale, creates the
  `kube` group, adds a dummy network interface for K3s, installs K3s (node name pinned
  to `local`), installs the Intel GPU device plugin with GPU sharing and pre-downloads
  the application images.
- Image list generated from the SAE helm chart (`sae-components.txt`) plus
  `extra-images.txt`, with download progress on the console.
- Failure reporting: the failed step is shown on the console and in front of the login
  prompt.
- Test VM targets `make vm-start` and `make vm-clean`.
- Versioning: `VERSION` file, this changelog, version in the ISO file name and in the
  first boot setup output, GitHub release workflow.
