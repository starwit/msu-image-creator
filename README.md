# MSU Image Creator

This software creates an Ubuntu server base image, to be used on MSU embedded devices that are developed in cooperation with [Gerhartl](https://www.gerhartl.de/en/homepage/)

## Creating an image

Script [create_autoinstall_image.sh](create_autoinstall_image.sh) downloads Ubuntu Server 26.04 and builds an autoinstall ISO from it. The hostname, user and Tailscale key are built into the ISO, so you create one ISO per device.

1. **Install the build tools.** You need `xorriso`, `mkpasswd` (package _whois_), `wget` and [helm](https://helm.sh/docs/intro/install/):
    ```bash
    sudo apt update && sudo apt install xorriso whois wget
    ```
2. **Set the device settings.** Copy the template and fill in your values (see [Environment variables](#environment-variables)):
    ```bash
    cp env.sh.template env.sh
    vim env.sh
    ```
3. **Choose the images to pre-download** (optional). Enable the SAE components you need in [sae-components.txt](sae-components.txt), and add any further images to [extra-images.txt](extra-images.txt) (see [Pre-downloaded images](#pre-downloaded-images)).
4. **Build the ISO:**
    ```bash
    make image
    ```
    The build prints the list of images that will be pre-downloaded, so you can check it. It stops with an error if a required variable is missing, a tool isn't installed or the SAE chart can't be rendered.
5. **Note the password.** If `MSU_FUNCTION_USER_PASSWORD` isn't set, a password is generated and printed at the end of the build. It is not shown again, and there is no other way to log into the machine.
6. **Write the ISO to a USB stick.** The ISO is in `autoinstall_image/` (name set by `TARGET_ISO_FILE` in the [Makefile](Makefile)). Write it with a tool of your choice. On Linux, for example (replace `/dev/sdX` with your USB stick, all data on it is lost):
    ```bash
    sudo dd if=autoinstall_image/ubuntu-26.04.1-server-autoinstall.iso of=/dev/sdX bs=4M status=progress conv=fsync
    ```
7. **Install the device.** Boot the device from the USB stick. The entry "Start Ubuntu Autoinstall" is selected automatically after 10 seconds. The installation runs without any input. After the reboot, the first boot setup runs (see [What happens on the device](#what-happens-on-the-device)) and ends with `SETUP SUCCESSFUL` or `SETUP FAILED`.

`make image` always rebuilds the ISO and overwrites the previous one. The Ubuntu base ISO is cached in `download-cache/`, so it is only downloaded once. To remove all generated files (the download cache is kept), run `make clean`.

## Customization

### Environment variables

These are set in `env.sh` (see [env.sh.template](env.sh.template)). The build script sources `env.sh` if it exists. You can also set the variables any other way, e.g. export them in your shell or CI pipeline.

| Variable | Required | Description |
|---|---|---|
| `MSU_FUNCTION_USER_NAME` | yes | name of the main user to be created |
| `MSU_HOSTNAME` | yes | hostname of the machine |
| `MSU_TAILSCALE_TOKEN` | yes | Tailscale auth key used to join the tailnet |
| `MSU_SAE_VERSION` | yes | version of the SAE helm chart (e.g. `13.2.2`), used to generate the list of images to pre-download |
| `MSU_FUNCTION_USER_PASSWORD` | no | password of the main user; generated during the build if not set |
| `MSU_K3S_VERSION` | no | K3s release (e.g. `v1.34.1+k3s1`) or channel (e.g. `stable`, `latest`) to install; defaults to `stable` |

### Pre-downloaded images

The list of images is generated during the build by rendering the SAE helm chart in version `MSU_SAE_VERSION` (see [SAE image provisioning](https://github.com/starwit/starwit-awareness-engine/tree/main/helm#image-provisioning)):

- [sae-components.txt](sae-components.txt) selects which SAE components are enabled (`true`/`false` per component). All components are disabled by default, so test installations are quick. In that case only the images the chart always deploys (Valkey, monitoring) are pulled.
- [extra-images.txt](extra-images.txt) lists further images that are not part of the chart, one per line, e.g. custom object detector weights (`docker.io/starwitorg/sae-object-detector-weights:<tag>`).

Images are pulled on the device during the first boot setup, so the ISO size doesn't change.

### Other settings

| What | Where |
|---|---|
| Ubuntu installation (disk layout, keyboard, locale, timezone, packages, final message) | [user-data](user-data) |
| Intel GPU device plugin version (`INTEL_DEVICE_PLUGINS_VERSION`), dummy interface IP for K3s (`DUMMY_IP`), K3s configuration | [first-boot-setup.sh](first-boot-setup.sh) |
| Ubuntu base ISO (`ISO_FILE`, `ISO_URL`) | [create_autoinstall_image.sh](create_autoinstall_image.sh) |
| Name of the created ISO (`TARGET_ISO_FILE`), test VM settings | [Makefile](Makefile) |
| Boot menu and timeout | [grub.cfg](grub.cfg) |

## Testing in a VM

Testing requires libvirt and `virt-install`, plus `virt-viewer` to open the VM window automatically:

```bash
sudo apt install virt-manager virt-viewer
```

To test the ISO in a KVM/Qemu virtual machine (the image is created first if it doesn't exist yet):

```bash
make vm-start
```

The VM disk is created automatically in libvirt's default storage pool. If libvirt can't read the ISO from your home directory, virt-install offers to fix the permissions for you. To remove the test VM and its disk afterwards:

```bash
make vm-clean
```

VM name and libvirt connection can be overridden, e.g. `make vm-start VM_NAME=my-test LIBVIRT_URI=qemu:///session`.

By default the VM commands connect to the system libvirt instance (`qemu:///system`). If your user is not in the `libvirt` group, you may need to run them with sudo, e.g. `sudo make vm-start`. In that case, build the image beforehand with `make image` (without sudo), so the generated files aren't owned by root.

If the VM window doesn't open (`virt-viewer` not installed, or no display available, e.g. because sudo dropped the `DISPLAY` variable), the installation still runs. Open the VM in virt-manager, or connect with `virt-viewer --connect qemu:///system autoinstall-test`.

Note that the device joins your tailnet during the test as well. Remove the test machine from Tailscale afterwards.

## What happens on the device

After Ubuntu is installed and the machine has rebooted, cloud-init runs [first-boot-setup.sh](first-boot-setup.sh) once. It

1. sets the hostname and connects the device to Tailscale,
2. creates the group `kube` and adds the main user to it (members can use `kubectl` without sudo),
3. creates a dummy network interface `dummy0` (`203.0.113.1`) as a stable primary interface for K3s,
4. writes the K3s configuration (Tailscale hostname and IP are added as TLS SANs) and installs K3s,
5. installs the Intel GPU device plugin and enables GPU sharing,
6. pre-downloads the application images.

The script stops at the first error. It then prints `SETUP FAILED` with the failed step and command on the console, shows the same message in front of the login prompt and `cloud-init status` reports an error. The full output is in `/var/log/cloud-init-output.log`. If everything worked, it prints `SETUP SUCCESSFUL`.

## How it works
This section shall explain main steps, how disk image is created. Look here if you want to modify image creation script.

0. Install xorriso and mkpasswd with sudo apt update && sudo apt install xorriso whois (and helm, see above)
1. Download base image (e.g. [Ubuntu server](https://ubuntu.com/download/server))
2. Extract ISO file to a folder on your disk
    ```bash
    # extract original ISO
    xorriso -osirrox on -indev ~/Downloads/ISO/ubuntu-24.04.2-live-server-amd64.iso --extract_boot_images source-files/bootpart -extract / source-files
    ```
3. Add auto install configuration to folder _nocloud_ into extracted ISO
4. Copy file [user-data](user-data) to folder _nocloud_
5. Create empty file meta-data in folder _nocloud_
6. Add option to grub.cfg (boot/grub/grub.cfg) like so:
    ```bash
    menuentry "Start Ubuntu Autoinstall" {
        set gfxpayload=keep
        linux /casper/vmlinuz quiet autoinstall ds=nocloud\;s=/cdrom/nocloud/ --- 
        initrd /casper/initrd
    }
    ```
7. Create new ISO image
    ```bash
    xorriso -as mkisofs -r -V "ubuntu-autoinstall" -J -boot-load-size 4 -boot-info-table -input-charset utf-8 -eltorito-alt-boot -b bootpart/eltorito_img1_bios.img -no-emul-boot -o ../pod_autoinstall.iso .
    ```

8. Test with VM

# License
Code is published using AGPLv3 license. License agreement can be found [here](LICENSE)