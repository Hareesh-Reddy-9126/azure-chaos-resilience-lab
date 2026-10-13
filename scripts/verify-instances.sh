#!/usr/bin/env bash
# verify-instances.sh
# Read-only Azure CLI script to list VMSS instances, zones, and statuses.
# Requires: az login, appropriate RBAC (Reader or Contributor on RG)

set -euo pipefail

# Configuration - UPDATE THESE VALUES
RESOURCE_GROUP="rg-t087-chaos-resilience"
VMSS_NAME="vmss-t087-chaos-resilience"
SUBSCRIPTION_ID=""  # Optional: set to override default subscription

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Read-only script to verify VMSS instance status across availability zones.

Options:
    -g, --resource-group NAME    Resource group name (default: $RESOURCE_GROUP)
    -n, --vmss-name NAME         VMSS name (default: $VMSS_NAME)
    -s, --subscription ID        Subscription ID (optional)
    -h, --help                   Show this help

Examples:
    $0
    $0 -g my-rg -n my-vmss
    $0 --subscription xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -n|--vmss-name)
            VMSS_NAME="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
    echo -e "${BLUE}Setting subscription to $SUBSCRIPTION_ID...${NC}"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

echo -e "${BLUE}=== VMSS Instance Verification ===${NC}"
echo -e "Resource Group: ${YELLOW}$RESOURCE_GROUP${NC}"
echo -e "VMSS Name:      ${YELLOW}$VMSS_NAME${NC}"
echo ""

# Verify resource group exists
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${RED}Error: Resource group '$RESOURCE_GROUP' not found or no access${NC}" >&2
    exit 1
fi

# Get VMSS details
echo -e "${BLUE}--- VMSS Overview ---${NC}"
az vmss show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "{name:name, location:location, sku:sku.name, capacity:sku.capacity, zones:zones, orchestrationMode:orchestrationMode, upgradePolicy:upgradePolicy.mode}" \
    -o table

echo ""

# List instances with zones and power states
echo -e "${BLUE}--- Instance Details ---${NC}"
az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[].{instanceId:instanceId, zone:zone, powerState:instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0], provisioningState:provisioningState, vmId:vmId}" \
    -o table

echo ""

# Count instances by zone
echo -e "${BLUE}--- Zone Distribution ---${NC}"
az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[].zone" \
    -o tsv | sort | uniq -c | while read count zone; do
    echo -e "  Zone ${YELLOW}$zone${NC}: ${GREEN}$count${NC} instance(s)"
done

echo ""

# Show instance view for each instance (detailed power state)
echo -e "${BLUE}--- Detailed Power States ---${NC}"
az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[].{instanceId:instanceId, zone:zone, statuses:instanceView.statuses[?starts_with(code, 'PowerState/') || starts_with(code, 'ProvisioningState/')].{code:code, level:level, displayStatus:displayStatus, time:time}}" \
    -o json | jq -r '.[] | "Instance \(.instanceId) (Zone \(.zone)): \(.statuses[] | select(.code | startswith("PowerState/")) | .displayStatus)"'

echo -e "${GREEN}Verification complete.${NC}"