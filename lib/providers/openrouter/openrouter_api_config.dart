/// OpenRouter chat-completions configuration. The free router selects from
/// currently available free models; availability and quotas can change.
class OpenRouterApiConfig {
  const OpenRouterApiConfig({
    this.model = 'openrouter/free',
    this.endpoint = 'https://openrouter.ai/api/v1/chat/completions',
    this.siteUrl = 'https://omni-ai.app',
    this.appName = 'OMNI AI',
  });

  final String model;
  final String endpoint;
  final String siteUrl;
  final String appName;
}
