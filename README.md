# MSU Image Creator

This software creates an Ubuntu server base image, to be used on MSU embedded devices that are developed in cooperation with [Gerhartl](https://www.gerhartl.de/en/homepage/)

## How to use repo

Bash script [create_autoinstall_image.sh](create_autoinstall_image.sh) is downloading Ubuntu server 24 and do all necessary steps, to create a new autoinstall ISO image. Main configuration of your image is done via file [user-data](user-data) and [env.sh](env.sh). In env.sh you can define name of main user to be created and hostname of machine. Note that password is generated upon image creation.

After creation script ran, an ISO file is sitting in folder _autoinstall_image_. This you can then put on an USB stick and autoinstall with that any computer.

If you want to test ISO with a virtual machine, you can use KVM/Qemu to do so. Please note, that you need to copy ISO to the configured storage pools in your configuration.
```bash
virsh pool-list
```

The following command shows how to start a VM and using created ISO to auto-install Ubuntu:

```bash
virt-install -n auto-install-test \
--description "VM to test Ubuntu auto install" \
--os-type=Linux --os-variant=ubuntu24.04 \
--ram=2048 --vcpus=2 \
--disk path=/path/to/diskfolder/autoinstall-test.img,bus=virtio,size=15 \
--graphics spice \
--cdrom /path/to/imagefolder/ubuntu-24.04-server-autoinstall.iso 
```

## How it works
This section shall explain main steps, how disk image is created. Look here if you want to modify image creation script.

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

# License
Code is published using AGPLv3 license. License agreement can be found [here](LICENSE)