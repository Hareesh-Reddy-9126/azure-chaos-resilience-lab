# Azure Resource Inventory — Verified Configuration

> **Source:** Azure CLI inventory (`az resource list`, `az vmss list-instances`, `az network lb show`) run in Cloud Shell on 2026-10-13.
> **Scope:** Read-only inspection of existing resources. No resources were created, modified, or deleted.

---

## Subscription & Resource Group

| Property | Value |
|----------|-------|
| **Subscription** | Azure for Students |
| **Resource Group** | `rg-t087-chaos-resilience` |
| **Resource Group Location** | Central India |
| **Workload Location** | East Asia |

> **Note:** The resource group's metadata location (Central India) does not constrain its child resources. All workload resources are deployed in **East Asia**.

---

## Virtual Machine Scale Set

| Property | Value |
|----------|-------|
| **Name** | `vmss-t087-chaos-resilience` |
| **Location** | East Asia |
| **SKU** | `Standard_B2ats_v2` |
| **Capacity** | 3 |
| **Orchestration Mode** | Uniform |
| **Upgrade Policy** | Manual |
| **Zones** | `["1", "2", "3"]` |
| **Image** | Ubuntu 22.04 LTS (Canonical) |
| **Application** | NGINX on port 80 (via cloud-init) |

### Instance Details (Current State)

| Instance ID | Zone | Power State | Provisioning State |
|-------------|------|-------------|-------------------|
| 0 | 1 | Running | Succeeded |
| 1 | 2 | Running | Succeeded |
| 2 | 3 | Running | Succeeded |

> **Note:** Instance states reflect the current inventory. The historical test deallocated instance 0 and restarted it; all three are running now.

---

## Load Balancer

| Property | Value |
|----------|-------|
| **Name** | `lb-t087-chaos-resilience` |
| **Location** | East Asia |
| **SKU** | Standard |
| **Public IP Resource** | `lb-t087-chaos-resilience-publicip` |
| **Public IP Address** | `<LOAD_BALANCER_PUBLIC_IP>` |
| **Public IP Allocation** | Static |
| **Public IP SKU** | Standard |
| **Backend Pool** | `bepool` (contains all 3 VMSS instances) |
| **Frontend Port** | 80 (TCP) |
| **Backend Port** | 80 (TCP) |
| **Protocol** | TCP |
| **Health Probe** | `lb-t087-chaos-resilience-probe01` |
| **Probe Protocol** | HTTP |
| **Probe Port** | 80 |
| **Probe Path** | `/` |
| **Probe Interval** | 5 seconds (default) |
| **Unhealthy Threshold** | 2 (default) |

---

## Networking

| Property | Value |
|----------|-------|
| **Virtual Network** | `vnet-eastasia` |
| **Address Space** | `172.16.0.0/16` |
| **Subnet** | `snet-eastasia-1` |
| **Subnet CIDR** | *Not returned by inventory — not documented* |
| **Network Security Group** | `basicNsgvnet-eastasia-nic01` |
| **Inbound Rule** | TCP port 80, Priority 300, Source `*`, Destination `*`, Action Allow |

---

## Log Analytics / Monitoring

| Property | Value |
|----------|-------|
| **Log Analytics Workspace** | `law-t087-chaos` (from project report) |
| **Location** | East Asia (inferred) |

---

## Chaos Studio

| Property | Value |
|----------|-------|
| **Workspace/Experiment Name** | `chaos-t087` / `exp-t087-zone-down` (from project report) |
| **Target** | `vmss-t087-chaos-resilience` |
| **Fault Type** | `Microsoft.Compute/virtualMachineScaleSets` → `zoneDown` |
| **Intended Duration** | 10 minutes |
| **Status** | **NOT EXECUTED** |
| **Blocker** | Subscription-level **Allowed resource deployment regions** policy prevented Chaos Studio agent/resource deployment |

> **Critical:** No zone-down fault was ever injected. The experiment remains a saved configuration in the portal.

---

## Test Results Summary (Historical)

| Phase | Action | Requests | HTTP 200 | Availability |
|-------|--------|----------|----------|--------------|
| Baseline | Steady state | 20 | 20 | 100% |
| Failure | `az vmss deallocate --instance-ids 0` | 20 | 20 | 100% |
| Recovery | `az vmss start --instance-ids 0` | 20 | 20 | 100% |

> **Limitation:** 20 sampled requests per phase do not establish a 100% availability guarantee. Continuous load testing would likely reveal brief errors during health-probe detection window.

---

## Verification Commands

```bash
# Subscription & RG
az account show --query "{subscription:name, subscriptionId:id}" -o json
az group show --name rg-t087-chaos-resilience --query "{name:name, location:location, provisioningState:properties.provisioningState}" -o json

# VMSS
az vmss show --resource-group rg-t087-chaos-resilience --name vmss-t087-chaos-resilience -o json
az vmss list-instances --resource-group rg-t087-chaos-resilience --name vmss-t087-chaos-resilience -o table

# Load Balancer
az network lb show --resource-group rg-t087-chaos-resilience --name lb-t087-chaos-resilience -o json
az network lb probe show --resource-group rg-t087-chaos-resilience --lb-name lb-t087-chaos-resilience --name lb-t087-chaos-resilience-probe01 -o json
az network public-ip show --resource-group rg-t087-chaos-resilience --name lb-t087-chaos-resilience-publicip -o json

# Networking
az network vnet show --resource-group rg-t087-chaos-resilience --name vnet-eastasia -o json
az network nsg show --resource-group rg-t087-chaos-resilience --name basicNsgvnet-eastasia-nic01 -o json
```