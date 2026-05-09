package com.company.assessment.infrastructure.adapter.out.external;

import java.util.Optional;
import java.util.concurrent.CompletableFuture;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import com.company.assessment.application.port.out.IntegrationPort;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import io.github.resilience4j.timelimiter.annotation.TimeLimiter;
import lombok.extern.slf4j.Slf4j;

@Slf4j
@Component
public class ResilientIntegrationAdapter implements IntegrationPort {

    private final RestClient restClient;
    private final String upstreamUrl;
    private static final String COMPONENT_NAME = "externalIntegration";

    public ResilientIntegrationAdapter(RestClient restClient,
                                       @Value("${integration.upstream.url}") String upstreamUrl) {
        this.restClient = restClient;
        this.upstreamUrl = upstreamUrl;
    }

    @Override
    @CircuitBreaker(name = COMPONENT_NAME, fallbackMethod = "fallbackProcess")
    @Retry(name = COMPONENT_NAME)
    @TimeLimiter(name = COMPONENT_NAME)
    public CompletableFuture<Optional<String>> processTransaction(String payload, String idempotencyKey) {
        // We use CompletableFuture to support TimeLimiter, which requires async execution

        log.info("Initiating external integration call with Idempotency-Key: {}", idempotencyKey);

        // OpenTelemetry trace propagation is handled automatically by RestClient
        String response = restClient.post()
                .uri(upstreamUrl)
                .header("Idempotency-Key", idempotencyKey) // Key Idempotency Support
                .body(payload)
                .retrieve()
                .body(String.class);

        log.info("Successfully processed integration call for key: {}", idempotencyKey);
        return CompletableFuture.completedFuture(Optional.ofNullable(response));
    }

    /**
     * Fallback method executed if the Circuit Breaker is OPEN,
     * retries are exhausted, or the TimeLimiter times out.
     */
    public CompletableFuture<Optional<String>> fallbackProcess(String payload, String idempotencyKey, Throwable t) {
        log.error("Integration failed for Idempotency-Key: {} after retries/circuit breaker. Reason: {}",
                idempotencyKey, t.getMessage());

        // Return empty or queue to a Dead Letter Queue (DLQ) depending on business requirements
        return CompletableFuture.completedFuture(Optional.empty());
    }
}
