#!/usr/bin/env bash
# Create one ephemeral Google Compute Engine VM and let cloud-init register it
# as a just-in-time GitHub self-hosted runner.
#
# Usage:
#   INSTANCE_NAME=<name> RUNNER_LABEL=<label> REGION=asia-east1 \
#   ZONES="a b c" MACHINE_TYPE=t2d-standard-16 CLOUD_INIT=cloud-init.yml \
#     gcp-provision-vm.sh
#
# Prints key=value pairs for GitHub Actions outputs on success.
set -euo pipefail

: "${INSTANCE_NAME:?INSTANCE_NAME required}"
: "${RUNNER_LABEL:?RUNNER_LABEL required}"
: "${REGION:?REGION required}"
: "${ZONES:?ZONES required}"
: "${MACHINE_TYPE:?MACHINE_TYPE required}"
: "${CLOUD_INIT:?CLOUD_INIT path required}"

BOOT_DISK_SIZE_GB=${BOOT_DISK_SIZE_GB:-256}
BOOT_DISK_TYPE=${BOOT_DISK_TYPE:-pd-balanced}
IMAGE_FAMILY=${IMAGE_FAMILY:-ubuntu-2204-lts}
IMAGE_PROJECT=${IMAGE_PROJECT:-ubuntu-os-cloud}
SERVICE_ACCOUNT=${SERVICE_ACCOUNT:-}

created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
github_run_id=${GITHUB_RUN_ID:-manual}
github_repository=${GITHUB_REPOSITORY:-unknown}

service_account_args=()
if [[ -n "$SERVICE_ACCOUNT" ]]; then
	service_account_args=(--service-account="$SERVICE_ACCOUNT")
fi

try_create() {
	local zone="$1"
	echo "::group::gcloud compute instances create: $INSTANCE_NAME zone=$zone type=$MACHINE_TYPE" >&2
	if gcloud compute instances create "$INSTANCE_NAME" \
		--zone="$zone" \
		--machine-type="$MACHINE_TYPE" \
		--image-family="$IMAGE_FAMILY" \
		--image-project="$IMAGE_PROJECT" \
		--boot-disk-size="${BOOT_DISK_SIZE_GB}GB" \
		--boot-disk-type="$BOOT_DISK_TYPE" \
		--scopes=https://www.googleapis.com/auth/cloud-platform \
		--labels="app=cangjie-build,managed-by=github-actions,github-run-id=${github_run_id}" \
		--metadata="created_at=${created_at},runner_label=${RUNNER_LABEL},github_repository=${github_repository}" \
		--metadata-from-file=user-data="$CLOUD_INIT" \
		"${service_account_args[@]}" \
		--quiet \
		-o none; then
		echo "::endgroup::" >&2
		return 0
	fi
	echo "::endgroup::" >&2
	return 1
}

for suffix in $ZONES; do
	if [[ "$suffix" == *"-"* ]]; then
		zone="$suffix"
	else
		zone="${REGION}-${suffix}"
	fi

	if try_create "$zone"; then
		printf 'region=%s\n' "$REGION"
		printf 'zone=%s\n' "$zone"
		printf 'instance_name=%s\n' "$INSTANCE_NAME"
		printf 'runner_label=%s\n' "$RUNNER_LABEL"
		exit 0
	fi
done

echo "::error::Could not allocate $MACHINE_TYPE in region $REGION zones {$ZONES}." >&2
exit 1
