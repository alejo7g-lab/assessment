package com.company.assessment.infrastructure.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration
public class ObservabilityConfig {

    @Bean
    public RestClient restClient(RestClient.Builder builder) {
        // By injecting the RestClient.Builder, Spring automatically configures it
        // with the Micrometer OpenTelemetry interceptors for trace propagation.
        return builder.build();
    }
}
