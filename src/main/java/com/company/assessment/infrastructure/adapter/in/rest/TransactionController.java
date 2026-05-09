package com.company.assessment.infrastructure.adapter.in.rest;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.company.assessment.application.port.out.IntegrationPort;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@Slf4j
@RestController
@RequestMapping("/api/v1/transactions")
@RequiredArgsConstructor
public class TransactionController {

    private final IntegrationPort integrationPort;

    @PostMapping
    public ResponseEntity<Map<String, Object>> processTransaction(
            @RequestBody String payload,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey) {

        // Generate an idempotency key if none is provided
        String key = (idempotencyKey != null && !idempotencyKey.isBlank())
                ? idempotencyKey
                : UUID.randomUUID().toString();

        log.info("Received transaction request with Idempotency-Key: {}", key);

        Optional<String> result = integrationPort.processTransaction(payload, key).join();

        if (result.isPresent()) {
            return ResponseEntity.ok(Map.of(
                    "status", "SUCCESS",
                    "idempotencyKey", key,
                    "response", result.get()));
        } else {
            return ResponseEntity.ok(Map.of(
                    "status", "FALLBACK",
                    "idempotencyKey", key,
                    "message", "External service unavailable. Fallback activated."));
        }
    }
}
