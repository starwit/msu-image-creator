# Ubuntu Auto-Install Documentation

If you are in need to auto-install Ubuntu to a device/VM with pre-defined config & packages - this repo explains, how to do that.

## How to use repo

Bash script [create_autoinstall_image.sh](create_autoinstall_image.sh) is downloading Ubuntu server 24 and do all necessary steps, to create a new autoinstall ISO image. Main configuration of your image is done via file [user-data](user-data)

## How it works

Boot image creation is done by the following steps:

0. Install xorriso with sudo apt update && sudo apt install xorriso
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