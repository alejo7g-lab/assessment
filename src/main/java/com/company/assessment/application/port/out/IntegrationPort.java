package com.company.assessment.application.port.out;

import java.util.Optional;
import java.util.concurrent.CompletableFuture;

public interface IntegrationPort {
    /**
     * Processes a transaction via an external system, utilizing idempotency keys.
     *
     * @param payload        The transaction payload.
     * @param idempotencyKey A unique key to ensure idempotency.
     * @return An Optional containing the response string, or empty if it fails and falls back.
     */
    CompletableFuture<Optional<String>> processTransaction(String payload, String idempotencyKey);
}
