# Get Bicep Deployments

This action assists in determining which Bicep deployments should be deployed based on conditions like the Github event, modified files, regex and environment filters and the `deploymentconfig.json` or `deploymentconfig.jsonc` configuration file.

<!-- TOC -->

- [Get Bicep Deployments](#get-bicep-deployments)
  - [How to use this action](#how-to-use-this-action)
  - [Parameters](#parameters)
    - [`deployments-root-directory`](#deployments-root-directory)
    - [`event-name`](#event-name)
    - [`environment`](#environment)
    - [`environment-pattern`](#environment-pattern)
    - [`pattern`](#pattern)
  - [Outputs:](#outputs)
    - [Schema](#schema)
      - [`deployments`](#deployments)
    - [Example output](#example-output)
  - [Examples:](#examples)
    - [Single deployment](#single-deployment)
    - [Multi-deployments](#multi-deployments)

<!-- /TOC -->

## How to use this action

This action can be used multiple ways.

- Single deployments
- Part of a dynamic, multi-deployment strategy using the `matrix` capabilities in Github.

Both these approaches can be adjusted using the filter capabilities of the action.

It requires the repository to be checked out before use.

It is called as a step like this:

```yaml
# ...
steps:
  - name: Checkout repository
    uses: actions/checkout@v4

  - name: Get Bicep Deployments
    id: get-bicep-deployments
    uses: climpr/get-bicep-deployments@v1
    with:
      deployments-root-directory: deployments
# ...
```

## Parameters

### `deployments-root-directory`

The root directory in which deployments are located.

> NOTE: It needs to be a directory at least one level above the deployment directory. I.e. `deployments` if the desired deployment is the following: `deployments/sample-deployment/prod.bicepparam`.

### `event-name`

The Github event name that triggers the workflow. This decides the primary logic for which deployments to include.
Supported events are: `push`, `schedule`, `pull_request_target` and `workflow_dispatch`.

- `push`: Only includes deployments if any related files are modified in the commit.
- `schedule`: Includes all deployments.
- `pull_request_target`: Only includes deployments if any related files are modified in the pull request.
- `workflow_dispatch`: Manual trigger. Includes all deployments by default, but requires filters.

### `environment`

If this parameter is specified, only deployments matching the specified environment is included.

> NOTE: The environment is calculated from the first dot delimited element in the `.bicepparam` file name. I.e. `prod` in `prod.bicepparam` or `prod.main.bicepparam`.

### `environment-pattern`

If this parameter is specified, only deployments matching the specified environment regex pattern is included.

> NOTE: The environment is calculated from the first dot delimited element in the `.bicepparam` file name. I.e. `prod` in `prod.bicepparam` or `prod.main.bicepparam`.

### `pattern`

If this parameter is specified, only the deployments matching the specified regex pattern is included.

> NOTE: This pattern is matched against the deployment **directory**. I.e. `sample-deployment` in the following directory structure: `deployments/sample-deployment/prod.bicepparam`.

## Outputs

### Schema

#### `deployments`

```jsonc
[
  {
    "Name": string, // Name of the deployment (Directory name)
    "Environment": string, // Name of the environment (from the .bicepparam or .bicep file name)
    "DeploymentFile": string, // Full path to the .bicepparam or .bicep file used for deployment
    "ParameterFile": string?, // Full path to the .bicepparam file used for deployment (if any)
    "References": string[], // List of all files referenced by the deployment (including the deployment file itself)
    "Deploy": boolean, // Whether this deployment should be deployed or not
    "Modified": boolean // Whether any of the referenced files are modified in the triggering commit/pull request
  }
]
```

### Example output

```jsonc
[
  {
    "Name": "sample-deployment",
    "Environment": "prod",
    "DeploymentFile": "/home/runner/work/bi-az-banner-online/bi-az-banner-online/bicep-deployments/sample-deployment/prod.bicepparam",
    "ParameterFile": "/home/runner/work/bi-az-banner-online/bi-az-banner-online/bicep-deployments/sample-deployment/prod.bicepparam",
    "References": [
      "./bicep-deployments/sample-deployment/modules/sample-submodule/main.bicep",
      "./bicep-deployments/sample-deployment/main.bicep",
      "./bicep-deployments/sample-deployment/prod.bicepparam"
    ],
    "Deploy": true,
    "Modified": false
  }
]
```

## Examples

### Single deployment

```yaml
# .github/workflows/deploy-sample-deployment.yaml
name: Deploy sample-deployment

on:
  workflow_dispatch:

  schedule:
    - cron: 0 23 * * *

  push:
    branches:
      - main
    paths:
      - deployments/sample-deployment/prod.bicepparam

jobs:
  deploy-bicep:
    name: "Deploy sample-deployment to prod"
    runs-on: ubuntu-latest
    environment:
      name: prod
    permissions:
      id-token: write # Required for the OIDC Login
      contents: read # Required for repo checkout

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Azure login via OIDC
        uses: azure/login@v2
        with:
          client-id: ${{ vars.APP_ID }}
          tenant-id: ${{ vars.TENANT_ID }}
          subscription-id: ${{ vars.SUBSCRIPTION_ID }}

      - name: Get Bicep Deployments
        id: get-bicep-deployments
        uses: climpr/get-bicep-deployments@v1
        with:
          deployments-root-directory: deployments
          pattern: sample-deployment

      - name: Run Bicep deployments
        id: deploy-bicep
        uses: climpr/deploy-bicep@v1
        with:
          parameter-file-path: deployments/sample-deployment/prod.bicepparam
```

### Multi-deployments

```yaml
# .github/workflows/deploy-bicep-deployments.yaml
name: Deploy Bicep deployments

on:
  schedule:
    - cron: 0 23 * * *

  push:
    branches:
      - main
    paths:
      - "**/deployments/**"

  workflow_dispatch:
    inputs:
      environment:
        type: environment
        description: Filter which environment to deploy to
      pattern:
        description: Filter deployments based on regex pattern. Matches against the deployment name (Directory name)
        required: false
        default: .*

jobs:
  get-bicep-deployments:
    runs-on: ubuntu-latest
    permissions:
      contents: read # Required for repo checkout

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Get Bicep Deployments
        id: get-bicep-deployments
        uses: climpr/get-bicep-deployments@v1
        with:
          deployments-root-directory: deployment-manager/deployments
          event-name: ${{ github.event_name }}
          pattern: ${{ github.event.inputs.pattern }}
          environment: ${{ github.event.inputs.environment }}

    outputs:
      deployments: ${{ steps.get-bicep-deployments.outputs.deployments }}

  deploy-bicep-parallel:
    name: "[${{ matrix.Name }}][${{ matrix.Environment }}] Deploy"
    if: "${{ needs.get-bicep-deployments.outputs.deployments != '' && needs.get-bicep-deployments.outputs.deployments != '[]' }}"
    runs-on: ubuntu-latest
    needs:
      - get-bicep-deployments
    strategy:
      matrix:
        include: ${{ fromjson(needs.get-bicep-deployments.outputs.deployments) }}
      max-parallel: 10
      fail-fast: false
    environment:
      name: ${{ matrix.Environment }}
    permissions:
      id-token: write # Required for the OIDC Login
      contents: read # Required for repo checkout

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Azure login via OIDC
        uses: azure/login@v2
        with:
          client-id: ${{ vars.APP_ID }}
          tenant-id: ${{ vars.TENANT_ID }}
          subscription-id: ${{ vars.SUBSCRIPTION_ID }}

      - name: Run Bicep deployments
        id: deploy-bicep
        uses: climpr/deploy-bicep@v1
        with:
          parameter-file-path: ${{ matrix.ParameterFile }}
          what-if: "false"
```
