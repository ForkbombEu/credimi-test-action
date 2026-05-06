<div align="center">
<h1>
  <img
    src="./images/credimi_logo.svg"
    alt="C"
    height="48"/>redimi Test Action
</h1>

### Run [Credimi](https://github.com/ForkbombEu/credimi) pipelines from GitHub Actions to test wallets as part of your CI workflow. <!-- omit in toc --> 
<!--, credential issuers, and verifiers-->
</div>

<br>

This action starts a Credimi pipeline execution and passes GitHub workflow metadata to Credimi so runs can be traced back to the repository, workflow, commit, and pull request that triggered them. It helps teams validate identity and credential flows automatically instead of relying only on manual QA. You can use this action to:
- Run the same credential tests on every pull request.
- Test mobile wallet APKs before they are distributed.
- Keep CI failures tied to the exact commit and workflow run that produced them.
<!--- Check issuer and verifier behavior against reusable Credimi pipelines.-->

<br>

---

<div id="toc">

### 🚩 Table of contents <!-- omit in toc -->

- [🏗️ Setup](#️-setup)
- [🎮 Usage](#-usage)
  - [📂 Test a locally built APK](#-test-a-locally-built-apk)
  - [🌐 Test an APK by URL](#-test-an-apk-by-url)
- [⌨️ Inputs](#️-inputs)
- [🗞️ More information](#️-more-information)

</div>

---
## 🏗️ Setup

Follow these steps:

1. Install the [Credimi CI GitHub App](https://github.com/apps/credimi-ci/installations/new) for your organization or a single repository to let Credimi add PR feedback for pipeline runs triggered by this action.
2. If you do not have an account on [Credimi](https://credimi.io), create one.
3. Create your [Credimi API key](https://credimi.io/my/profile/api-keys) and add it to GitHub as a repository or organization secret named `CREDIMI_API_KEY`.
4. Create or choose a [Credimi pipeline](https://credimi.io/my/pipelines) and a runner in Credimi.
5. Lastly use this action in a workflow that runs on PR. See the [next section](#-usage) for more information.

**[🔝 back to top](#toc)**

---
## 🎮 Usage

### 📂 Test a locally built APK

```yaml
name: Credimi tests

on:
  pull_request:
    branches: [main]

jobs:
  credimi:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

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

### 🌐 Test an APK by URL

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

**[🔝 back to top](#toc)**

---
## ⌨️ Inputs

| Input          | Required | Description                                                        |
| -------------- | -------- | ------------------------------------------------------------------ |
| `api-key`      | Yes      | Credimi API key. Store it as a GitHub Actions secret.              |
| `pipeline-id`  | Yes      | Credimi pipeline identifier, for example `your-org/your-pipeline`. |
| `runner-id`    | Yes      | Credimi runner identifier, for example `your-org/your-runner`.     |
| `apk-file`     | No       | Path to a locally built APK artifact in the workflow workspace.    |
| `apk-url`      | No       | URL where Credimi can fetch the APK.                               |
| `api-base-url` | No       | Credimi API base URL. Defaults to `https://credimi.io`.            |

Exactly one of `apk-file` or `apk-url` must be provided.

**[🔝 back to top](#toc)**

---
## 🗞️ More information

- Credimi project: https://github.com/ForkbombEu/credimi
- Credimi CI app installation: https://github.com/apps/credimi-ci/installations/new

**[🔝 back to top](#toc)**
