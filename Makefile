VM_NAME     ?= autoinstall-test
LIBVIRT_URI ?= qemu:///system

# most recently built ISO (symlink created by create_autoinstall_image.sh)
ISO := $(CURDIR)/autoinstall_image/latest.iso

.PHONY: image vm-start vm-clean clean

# always rebuild, as env vars may have changed
image:
	./create_autoinstall_image.sh

# only build the ISO if it does not exist yet
$(ISO):
	$(MAKE) image

vm-start: $(ISO)
	@command -v virt-viewer > /dev/null || echo "NOTE: virt-viewer is not installed, so the VM window won't open automatically. Install it (sudo apt install virt-viewer) or open the VM in virt-manager."
	virt-install --connect $(LIBVIRT_URI) -n $(VM_NAME) \
		--os-variant=ubuntu24.04 \
		--memory=4096 --vcpus=2 \
		--disk size=60 \
		--cdrom "$(ISO)"

vm-clean:
	-virsh --connect $(LIBVIRT_URI) destroy $(VM_NAME)
	virsh --connect $(LIBVIRT_URI) undefine $(VM_NAME) --remove-all-storage

# removes generated files, keeps the downloaded base ISO in download-cache
# (extracted ISO content is read-only, make it writable first)
clean:
	-chmod -R u+w autoinstall_image
	rm -rf autoinstall_image
