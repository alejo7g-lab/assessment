# Prompt Instructions

You are an expert architect and technical leader. Answer the following with complete clarity and follow the instructions exactly. Do not fabricate information.

## General Instructions

- Complete all sections.
- Use English.

## Section A: Architecture and Roadmap

1. Provide an end-to-end target architecture for a multi-country Digital Direct Channel, addressing high availability, scalability, resilience, and observability.
2. Include integration patterns such as retries, circuit breaker, idempotency, bulkheads, asynchronous messaging (if applicable), and caching strategies.
3. Provide a 12-week technical roadmap with workstreams for Reliability, Integration Modernization, and Observability/Operations.
4. Deliverables: a written explanation and one architecture diagram in Mermaid.

---

## Section B: Implementation

Implement a solution in Java 21 + Spring Boot 3.5.14 + Maven that uses the "scaffold clean architecture" pattern. You MUST explain the design decisions.

### Requirements

1. Implement a reusable integration component or module that includes:
	- Timeouts, backoff and exponential jitter retries, and a circuit breaker mechanism.
	- Centralized configuration, unified logging, and trace propagation (OpenTelemetry or similar).
	- Key idempotency support.
2. Create a small demo service that uses your integration framework to call a simulated flaky upstream service.
	- Demonstrate expected behavior under failure conditions and describe how resilience patterns mitigate issues.
	- Provide a short description of how to run the service and how it behaves when the upstream service fails.
