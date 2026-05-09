# Technical Lead – Practical Assessment

## Section A – Architecture & Roadmap
- Clean Architecture with Ports & Adapters.
- Spring Boot 3.5.14, Java 21, Maven-based project.
- External integration via outbound adapter and resilient HTTP client.
- Observability through OpenTelemetry and actuator metrics.
- Local and Kubernetes deployment support.

## Section B – Reusable Integration Framework
- `IntegrationPort` defines outbound contract.
- `ResilientIntegrationAdapter` implements circuit breaker, retry, and timeout.
- Idempotency support via `Idempotency-Key` header.
- Adapter layer isolated from core application logic.
- Configurable resilience properties and external URLs.

## Section C – Demo Service & Reliability Test
- Includes simulated flaky upstream service.
- Demo mode controls failure rate and latency.
- Health endpoints and local Docker/Kubernetes deploy scripts.
- Reliability observed via retries, fallback handling, and circuit breaker behavior.
- `deploy_local.cmd` and `deploy_kubernet.cmd` for local demo and Kubernetes.

## Section D – Technical Decision Record
- Chosen Spring Boot for rapid Java service development.
- Used Resilience4j for reliable downstream calls.
- Applied Clean Architecture to separate domain, adapter, and infrastructure.
- Added OTel for tracing and metrics, plus actuator health probes.
- Local Kubernetes script uses namespace `kube-node-lease` for sandbox testing.

## Project Contents Summary
This repository implements a Spring Boot service with a clean architecture structure, resilient outbound integration, and a demo flaky upstream. It includes Docker and Kubernetes support, local and AKS deployment scripts, observability configuration, and a reusable port/adapter integration pattern. Unit tests validate adapter behavior and resilience. The service is designed to run locally or in Kubernetes with health checks and reliability controls.