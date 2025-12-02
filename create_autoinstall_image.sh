#!/bin/bash

source ./env.sh

FUNCTION_USER_PASSWORD=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 18 ; echo ''`

TARGET_DIR="autoinstall_image"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

ISO_FILE="ubuntu-24.04-live-server-amd64.iso"
TARGET_ISO_FILE="ubuntu-24.04-server-autoinstall.iso"

# hash password
FUNCTION_USER_PASSWORD_HASH=$(mkpasswd -m sha-256 -s "$FUNCTION_USER_PASSWORD")
escaped_hash=$(printf '%s\n' "$FUNCTION_USER_PASSWORD_HASH" | sed -e 's/[\/&]/\\&/g')
echo "*****************************************"
echo $escaped_hash

mkdir -p "source-files"
mkdir -p "download"
cd ./download

# Download ISO if not already present
ISO_URL="https://mirror.wtnet.de/ubuntu-releases/24.04.3/ubuntu-24.04.3-live-server-amd64.iso"

if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading Ubuntu ISO..."
    wget -O "$ISO_FILE" "$ISO_URL"
fi

cd ..

echo $PWD

# remove old files
rm -rf ./source-files
rm -rf ./source-files/$TARGET_ISO_FILE

mkdir -p ./source-files/bootpart

# extract original ISO
xorriso -osirrox on -indev ./download/$ISO_FILE --extract_boot_images ./source-files/bootpart -extract / ./source-files

mkdir -p source-files/nocloud
cp ../user-data source-files/nocloud/user-data

# replacing placeholders
echo "Setting hostname"
sed -i -e "s/###HOSTNAME###/${HOSTNAME}/g" source-files/nocloud/user-data
echo "Setting function user name"
sed -i -e "s/###USER_NAME###/${FUNCTION_USER_NAME}/g" source-files/nocloud/user-data
echo "Setting function user password hash"
sed -i -e "s/###USER_PASSWORD_HASH###/${escaped_hash}/g" source-files/nocloud/user-data

touch source-files/nocloud/meta-data

chmod u+w source-files/boot/grub/grub.cfg
cp ../grub.cfg source-files/boot/grub/grub.cfg
chmod u-w source-files/boot/grub/grub.cfg

xorriso -as mkisofs -r -V "ubuntu-24-autoinstall" \
  -J -boot-load-size 4 -boot-info-table -input-charset utf-8 \
  -b bootpart/eltorito_img1_bios.img \
     -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e bootpart/eltorito_img2_uefi.img \
     -no-emul-boot -isohybrid-gpt-basdat \
  -isohybrid-mbr source-files/bootpart/mbr_code_grub2.img \
  -o "$TARGET_ISO_FILE" source-files

echo "*****************************************"
echo "Function user password: $FUNCTION_USER_PASSWORD"
echo "Please not this password, as it will not shown again and there is no other way to login into machine."
echo "*****************************************"