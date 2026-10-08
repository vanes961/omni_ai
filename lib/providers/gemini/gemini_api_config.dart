class GeminiApiConfig {
  const GeminiApiConfig({
    this.model = 'gemini-3.8-flash',
    this.endpoint =
        'https://generativelanguage.googleapis.com/v1beta/interactions',
  });

  final String model;
  final String endpoint;
}
