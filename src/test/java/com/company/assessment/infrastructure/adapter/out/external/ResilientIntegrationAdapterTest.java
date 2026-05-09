package com.company.assessment.infrastructure.adapter.out.external;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class ResilientIntegrationAdapterTest {

    private static final String UPSTREAM_URL = "http://localhost:8080/upstream/process";

    @Mock
    private RestClient restClient;

    @Mock
    private RestClient.RequestBodyUriSpec requestBodyUriSpec;

    @Mock
    private RestClient.RequestBodySpec requestBodySpec;

    @Mock
    private RestClient.ResponseSpec responseSpec;

    private ResilientIntegrationAdapter adapter;

    @BeforeEach
    void setUp() {
        adapter = new ResilientIntegrationAdapter(restClient, UPSTREAM_URL);
    }

    /**
     * Configures the full RestClient fluent chain mock.
     * Called explicitly by tests that exercise processTransaction().
     */
    private void stubRestClientChain() {
        when(restClient.post()).thenReturn(requestBodyUriSpec);
        when(requestBodyUriSpec.uri(anyString())).thenReturn(requestBodySpec);
        // header(String, String...) — use varargs-safe matcher
        when(requestBodySpec.header(anyString(), any())).thenReturn(requestBodySpec);
        when(requestBodySpec.body(any(Object.class))).thenReturn(requestBodySpec);
        when(requestBodySpec.retrieve()).thenReturn(responseSpec);
    }

    @Test
    void processTransaction_Success_ReturnsResponse() {
        stubRestClientChain();
        when(responseSpec.body(String.class)).thenReturn("{\"status\":\"ok\"}");

        Optional<String> result = adapter.processTransaction("{\"data\":\"test\"}", "key-123").join();

        assertTrue(result.isPresent());
        assertEquals("{\"status\":\"ok\"}", result.get());
    }

    @Test
    void processTransaction_NullResponse_ReturnsEmptyOptional() {
        stubRestClientChain();
        when(responseSpec.body(String.class)).thenReturn(null);

        Optional<String> result = adapter.processTransaction("{\"data\":\"test\"}", "key-null").join();

        assertTrue(result.isEmpty());
    }

    @Test
    void processTransaction_SetsIdempotencyKeyHeader() {
        stubRestClientChain();
        when(responseSpec.body(String.class)).thenReturn("ok");

        adapter.processTransaction("{}", "unique-key-456").join();

        verify(requestBodySpec).header("Idempotency-Key", "unique-key-456");
    }

    @Test
    void processTransaction_CallsCorrectUri() {
        stubRestClientChain();
        when(responseSpec.body(String.class)).thenReturn("ok");

        adapter.processTransaction("{}", "key").join();

        verify(requestBodyUriSpec).uri(UPSTREAM_URL);
    }

    @Test
    void processTransaction_SendsPayloadAsBody() {
        stubRestClientChain();
        when(responseSpec.body(String.class)).thenReturn("ok");
        String payload = "{\"amount\":100}";

        adapter.processTransaction(payload, "key").join();

        verify(requestBodySpec).body(payload);
    }

    @Test
    void processTransaction_WhenExceptionThrown_Propagates() {
        stubRestClientChain();
        when(responseSpec.body(String.class)).thenThrow(new ResourceAccessException("Connection refused"));

        // Exception propagates synchronously before CompletableFuture is created
        assertThrows(ResourceAccessException.class,
                () -> adapter.processTransaction("{}", "key-err"));
    }

    @Test
    void fallbackProcess_ReturnsEmptyOptional() {
        // No RestClient stubbing needed — fallback doesn't use it
        RuntimeException cause = new RuntimeException("Service unavailable");

        Optional<String> result = adapter.fallbackProcess("{\"data\":\"test\"}", "key-fallback", cause).join();

        assertTrue(result.isEmpty());
    }
}