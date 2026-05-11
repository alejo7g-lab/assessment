# Technical Lead – Practical Assessment

**Objective**: Technical Assessment --> Technical Lead SuraTech

**Resources**: 
- `Technical_Assesstment.docx`
- `DEMO.md`
- `architecture_diagram.mmd`
- Project code assessment

## Architecture & Roadmap
- **Clean Architecture**: Utilizes Ports & Adapters pattern.
- **Tech Stack**: Spring Boot 3.5.14, Java 21, Maven-based project.
- **Integration**: External integration via outbound adapter and resilient HTTP client.
- **Observability**: Provided through OpenTelemetry and actuator metrics.
- **Deployment**: Local and Kubernetes deployment support.

## Reusable Integration Framework
- `IntegrationPort` defines the outbound contract.
- `ResilientIntegrationAdapter` implements circuit breaker, retry, and timeout strategies.
- Idempotency support via `Idempotency-Key` header.
- Adapter layer is isolated from core application logic.
- Configurable resilience properties and external URLs.

## Demo Service & Reliability Test
- Includes a simulated flaky upstream service.
- Demo mode controls failure rate and latency.
- Health endpoints and local Docker/Kubernetes deploy scripts are provided.
- Reliability observed via retries, fallback handling, and circuit breaker behavior.
- `deploy_local.cmd` and `deploy_kubernet.cmd` for local demo and Kubernetes execution.

## Technical Decision Record
- **Framework**: Chosen Spring Boot for rapid Java service development.
- **Resilience**: Used Resilience4j for reliable downstream calls.
- **Architecture**: Applied Clean Architecture to separate domain, adapter, and infrastructure.
- **Monitoring**: Added OTel for tracing and metrics, plus actuator health probes.