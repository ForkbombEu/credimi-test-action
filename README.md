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
  - [🔐 Credimi API key](#-credimi-api-key)
  - [🔗 Choose a pipeline](#-choose-a-pipeline)
- [🎮 Usage](#-usage)
  - [📂 Test a locally built APK](#-test-a-locally-built-apk)
  - [🌐 Test an APK by URL](#-test-an-apk-by-url)
- [⌨️ Inputs](#️-inputs)
- [🥷 Advanced usage](#-advanced-usage)
  - [👟 Choose a specific runner](#-choose-a-specific-runner)
  - [📡 Use a custom API base URL](#-use-a-custom-api-base-url)
- [🗞️ More information](#️-more-information)

</div>

---
## 🏗️ Setup

Follow these steps:

1. Install the [<span style="font-weight: 1000;">Credimi CI GitHub App<span>](https://github.com/apps/credimi-ci/installations/new).
2. Create your [Credimi API key](https://credimi.io/my/profile/api-keys) and add it to GitHub as a repository or organization secret named `CREDIMI_API_KEY`.
3. Create or choose a [Credimi pipeline](https://credimi.io/my/pipelines) and copy its identifier (formatted as `org/pipeline`).

### 🔐 Credimi API key

Log in to Credimi and visit the [Credimi API key page](https://credimi.io/my/profile/api-keys).
After you create a new key, save it in your GitHub organization or repository secrets under the name `CREDIMI_API_KEY`.

<div align=center>
<img src="./images/api_key.png" width=80% align=center/>
</div>

### 🔗 Choose a pipeline

Log in to Credimi and visit the [Credimi pipeline page](https://credimi.io/my/pipelines).
Find the pipeline you want to run in CI, then click the copy button next to its name.
This copies the pipeline identifier that you will use as the `pipeline-id` input.

<div align=center>
<img src="./images/pipeline.png" width=80% align=center/>
</div>

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
          runner-type: android_emulator | redroid | android_phone | ios_simulator
          apk-file: path/to/your/app.apk
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
          runner-type: android_emulator | redroid | android_phone | ios_simulator
          apk-url: https://example.com/path/to/app.apk
```

**[🔝 back to top](#toc)**

---
## ⌨️ Inputs

| Input          | Required | Description                                                        |
| -------------- | -------- | ------------------------------------------------------------------ |
| `api-key`      | Yes      | Credimi API key. Store it as a GitHub Actions secret.              |
| `pipeline-id`  | Yes      | Credimi pipeline identifier, for example `your-org/your-pipeline`. |
| `runner-type`  | Yes      | Credimi runner type. One of `android_emulator`, `redroid`, `android_phone`, `ios_simulator`. |
| `runner-id`    | No       | Credimi runner identifier, for example `your-org/your-runner`.     |
| `apk-file`     | No       | Path to a locally built APK artifact in the workflow workspace.    |
| `apk-url`      | No       | URL where Credimi can fetch the APK.                               |
| `api-base-url` | No       | Credimi API base URL. Defaults to `https://credimi.io`.            |

Exactly one of `apk-file` or `apk-url` must be provided.

**[🔝 back to top](#toc)**

---
## 🥷 Advanced usage

### 👟 Choose a specific runner

By default, Credimi selects an available runner that matches the requested `runner-type`. If you need to run the pipeline on a specific runner, pass its identifier with `runner-id`.

```yaml
- uses: forkbombeu/credimi-test-action@main
  with:
    api-key: ${{ secrets.CREDIMI_API_KEY }}
    pipeline-id: your-org/your-pipeline
    runner-type: android_phone
    runner-id: your-org/your-runner
    apk-url: https://example.com/path/to/app.apk
```

### 📡 Use a custom API base URL

The action sends requests to `https://credimi.io` by default. Use `api-base-url` only when you need to target another Credimi environment, such as a staging or self-hosted instance.

```yaml
- uses: forkbombeu/credimi-test-action@main
  with:
    api-key: ${{ secrets.CREDIMI_API_KEY }}
    pipeline-id: your-org/your-pipeline
    runner-type: android_emulator
    api-base-url: https://credimi.example.com
    apk-url: https://example.com/path/to/app.apk
```

**[🔝 back to top](#toc)**

---
## 🗞️ More information

- Credimi project: https://github.com/ForkbombEu/credimi
- Credimi CI app installation: https://github.com/apps/credimi-ci/installations/new

**[🔝 back to top](#toc)**
