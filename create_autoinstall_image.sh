#!/bin/bash

# env.sh is optional, variables can also be set in the environment directly
if [ -f ./env.sh ]; then
    source ./env.sh
fi

# fail if any required variable is not set
missing=0
for var in MSU_FUNCTION_USER_NAME MSU_HOSTNAME MSU_TAILSCALE_TOKEN MSU_SAE_VERSION; do
    if [ -z "${!var}" ]; then
        echo "required variable $var is not set" >&2
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "Please check if env.sh exists and is configured (or the env vars are set through other means)"
    exit 1
fi

# version of this repo (single source of truth: file VERSION), goes into the ISO name and onto the device
MSU_VERSION=$(tr -d '[:space:]' < VERSION 2>/dev/null)
if [ -z "$MSU_VERSION" ]; then
    echo "could not read version from file VERSION (run the script from the repository root)" >&2
    exit 1
fi
MSU_BUILD_DATE=$(date +%F)
TARGET_ISO_FILE="msu-autoinstall-${MSU_VERSION}-${MSU_HOSTNAME}-${MSU_BUILD_DATE}.iso"
echo "Building MSU image version ${MSU_VERSION} for host ${MSU_HOSTNAME}"

# fail if any required tool is not installed
for cmd in mkpasswd xorriso wget helm; do
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

# K3s release (e.g. v1.34.1+k3s1) or channel to install
MSU_K3S_VERSION="${MSU_K3S_VERSION:-stable}"

# generate list of images to pre-download onto the device
# see https://github.com/starwit/starwit-awareness-engine/tree/main/helm#image-provisioning
echo "Generating image list for SAE helm chart version ${MSU_SAE_VERSION}"
sae_set_flags=$(sed -E '/^\s*(#|$)/d; s/^\s*(\S+)\s+(\S+).*/--set \1.enabled=\2/' sae-components.txt)
# shellcheck disable=SC2086 # flags need to be word-split
if ! sae_manifests=$(helm template sae oci://registry-1.docker.io/starwitorg/sae --version "$MSU_SAE_VERSION" $sae_set_flags); then
    echo "failed to render SAE helm chart version ${MSU_SAE_VERSION}, see helm error above (does the version exist, are the components in sae-components.txt valid?)" >&2
    exit 1
fi
images=$(
    {
        printf '%s\n' "$sae_manifests" | grep 'image:' \
            | sed -E 's/^.*image: *"?([^"]+)"?.*$/\1/; /^[^/]+$/s|^|docker.io/library/|; /^(localhost|[^/]*[.:][^/]*)\//!s|^|docker.io/|'
        sed -E '/^\s*(#|$)/d; s/^\s+//; s/\s+$//' extra-images.txt
    } | sort -u
)
if [ -z "$images" ]; then
    echo "WARNING: image list is empty, no images will be pre-downloaded"
else
    echo "Images to pre-download:"
    printf '%s\n' "$images" | sed 's/^/  /'
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
{
    printf 'MSU_VERSION=%q\n' "$MSU_VERSION"
    printf 'MSU_BUILD_DATE=%q\n' "$MSU_BUILD_DATE"
    printf 'K3S_VERSION=%q\n' "$MSU_K3S_VERSION"
} > source-files/nocloud/setup.env
printf '%s\n' "$images" > source-files/nocloud/images.txt
cp ../first-boot-setup.sh source-files/nocloud/first-boot-setup.sh

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

# stable name for the most recently built ISO (used by make vm-start)
ln -sfn "$TARGET_ISO_FILE" latest.iso

echo "*****************************************"
echo "Created ISO: ${TARGET_DIR}/${TARGET_ISO_FILE} (also available as ${TARGET_DIR}/latest.iso)"
echo "*****************************************"
echo "Function user password: $MSU_FUNCTION_USER_PASSWORD"
echo "Please note this password, as it will not shown again and there is no other way to login into machine."
echo "*****************************************"