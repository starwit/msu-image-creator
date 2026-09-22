# MSU Image Creator

This software creates an Ubuntu server base image, to be used on MSU embedded devices that are developed in cooperation with [Gerhartl](https://www.gerhartl.de/en/homepage/)

## How to use repo

Bash script [create_autoinstall_image.sh](create_autoinstall_image.sh) is downloading Ubuntu server 24 and do all necessary steps, to create a new autoinstall ISO image. Main configuration of your image is done via file [user-data](user-data) and environment variables prefixed with `MSU_` (see [env.sh.template](env.sh.template)):

| Variable | Required | Description |
|---|---|---|
| `MSU_FUNCTION_USER_NAME` | yes | name of main user to be created |
| `MSU_HOSTNAME` | yes | hostname of machine |
| `MSU_TAILSCALE_TOKEN` | yes | Tailscale auth key used to join the tailnet |
| `MSU_FUNCTION_USER_PASSWORD` | no | password of main user; generated upon image creation if not set |

The easiest way to set them is to copy env.sh.template to env.sh and fill in your values; the script sources env.sh if it exists. It is optional though, so you can also set the variables in any other way (e.g. export them in your shell or CI pipeline). The script aborts if any required variable is not set.

After creation script ran, an ISO file is sitting in folder _autoinstall_image_. This you can then put on an USB stick and autoinstall with that any computer.

To test the ISO in a KVM/Qemu virtual machine, run this from the repo root:

```bash
virt-install -n autoinstall-test \
--os-variant=ubuntu24.04 \
--memory=2048 --vcpus=2 \
--disk size=15 \
--cdrom "$PWD/autoinstall_image/ubuntu-26.04.1-server-autoinstall.iso"
```

The disk is created automatically in libvirt's default storage pool. If libvirt can't read the ISO from your home directory, virt-install offers to fix the permissions for you. To remove the test VM and its disk afterwards:

```bash
virsh destroy autoinstall-test; virsh undefine autoinstall-test --remove-all-storage
```

## How it works
This section shall explain main steps, how disk image is created. Look here if you want to modify image creation script.

0. Install xorriso and mkpasswd with sudo apt update && sudo apt install xorriso whois
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