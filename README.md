# Credimi Test Action

Run [Credimi](https://github.com/ForkbombEu/credimi) pipelines from GitHub Actions to test wallets, credential issuers, and verifiers as part of your CI workflow.

This action starts a Credimi pipeline execution and passes GitHub workflow metadata to Credimi so runs can be traced back to the repository, workflow, commit, and pull request that triggered them.

## Why use it

Credimi helps teams validate identity and credential flows automatically instead of relying only on manual QA. You can use this action to:

- Run the same credential tests on every pull request or release build.
- Test mobile wallet APKs before they are distributed.
- Check issuer and verifier behavior against reusable Credimi pipelines.
- Keep CI failures tied to the exact commit and workflow run that produced them.

## Pull request comments

This action no longer writes comments on pull requests directly.

Pull request comments are handled by the **Credimi CI** GitHub App. Install it for your organization or a single repository from:

https://github.com/apps/credimi-ci/installations/new

After installation, Credimi CI can add the PR feedback for pipeline runs triggered by this action.

## Inputs

| Input | Required | Description |
| --- | --- | --- |
| `api-key` | Yes | Credimi API key. Store it as a GitHub Actions secret. |
| `pipeline-id` | Yes | Credimi pipeline identifier, for example `your-org/your-pipeline`. |
| `runner-id` | Yes | Credimi runner identifier, for example `your-org/your-runner`. |
| `apk-file` | No | Path to a locally built APK artifact in the workflow workspace. |
| `apk-url` | No | URL where Credimi can fetch the APK. |
| `api-base-url` | No | Credimi API base URL. Defaults to `https://credimi.io`. |

Exactly one of `apk-file` or `apk-url` must be provided.

## Usage

### Test a locally built APK

```yaml
name: Credimi tests

on:
  pull_request:
  push:
    branches: [main]

jobs:
  credimi:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Build your APK before running Credimi.
      # Replace this with your project build command.
      - run: ./gradlew assembleDebug

      - uses: forkbombeu/credimi-test-action@main
        with:
          api-key: ${{ secrets.CREDIMI_API_KEY }}
          pipeline-id: your-org/your-pipeline
          runner-id: your-org/your-runner
          apk-file: app/build/outputs/apk/debug/app-debug.apk
```

### Test an APK by URL

```yaml
name: Credimi tests

on:
  workflow_dispatch:

jobs:
  credimi:
    runs-on: ubuntu-latest
    steps:
      - uses: forkbombeu/credimi-test-action@main
        with:
          api-key: ${{ secrets.CREDIMI_API_KEY }}
          pipeline-id: your-org/your-pipeline
          runner-id: your-org/your-runner
          apk-url: https://example.com/path/to/app.apk
```

## Setup

1. Create or choose a Credimi pipeline and runner in Credimi.
2. Add your Credimi API key as a repository or organization secret named `CREDIMI_API_KEY`.
3. Add this action to the workflow that builds or publishes your APK.
4. Install the [Credimi CI GitHub App](https://github.com/apps/credimi-ci/installations/new) if you want Credimi results commented on pull requests.

## Permissions

The action does not require GitHub write permissions and does not use `GITHUB_TOKEN` to post comments. The Credimi CI GitHub App is responsible for pull request comments.

## More information

- Credimi project: https://github.com/ForkbombEu/credimi
- Credimi CI app installation: https://github.com/apps/credimi-ci/installations/new
