# Demo: Resilient Integration Service

## Overview

This service demonstrates a **clean architecture** integration framework with built-in resilience patterns using **Resilience4j**. It includes a simulated **flaky upstream service** that can be configured at runtime to produce failures and latency, allowing you to observe how the resilience mechanisms mitigate issues.

### Architecture

```
Client (curl/Postman)
       │
       ▼
┌──────────────────────────┐
│  TransactionController   │  ← REST API entry point
│  POST /api/v1/transactions│
└──────────┬───────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│  ResilientIntegrationAdapter             │
│  ┌────────────────────────────────────┐  │
│  │  @CircuitBreaker ──► @Retry ──► @TimeLimiter  │
│  └────────────────────────────────────┘  │
│  fallbackProcess() ← on exhaustion       │
└──────────┬───────────────────────────────┘
           │
           ▼
┌──────────────────────────┐
│  FlakyUpstreamController │  ← Simulated upstream (same JVM)
│  POST /upstream/process  │
│  GET  /upstream/stats    │
│  POST /upstream/configure│
└──────────────────────────┘
```

## How to Run

### Prerequisites
- **Java 21**
- **Maven 3.8+** (or use the included `mvnw` wrapper)

### Start the service

```bash
./mvnw spring-boot:run -DskipTests
```

The application starts on **http://localhost:8080**.

### Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/transactions` | POST | Send a transaction through the resilient adapter |
| `/upstream/process` | POST | Flaky upstream (called internally by the adapter) |
| `/upstream/stats` | GET | View upstream request statistics |
| `/upstream/configure` | POST | Reconfigure failure rate and latency at runtime |
| `/actuator/health` | GET | Health check |

---

## Demo Scenarios

### Scenario 1: Healthy Upstream (0% failure)

Configure the upstream to never fail:

```powershell
# Configure: 0% failure, 0ms latency
Invoke-RestMethod -Uri "http://localhost:8080/upstream/configure?failureRate=0.0&latencyMs=0" -Method POST

# Send a transaction
Invoke-RestMethod -Uri "http://localhost:8080/api/v1/transactions" `
  -Method POST -ContentType "application/json" `
  -Headers @{"Idempotency-Key"="healthy-001"} `
  -Body '{"amount": 500, "currency": "USD"}'
```

**Expected result:**
```json
{
  "status": "SUCCESS",
  "idempotencyKey": "healthy-001",
  "response": "{\"result\":\"processed\",\"idempotencyKey\":\"healthy-001\",\"request\":1}"
}
```

The request passes through directly. No retries needed.

---

### Scenario 2: Flaky Upstream (60% failure) — Retry with Exponential Backoff + Jitter

```powershell
# Configure: 60% failure rate
Invoke-RestMethod -Uri "http://localhost:8080/upstream/configure?failureRate=0.6" -Method POST

# Send 5 transactions
1..5 | ForEach-Object {
    Invoke-RestMethod -Uri "http://localhost:8080/api/v1/transactions" `
      -Method POST -ContentType "application/json" `
      -Headers @{"Idempotency-Key"="flaky-$_"} `
      -Body "{`"amount`": $($_ * 100)}" | ConvertTo-Json -Compress
}

# Check upstream stats
Invoke-RestMethod -Uri "http://localhost:8080/upstream/stats" | ConvertTo-Json
```

**Expected behavior:**
- Some requests return `"status": "SUCCESS"` (retry succeeded within 3 attempts)
- Others return `"status": "FALLBACK"` (all 3 attempts failed)
- The **upstream stats** show more `totalRequests` than the 5 you sent, because retries generate additional upstream calls
- **Logs** show retry intervals with exponential backoff (500ms → 1000ms → 2000ms) plus random jitter

**How Retry mitigates the issue:**
> Instead of immediately failing, Resilience4j retries up to **3 attempts** with **exponential backoff** (base 500ms, multiplier 2x) and **random jitter** (±50%). This avoids thundering-herd effects and gives transient errors time to resolve.

---

### Scenario 3: Total Upstream Failure (100%) — Circuit Breaker Activation

```powershell
# Configure: 100% failure rate
Invoke-RestMethod -Uri "http://localhost:8080/upstream/configure?failureRate=1.0" -Method POST

# Send 12 transactions rapidly
1..12 | ForEach-Object {
    $r = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/transactions" `
      -Method POST -ContentType "application/json" `
      -Headers @{"Idempotency-Key"="cb-$_"} `
      -Body "{`"test`": $_}"
    Write-Host "Request $($_): $($r.status)"
}

# Check upstream stats
Invoke-RestMethod -Uri "http://localhost:8080/upstream/stats" | ConvertTo-Json
```

**Expected behavior:**
- All 12 requests return `"status": "FALLBACK"`
- **But the upstream only receives ~4-10 requests** (not 12 × 3 = 36)
- After the sliding window of 10 fills with >50% failures, the **circuit breaker opens**
- Subsequent requests are **short-circuited immediately** — they never reach the upstream

**How Circuit Breaker mitigates the issue:**
> When the failure rate exceeds **50%** in a sliding window of **10 calls**, the circuit breaker transitions to **OPEN** state. All subsequent requests fail fast with the fallback response, preventing the overwhelmed upstream from receiving more load. After **10 seconds**, the circuit enters **HALF-OPEN** state and allows **3 probe calls** to test if the upstream has recovered.

---

### Scenario 4: Idempotency Key Support

```powershell
# Send the same idempotency key multiple times
Invoke-RestMethod -Uri "http://localhost:8080/upstream/configure?failureRate=0.0" -Method POST

1..3 | ForEach-Object {
    Invoke-RestMethod -Uri "http://localhost:8080/api/v1/transactions" `
      -Method POST -ContentType "application/json" `
      -Headers @{"Idempotency-Key"="same-key-xyz"} `
      -Body '{"amount": 100}' | ConvertTo-Json -Compress
}
```

**Expected behavior:**
- All 3 requests carry the same `Idempotency-Key: same-key-xyz` header to the upstream
- In a real system, the upstream would deduplicate and return the same response for all 3
- **Logs** show the same idempotency key propagated through the trace

**How Idempotency mitigates the issue:**
> When retries or client duplicates send the same request multiple times, the `Idempotency-Key` header ensures the upstream processes the operation **exactly once**. This prevents double charges, duplicate records, or other side effects.

---

### Scenario 5: Observability — Trace Propagation

Watch the application logs during any scenario above. Each log line includes:

```
INFO [assessment,<traceId>,<spanId>] ... TransactionController  : Received transaction request...
INFO [assessment,<traceId>,<spanId>] ... ResilientIntegrationAdapter : Initiating external integration call...
```

- The **same traceId** correlates all log entries for a single request across the controller and adapter
- **W3C Trace Context** headers (`traceparent`) are automatically propagated to the upstream via RestClient
- In production, these traces integrate with **Jaeger**, **Zipkin**, or any OpenTelemetry-compatible backend

---

## Resilience Configuration Summary

| Pattern | Config | Purpose |
|---|---|---|
| **Retry** | 3 attempts, 500ms base wait, 2x exponential, ±50% jitter | Handles transient failures without overwhelming upstream |
| **Circuit Breaker** | Window=10, threshold=50%, open=10s, half-open probes=3 | Stops calling a failing upstream; allows recovery |
| **TimeLimiter** | 2s timeout | Prevents blocking threads indefinitely on slow calls |
| **Idempotency Key** | `Idempotency-Key` HTTP header | Ensures at-most-once processing despite retries |
| **Tracing** | W3C / OpenTelemetry via Micrometer | End-to-end request correlation in distributed systems |

## Configuring the Flaky Upstream at Runtime

```powershell
# Set failure rate (0.0 to 1.0) and latency in ms
Invoke-RestMethod -Uri "http://localhost:8080/upstream/configure?failureRate=0.8&latencyMs=1000" -Method POST

# View statistics
Invoke-RestMethod -Uri "http://localhost:8080/upstream/stats"
```

| Parameter | Type | Range | Default | Description |
|---|---|---|---|---|
| `failureRate` | double | 0.0 – 1.0 | 0.6 | Probability of returning HTTP 500 |
| `latencyMs` | long | 0+ | 0 | Artificial delay in milliseconds |
