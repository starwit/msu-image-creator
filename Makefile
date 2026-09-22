VM_NAME     ?= autoinstall-test
LIBVIRT_URI ?= qemu:///system

export TARGET_ISO_FILE := ubuntu-26.04.1-server-autoinstall.iso
ISO := $(CURDIR)/autoinstall_image/$(TARGET_ISO_FILE)

.PHONY: image start-vm cleanup-vm clean

# always rebuild, as env vars may have changed
image:
	./create_autoinstall_image.sh

# only build the ISO if it does not exist yet
$(ISO):
	$(MAKE) image

start-vm: $(ISO)
	virt-install --connect $(LIBVIRT_URI) -n $(VM_NAME) \
		--os-variant=ubuntu24.04 \
		--memory=2048 --vcpus=2 \
		--disk size=15 \
		--cdrom "$(ISO)"

cleanup-vm:
	-virsh --connect $(LIBVIRT_URI) destroy $(VM_NAME)
	virsh --connect $(LIBVIRT_URI) undefine $(VM_NAME) --remove-all-storage

# removes generated files, keeps the downloaded base ISO in download-cache
# (extracted ISO content is read-only, make it writable first)
clean:
	-chmod -R u+w autoinstall_image
	rm -rf autoinstall_image
