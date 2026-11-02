#!/bin/bash
# First boot setup of an MSU device, run as root by cloud-init (runcmd).
# Joins Tailscale, installs K3s and pre-pulls the application images.
# Stops at the first failing step and reports it on the console and at the login prompt.
#
# usage: first-boot-setup.sh <function user name>

set -Eeuo pipefail

USER_NAME="${1:?usage: $0 <function user name>}"
SETUP_DIR="/opt/msu"
FAILED_ISSUE_FILE="/etc/issue.d/msu-setup-failed.issue"
INTEL_DEVICE_PLUGINS_VERSION="v0.34.0"
DUMMY_IP="203.0.113.1"

export PATH="/usr/local/sbin:/usr/local/bin:$PATH"
# cloud-init runs runcmd without $HOME, which some tools (e.g. crictl, git) need
export HOME="${HOME:-/root}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# shellcheck source=/dev/null
source "$SETUP_DIR/setup.env"
K3S_VERSION="${K3S_VERSION:-stable}"

step_no=0
current_step="preparation"

banner() {
    echo "***********************************************"
}

step() {
    step_no=$((step_no + 1))
    current_step="$1"
    echo
    banner
    echo "Step ${step_no}: ${current_step}"
    banner
}

# prints the failure to the console and puts it in front of the login prompt
report_failure() {
    trap - ERR
    local reason="$1" exit_code="${2:-1}" msg
    msg="$(banner)

SETUP FAILED in step ${step_no}: ${current_step}
${reason}

Please tell your IT contact.
Details are in /var/log/cloud-init-output.log

$(banner)"
    echo
    echo "$msg"
    mkdir -p "$(dirname "$FAILED_ISSUE_FILE")"
    # agetty interprets backslashes in issue files, escape them
    printf '%s\n\n' "${msg//\\/\\\\}" > "$FAILED_ISSUE_FILE" || true
    exit "$exit_code"
}

fail() {
    report_failure "$*"
}

on_error() {
    local exit_code=$? command="$BASH_COMMAND"
    report_failure "Command failed (exit code ${exit_code}): ${command}" "$exit_code"
}
trap on_error ERR

# the auth key must not stay on disk, whatever happens
trap 'rm -f "$SETUP_DIR/tailscale.txt"' EXIT

# retry <attempts> <command...>, waits 10s, 20s, ... between attempts
retry() {
    local attempts="$1" delay=10 n=1
    shift
    until "$@"; do
        if (( n >= attempts )); then
            return 1
        fi
        echo "Attempt ${n}/${attempts} failed, retrying in ${delay}s..."
        sleep "$delay"
        n=$((n + 1))
        delay=$((delay * 2))
    done
}

# containerd's content store, downloaded image layers end up here
CONTENT_DIR="/var/lib/rancher/k3s/agent/containerd/io.containerd.content.v1.content"
PROGRESS_INTERVAL=15

content_size() {
    du -sb "$CONTENT_DIR" 2>/dev/null | cut -f1 || echo 0
}

# pull_image <image>, prints progress (elapsed time, downloaded MB) while pulling
pull_image() {
    local image="$1" start_size start_time next_report pid
    start_size=$(content_size)
    start_time=$SECONDS
    next_report=$((SECONDS + PROGRESS_INTERVAL))
    k3s crictl pull "$image" > /dev/null &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        if (( SECONDS >= next_report )); then
            echo "    still downloading: $((SECONDS - start_time))s, $(( ($(content_size) - start_size) / 1000000 )) MB"
            next_report=$((SECONDS + PROGRESS_INTERVAL))
        fi
    done
    wait "$pid" || return 1
    echo "    done: $((SECONDS - start_time))s, $(( ($(content_size) - start_size) / 1000000 )) MB"
}

# remove a failure message of a previous run
rm -f "$FAILED_ISSUE_FILE"


step "Set hostname"
host_name="$(cat "$SETUP_DIR/hostname.txt")"
[ -n "$host_name" ] || fail "Hostname file $SETUP_DIR/hostname.txt is empty"
hostnamectl hostname "$host_name"
echo "Hostname set to $host_name"


step "Connect to Tailscale VPN"
tailscale_key="$(cat "$SETUP_DIR/tailscale.txt")"
rm -f "$SETUP_DIR/tailscale.txt"
tailscale up --auth-key="$tailscale_key" || fail "Could not connect to Tailscale (is the auth key valid and not expired?)"
unset tailscale_key
tailscale_ip="$(tailscale ip -4)"
tailscale_dns="$(tailscale status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
[ -n "$tailscale_ip" ] || fail "Could not determine the Tailscale IP address"
[ -n "$tailscale_dns" ] || fail "Could not determine the Tailscale DNS name"
echo "Tailscale IP: $tailscale_ip, DNS name: $tailscale_dns"


step "Create group kube and add user $USER_NAME"
groupadd -f kube
usermod -aG kube "$USER_NAME"


step "Create dummy network interface for K3s"
cat > /etc/netplan/99-k3s-dummy.yaml <<EOF
network:
  dummy-devices:
    dummy0:
      addresses:
        - ${DUMMY_IP}/24
      routes:
        - to: default
          via: ${DUMMY_IP}
          metric: 1000
EOF
chmod 600 /etc/netplan/99-k3s-dummy.yaml
netplan apply
ip -4 addr show dev dummy0 | grep -q "inet ${DUMMY_IP}/" \
    || fail "Dummy interface dummy0 does not have address ${DUMMY_IP}"


step "Write K3s configuration"
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<EOF
write-kubeconfig-mode: "0640"
write-kubeconfig-group: "kube"
node-ip: "${DUMMY_IP}"
bind-address: "${DUMMY_IP}"
tls-san:
  - "${tailscale_ip}"
disable:
  - traefik
  - servicelb
EOF
cat /etc/rancher/k3s/config.yaml


step "Install K3s ($K3S_VERSION)"
installer="$(mktemp)"
curl -sfL --retry 5 -o "$installer" https://get.k3s.io || fail "Could not download the K3s installer"
if [[ "$K3S_VERSION" == v* ]]; then
    INSTALL_K3S_VERSION="$K3S_VERSION" sh "$installer"
else
    INSTALL_K3S_CHANNEL="$K3S_VERSION" sh "$installer"
fi
rm -f "$installer"


step "Wait for K3s to be ready"
for _ in $(seq 60); do
    [ -n "$(kubectl get nodes -o name 2>/dev/null)" ] && break
    sleep 5
done
[ -n "$(kubectl get nodes -o name 2>/dev/null)" ] || fail "K3s node did not register within 5 minutes"
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl get nodes -o wide


step "Install Intel GPU device plugin ($INTEL_DEVICE_PLUGINS_VERSION)"
retry 3 kubectl apply -n kube-system \
    -k "https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin?ref=${INTEL_DEVICE_PLUGINS_VERSION}" \
    || fail "Could not install the Intel GPU device plugin"


step "Enable GPU resource sharing"
kubectl patch -n kube-system daemonsets.apps intel-gpu-plugin \
    --patch '{"spec": {"template": {"spec": {"containers":[{"name": "intel-gpu-plugin", "args": ["-shared-dev-num=30"]}]}}}}'
kubectl -n kube-system rollout status daemonset/intel-gpu-plugin --timeout=300s \
    || fail "Intel GPU device plugin did not become ready"


step "Pull application images"
mapfile -t images < <(grep -Ev '^[[:space:]]*(#|$)' "$SETUP_DIR/images.txt" || true)
if [ "${#images[@]}" -eq 0 ]; then
    echo "No images to pull"
fi
for i in "${!images[@]}"; do
    image="${images[$i]}"
    echo "[$((i + 1))/${#images[@]}] $image"
    retry 3 pull_image "$image" || fail "Could not pull image $image"
done


echo
banner
echo
echo "SETUP SUCCESSFUL"
echo
banner
