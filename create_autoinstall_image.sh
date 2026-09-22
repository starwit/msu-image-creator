#!/bin/bash

# env.sh is optional, variables can also be set in the environment directly
if [ -f ./env.sh ]; then
    source ./env.sh
fi

# fail if any required variable is not set
missing=0
for var in MSU_FUNCTION_USER_NAME MSU_HOSTNAME MSU_TAILSCALE_TOKEN TARGET_ISO_FILE; do
    if [ -z "${!var}" ]; then
        echo "required variable $var is not set" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "Please check if env.sh exists and is configured (or the env vars are set through other means)"
    echo "TARGET_ISO_FILE is set by the Makefile, run 'make image' instead of calling the script directly"
    exit 1
fi

# fail if any required tool is not installed
for cmd in mkpasswd xorriso wget; do
    if ! command -v "$cmd" > /dev/null; then
        echo "required tool $cmd is not installed (mkpasswd is part of package whois)" >&2
        exit 1
    fi
done

# test if password variable is set via env var
if [ -z "${MSU_FUNCTION_USER_PASSWORD}" ]; then
    echo "no user password set, generate one"
    MSU_FUNCTION_USER_PASSWORD=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 18 ; echo ''`
fi


DOWNLOAD_DIR="download-cache"
TARGET_DIR="autoinstall_image"

ISO_FILE="ubuntu-26.04.1-live-server-amd64.iso"

# hash password
MSU_FUNCTION_USER_PASSWORD_HASH=$(printf '%s' "$MSU_FUNCTION_USER_PASSWORD" | mkpasswd -m sha-256 -s)
if [ $? -ne 0 ] || [ -z "$MSU_FUNCTION_USER_PASSWORD_HASH" ]; then
    echo "failed to hash user password" >&2
    exit 1
fi
escaped_hash=$(printf '%s\n' "$MSU_FUNCTION_USER_PASSWORD_HASH" | sed -e 's/[\/&]/\\&/g')
echo "*****************************************"
echo $escaped_hash

# Download ISO if not already present
ISO_URL="https://mirror.wtnet.de/ubuntu-releases/26.04.1/ubuntu-26.04.1-live-server-amd64.iso"

mkdir -p "$DOWNLOAD_DIR"
if [ ! -f "$DOWNLOAD_DIR/$ISO_FILE" ]; then
    echo "Downloading Ubuntu ISO..."
    wget -O "$DOWNLOAD_DIR/$ISO_FILE" "$ISO_URL"
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# remove old files (extracted ISO content is read-only, make it writable first)
[ -d ./source-files ] && chmod -R u+w ./source-files
rm -rf ./source-files
rm -f ./$TARGET_ISO_FILE

mkdir -p ./source-files/bootpart

# extract original ISO
xorriso -osirrox on -indev ../$DOWNLOAD_DIR/$ISO_FILE --extract_boot_images ./source-files/bootpart -extract / ./source-files

# xorriso keeps the read-only permissions of the ISO, make the extracted files writable
chmod -R u+w ./source-files

mkdir -p source-files/nocloud
cp ../user-data source-files/nocloud/user-data

# replacing placeholders
echo "Setting hostname"
sed -i -e "s/###HOSTNAME###/${MSU_HOSTNAME}/g" source-files/nocloud/user-data
echo "Setting function user name"
sed -i -e "s/###USER_NAME###/${MSU_FUNCTION_USER_NAME}/g" source-files/nocloud/user-data
echo "Setting function user password hash"
sed -i -e "s/###USER_PASSWORD_HASH###/${escaped_hash}/g" source-files/nocloud/user-data

touch source-files/nocloud/meta-data
echo "${MSU_HOSTNAME}" > source-files/nocloud/hostname.txt
echo "${MSU_TAILSCALE_TOKEN}" > source-files/nocloud/tailscale.txt

cp ../grub.cfg source-files/boot/grub/grub.cfg

xorriso -as mkisofs -r -V "ubuntu-26-autoinstall" \
  -J -boot-load-size 4 -boot-info-table -input-charset utf-8 \
  -b bootpart/eltorito_img1_bios.img \
     -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e bootpart/eltorito_img2_uefi.img \
     -no-emul-boot -isohybrid-gpt-basdat \
  -isohybrid-mbr source-files/bootpart/mbr_code_grub2.img \
  -o "$TARGET_ISO_FILE" source-files

echo "*****************************************"
echo "Function user password: $MSU_FUNCTION_USER_PASSWORD"
echo "Please note this password, as it will not shown again and there is no other way to login into machine."
echo "*****************************************"