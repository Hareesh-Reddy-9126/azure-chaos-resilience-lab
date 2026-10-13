# Controlled Failure Test Procedure

> **Purpose:** Document the exact commands and verification steps for the controlled VMSS instance failure test.
> **Scope:** Single instance deallocation and restart. **Not a zone-down fault.**
> **Safety:** These commands modify production resources. Review carefully before execution.

---

## Test Overview

| Property | Value |
|----------|-------|
| **Target** | `vmss-t087-chaos-resilience` instance 0 (Zone 1) |
| **Failure Action** | `az vmss deallocate` (stops instance, preserves disks) |
| **Recovery Action** | `az vmss start` (restarts same instance) |
| **Load Balancer** | `lb-t087-chaos-resilience` (Standard, zone-redundant) |
| **Health Probe** | HTTP `:80 /`, 5s interval, 2 threshold |
| **Expected Detection** | ~10–15 seconds |

---

## Prerequisites

- Azure CLI authenticated: `az login`
- Appropriate RBAC: **Virtual Machine Contributor** or **Owner** on resource group
- Traffic test running in separate terminal: `./scripts/traffic-test.sh -r 100 -c 5`
- Instance 0 is currently **Running** in Zone 1

---

## Phase 1: Baseline Verification

```bash
# Verify all instances running
az vmss list-instances \
    --resource-group rg-t087-chaos-resilience \
    --name vmss-t087-chaos-resilience \
    --query "[].{instanceId:instanceId, zone:zone, powerState:instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]}" \
    -o table

# Expected: All 3 instances show "PowerState/running"
```

```bash
# Baseline traffic test (20 requests)
./scripts/traffic-test.sh -r 20
# Expected: 20/20 HTTP 200
```

---

## Phase 2: Controlled Failure — Deallocate Instance 0

> ⚠️ **WARNING:** This stops a production VMSS instance. Traffic will be served by remaining instances (Zone 2 & 3).

```bash
# Deallocate instance 0 (Zone 1)
az vmss deallocate \
    --resource-group rg-t087-chaos-resilience \
    --name vmss-t087-chaos-resilience \
    --instance-ids 0
```

### Verify Deallocation

```bash
# Check instance state
az vmss list-instances \
    --resource-group rg-t087-chaos-resilience \
    --name vmss-t087-chaos-resilience \
    --query "[].{instanceId:instanceId, zone:zone, powerState:instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]}" \
    -o table

# Expected: Instance 0 shows "PowerState/deallocated"
```

### Traffic Test During Failure

```bash
# Run traffic test while instance 0 is deallocated
./scripts/traffic-test.sh -r 20

# Expected: 20/20 HTTP 200 (served by instances 1 & 2 in Zones 2 & 3)
# Note: Brief 5xx may appear during ~10s health probe detection window
```

### Monitor Load Balancer Health Probe

```bash
# Watch backend pool health (run in separate terminal)
watch -n 2 'az network lb address-pool show \
    --resource-group rg-t087-chaos-resilience \
    --lb-name lb-t087-chaos-resilience \
    --name bepool \
    --query "backendIPConfigurations[].{ip:id, provisioningState:provisioningState}" \
    -o table'
```

---

## Phase 3: Recovery — Restart Instance 0

```bash
# Restart instance 0 (same instance, same zone)
az vmss start \
    --resource-group rg-t087-chaos-resilience \
    --name vmss-t087-chaos-resilience \
    --instance-ids 0
```

### Verify Restart

```bash
# Check instance state
az vmss list-instances \
    --resource-group rg-t087-chaos-resilience \
    --name vmss-t087-chaos-resilience \
    --query "[].{instanceId:instanceId, zone:zone, powerState:instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]}" \
    -o table

# Expected: Instance 0 shows "PowerState/running" (may take 1-2 minutes)
```

### Traffic Test After Recovery

```bash
# Wait for health probe to recover (~10-15s after instance running)
sleep 20

# Run traffic test
./scripts/traffic-test.sh -r 20

# Expected: 20/20 HTTP 200 (all 3 instances healthy)
```

---

## Phase 4: Final Verification

```bash
# Confirm all 3 instances running
az vmss list-instances \
    --resource-group rg-t087-chaos-resilience \
    --name vmss-t087-chaos-resilience \
    --query "[].{instanceId:instanceId, zone:zone, powerState:instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]}" \
    -o table

# Expected: All 3 instances "PowerState/running"
```

---

## Complete Command Summary

```bash
# 1. Baseline
az vmss list-instances -g rg-t087-chaos-resilience -n vmss-t087-chaos-resilience -o table
./scripts/traffic-test.sh -r 20

# 2. Failure
az vmss deallocate -g rg-t087-chaos-resilience -n vmss-t087-chaos-resilience --instance-ids 0
az vmss list-instances -g rg-t087-chaos-resilience -n vmss-t087-chaos-resilience -o table
./scripts/traffic-test.sh -r 20

# 3. Recovery
az vmss start -g rg-t087-chaos-resilience -n vmss-t087-chaos-resilience --instance-ids 0
sleep 20
az vmss list-instances -g rg-t087-chaos-resilience -n vmss-t087-chaos-resilience -o table
./scripts/traffic-test.sh -r 20
```

---

## Safety Checklist

- [ ] Confirm you are targeting the correct resource group and VMSS
- [ ] Verify instance 0 is in Zone 1 (not a critical singleton)
- [ ] Run traffic test in separate terminal before starting
- [ ] Have rollback plan: `az vmss start` if deallocation causes issues
- [ ] Monitor Azure Portal > VMSS > Instances for visual confirmation
- [ ] Document actual timestamps and observations

---

## What This Test Does NOT Validate

| Not Tested | Reason |
|------------|--------|
| **Full zone outage** | Only single instance deallocated; Zones 2 & 3 unaffected |
| **Chaos Studio zoneDown fault** | Blocked by Azure Policy; never executed |
| **Data disk persistence** | Instance deallocated (disks preserved), not deleted |
| **VMSS auto-scale** | Capacity fixed at 3; no scale-out triggered |
| **Application-level resilience** | Only NGINX health endpoint tested |

---

## Historical Results (2026-09-26)

| Phase | Command | Requests | HTTP 200 | Notes |
|-------|---------|----------|----------|-------|
| Baseline | — | 20 | 20 | Steady state |
| Failure | `az vmss deallocate --instance-ids 0` | 20 | 20 | Instance 0 deallocated |
| Recovery | `az vmss start --instance-ids 0` | 20 | 20 | Instance 0 restarted |

> **Limitation:** 20 sampled requests per phase. Continuous load testing would likely show brief errors during health-probe detection window (~10–15s).

---

## References

- [az vmss deallocate](https://learn.microsoft.com/cli/azure/vmss#az-vmss-deallocate)
- [az vmss start](https://learn.microsoft.com/cli/azure/vmss#az-vmss-start)
- [Load Balancer health probes](https://learn.microsoft.com/azure/load-balancer/load-balancer-custom-probe-overview)
- Project report: `docs/team-report/T087_Azure_Chaos_Resilience_Team_Report.docx`