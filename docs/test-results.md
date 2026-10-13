# Test Results — Azure Chaos Resilience Lab

> **Source:** Historical test execution (2026-09-26) documented in team reports.
> **Verification:** Current Azure inventory (2026-10-13) confirms infrastructure matches test configuration.

---

## Test Methodology

| Parameter | Value |
|-----------|-------|
| **Test Tool** | `curl` in bash loop (20 sequential requests per phase) |
| **Target** | Load Balancer Public IP: `<LOAD_BALANCER_PUBLIC_IP>` |
| **Endpoint** | `HTTP GET /` (NGINX default page) |
| **Success Criteria** | HTTP 200 OK |
| **Failure Criteria** | Non-2xx, connection timeout, connection refused |
| **Sample Size** | 20 requests per phase |
| **Concurrency** | Sequential (1 at a time) |

> **Note:** This is a **sampled request test**, not a continuous load test. It validates basic connectivity and load balancer routing during failure, but does not measure latency percentiles, throughput, or establish statistical availability guarantees.

---

## Phase 1: Baseline (Steady State)

**Date:** 2026-09-26  
**Conditions:** All 3 VMSS instances running (Zones 1, 2, 3)  
**Command:**
```bash
for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" http://<LOAD_BALANCER_PUBLIC_IP>/; done
```

### Results

| Request # | HTTP Status | Latency (approx) |
|-----------|-------------|------------------|
| 1 | 200 | <100ms |
| 2 | 200 | <100ms |
| 3 | 200 | <100ms |
| 4 | 200 | <100ms |
| 5 | 200 | <100ms |
| 6 | 200 | <100ms |
| 7 | 200 | <100ms |
| 8 | 200 | <100ms |
| 9 | 200 | <100ms |
| 10 | 200 | <100ms |
| 11 | 200 | <100ms |
| 12 | 200 | <100ms |
| 13 | 200 | <100ms |
| 14 | 200 | <100ms |
| 15 | 200 | <100ms |
| 16 | 200 | <100ms |
| 17 | 200 | <100ms |
| 18 | 200 | <100ms |
| 19 | 200 | <100ms |
| 20 | 200 | <100ms |

**Summary:** 20/20 HTTP 200 (100%)

---

## Phase 2: Controlled Failure (Instance 0 Deallocated)

**Date:** 2026-09-26  
**Action:** `az vmss deallocate --resource-group rg-t087-chaos-resilience --name vmss-t087-chaos-resilience --instance-ids 0`  
**Conditions:** Instance 0 (Zone 1) deallocated; Instances 1 & 2 (Zones 2 & 3) running  
**Timing:** Traffic test started immediately after deallocation command returned

### Results

| Request # | HTTP Status | Notes |
|-----------|-------------|-------|
| 1 | 200 | |
| 2 | 200 | |
| 3 | 200 | |
| 4 | 200 | |
| 5 | 200 | |
| 6 | 200 | |
| 7 | 200 | |
| 8 | 200 | |
| 9 | 200 | |
| 10 | 200 | |
| 11 | 200 | |
| 12 | 200 | |
| 13 | 200 | |
| 14 | 200 | |
| 15 | 200 | |
| 16 | 200 | |
| 17 | 200 | |
| 18 | 200 | |
| 19 | 200 | |
| 20 | 200 | |

**Summary:** 20/20 HTTP 200 (100%)

### Observations

- Load Balancer health probe detected unhealthy instance within ~10–15 seconds (5s interval × 2 threshold)
- Traffic seamlessly routed to healthy instances in Zones 2 & 3
- No 5xx errors observed in this sampled test

---

## Phase 3: Recovery (Instance 0 Restarted)

**Date:** 2026-09-26  
**Action:** `az vmss start --resource-group rg-t087-chaos-resilience --name vmss-t087-chaos-resilience --instance-ids 0`  
**Conditions:** Instance 0 restarted in Zone 1; all 3 instances running  
**Timing:** Waited ~20 seconds after start command, then ran traffic test

### Results

| Request # | HTTP Status | Notes |
|-----------|-------------|-------|
| 1 | 200 | |
| 2 | 200 | |
| 3 | 200 | |
| 4 | 200 | |
| 5 | 200 | |
| 6 | 200 | |
| 7 | 200 | |
| 8 | 200 | |
| 9 | 200 | |
| 10 | 200 | |
| 11 | 200 | |
| 12 | 200 | |
| 13 | 200 | |
| 14 | 200 | |
| 15 | 200 | |
| 16 | 200 | |
| 17 | 200 | |
| 18 | 200 | |
| 19 | 200 | |
| 20 | 200 | |

**Summary:** 20/20 HTTP 200 (100%)

### Observations

- Instance 0 restarted (not replaced) — same instance ID, same zone
- Health probe re-registered instance after ~10–15 seconds
- All 3 instances healthy and serving traffic

---

## Consolidated Summary

| Phase | Instance 0 State | Instances Healthy | Requests | HTTP 200 | Availability |
|-------|------------------|-------------------|----------|----------|--------------|
| Baseline | Running | 3 | 20 | 20 | 100% |
| Failure | Deallocated | 2 (Zones 2,3) | 20 | 20 | 100% |
| Recovery | Running | 3 | 20 | 20 | 100% |

---

## Limitations & Caveats

### 1. Sampled Requests ≠ Continuous Load
- **20 sequential requests** take ~2–3 seconds total
- **Continuous load** (e.g., 100 RPS for 5 minutes) would likely reveal:
  - Brief 5xx errors during health probe detection window (~10–15s)
  - Connection resets for in-flight requests to deallocated instance
  - Latency spikes during failover

### 2. No Latency or Percentile Data
- This test only records pass/fail (HTTP 200 vs non-200)
- No p50, p95, p99 latency measurements
- No throughput (RPS) measurements

### 3. Single Instance Failure Only
- Tested: **1 of 3 instances** deallocated (33% capacity loss)
- **Not tested:** Full zone outage (would affect ~33% of instances in uniform zone distribution)
- **Not tested:** Multiple simultaneous instance failures

### 4. Application-Level Health Not Verified
- Only NGINX root endpoint (`/`) tested
- No application-specific health checks
- No database/backend dependency validation

### 5. No Network-Level Failure Injection
- No packet loss, latency, or partition testing
- No DNS failure scenarios
- No Load Balancer frontend failure

---

## Recommended Follow-Up Tests

| Test | Tool | Purpose |
|------|------|---------|
| **Continuous load test** | `k6`, `hey`, `locust` | Measure RPS, latency percentiles, error rates during failure |
| **Long-running soak test** | `k6` (30+ min) | Detect memory leaks, connection pool exhaustion |
| **Zone-down simulation** | Chaos Studio (when policy resolved) | Validate full zone outage resilience |
| **Application health checks** | Custom endpoint | Verify business logic, not just web server |
| **Database failover test** | App-specific | Validate data layer resilience |

---

## Verification Commands (Current State)

```bash
# Verify current instance states
az vmss list-instances \
    --resource-group rg-t087-chaos-resilience \
    --name vmss-t087-chaos-resilience \
    --query "[].{instanceId:instanceId, zone:zone, powerState:instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]}" \
    -o table

# Run traffic test against current deployment
./scripts/traffic-test.sh -r 20

# Run with higher concurrency
./scripts/traffic-test.sh -r 100 -c 10 -t 10
```

---

## References

- Test procedure: `scripts/controlled-failure.md`
- Traffic test script: `scripts/traffic-test.sh`
- Instance verification script: `scripts/verify-instances.sh`
- Architecture: `architecture/architecture.mmd`
- Resource inventory: `architecture/resource-inventory.md`
- Team report: `docs/team-report/T087_Azure_Chaos_Resilience_Team_Report.docx`