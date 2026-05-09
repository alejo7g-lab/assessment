package com.company.assessment.infrastructure.adapter.in.rest;

import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicInteger;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import lombok.extern.slf4j.Slf4j;

/**
 * Simulates a flaky upstream service for demo purposes.
 * Configurable failure rate and artificial latency to trigger
 * Resilience4j retry, circuit breaker, and time limiter patterns.
 */
@Slf4j
@RestController
@RequestMapping("/upstream")
public class FlakyUpstreamController {

    private final AtomicInteger totalRequests = new AtomicInteger(0);
    private final AtomicInteger failedRequests = new AtomicInteger(0);
    private final AtomicInteger successRequests = new AtomicInteger(0);

    @Value("${demo.upstream.failure-rate:0.6}")
    private double failureRate;

    @Value("${demo.upstream.latency-ms:0}")
    private long latencyMs;

    @PostMapping("/process")
    public ResponseEntity<String> process(
            @RequestBody String payload,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey) {

        int requestNumber = totalRequests.incrementAndGet();
        log.info("[UPSTREAM] Request #{} received | Idempotency-Key: {} | failureRate: {}",
                requestNumber, idempotencyKey, failureRate);

        // Simulate latency
        if (latencyMs > 0) {
            try {
                log.warn("[UPSTREAM] Simulating {}ms latency...", latencyMs);
                Thread.sleep(latencyMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }

        // Simulate random failures based on configured failure rate
        if (ThreadLocalRandom.current().nextDouble() < failureRate) {
            int failCount = failedRequests.incrementAndGet();
            log.error("[UPSTREAM] Request #{} FAILED (total failures: {})", requestNumber, failCount);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("{\"error\":\"Upstream service error\",\"request\":" + requestNumber + "}");
        }

        int okCount = successRequests.incrementAndGet();
        log.info("[UPSTREAM] Request #{} SUCCESS (total successes: {})", requestNumber, okCount);
        return ResponseEntity.ok(
                "{\"result\":\"processed\",\"idempotencyKey\":\"" + idempotencyKey
                        + "\",\"request\":" + requestNumber + "}");
    }

    /**
     * Returns upstream service statistics and allows runtime reconfiguration.
     */
    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> stats() {
        return ResponseEntity.ok(Map.of(
                "totalRequests", totalRequests.get(),
                "failedRequests", failedRequests.get(),
                "successRequests", successRequests.get(),
                "configuredFailureRate", failureRate,
                "configuredLatencyMs", latencyMs));
    }

    /**
     * Reconfigure the upstream failure rate and latency at runtime.
     */
    @PostMapping("/configure")
    public ResponseEntity<Map<String, Object>> configure(
            @RequestParam(required = false) Double failureRate,
            @RequestParam(required = false) Long latencyMs) {

        if (failureRate != null) {
            this.failureRate = Math.max(0.0, Math.min(1.0, failureRate));
        }
        if (latencyMs != null) {
            this.latencyMs = Math.max(0, latencyMs);
        }

        // Reset counters on reconfiguration
        totalRequests.set(0);
        failedRequests.set(0);
        successRequests.set(0);

        log.info("[UPSTREAM] Reconfigured: failureRate={}, latencyMs={}", this.failureRate, this.latencyMs);

        return ResponseEntity.ok(Map.of(
                "failureRate", this.failureRate,
                "latencyMs", this.latencyMs,
                "message", "Upstream reconfigured. Counters reset."));
    }
}
