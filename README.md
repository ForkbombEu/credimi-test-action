# forkbombeu/credimi-test-action

This action let you test your wallet, credential issuer or verifier with credimi pipelines.

# Usage
```yaml
- uses: forkbombeu/credimi-test-action@main
  with:
    # Credimi API key
    api-key: YOUR_USER_API_KEY

    # Credimi pipeline id to run
    pipeline-id: your-org/your-pipeline

    # Credimi runner id
    runner-id: your-org/your-runner

    # Path to local apk
    apk-file: path/to/local/app.apk

    # Url where to fetch apk
    apk-url: https://example.com/path/to/app.apk

    # Credimi API base URL
    # default: https://credimi.io
    api-base-url: https://credimi.io
```
