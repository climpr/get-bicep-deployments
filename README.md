# Get Bicep Deployments

This action assists in determining which Bicep deployments should be deployed based on conditions like the Github event, modified files, regex and environment filters and the `deploymentconfig.json` or `deploymentconfig.jsonc` configuration file.

<!-- TOC -->

- [Get Bicep Deployments](#get-bicep-deployments)
    - [How to use this action](#how-to-use-this-action)
    - [Parameters](#parameters)
        - [deployments-root-directory](#deployments-root-directory)
        - [event-name](#event-name)
        - [environment](#environment)
        - [environment-pattern](#environment-pattern)
        - [pattern](#pattern)
    - [Outputs](#outputs)
        - [deployments](#deployments)
    - [Deployment Configuration](#deployment-configuration)
        - [Configuration File Example](#configuration-file-example)
        - [Common Properties](#common-properties)
            - [disabled boolean, optional](#disabled-boolean-optional)
            - [enabledOn array, optional](#enabledon-array-optional)
            - [disabledOn array, optional](#disabledon-array-optional)
        - [Precedence Order](#precedence-order)
    - [Examples](#examples)
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

```json
{
  "deployments": [<deployments>] // JSON array of deployments (see schema below)
}
```

### `deployments`

**Schema**

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

**Example**

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

## Deployment Configuration

The `deploymentconfig.json` or `deploymentconfig.jsonc` file controls deployment behavior. This file is placed in the deployment directory and allows you to:

- Disable/enable deployments globally
- Specify which GitHub events should enable or disable a deployment
- Configure deployment parameters and options

### Configuration File Example

```jsonc
{
  "location": "westeurope",
  "disabled": false,
  "enabledOn": ["workflow_dispatch", "schedule"],
  "disabledOn": ["pull_request_target"]
}
```

### Common Properties

#### `disabled` (boolean, optional)

When `true`, the deployment is excluded for all GitHub events. This takes **highest precedence** over all other settings.

```jsonc
{
  // Disable deployment
  "disabled": true
}
```

#### `enabledOn` (array, optional)

Specify the GitHub events on which this deployment will run. The deployment is **only** enabled when triggered by one of the listed events.

Supported events: `push`, `pull_request_target`, `schedule`, `workflow_dispatch`

**Common use case:** Manual deployments only

```jsonc
{
  // Only enable when manually triggered
  "enabledOn": ["workflow_dispatch"]
}
```

**Common use case:** Scheduled and manual deployments

```jsonc
{
  // Enable for scheduled and manual events
  "enabledOn": ["schedule", "workflow_dispatch"]
}
```

#### `disabledOn` (array, optional)

Specify the GitHub events on which this deployment will not run. This is useful when you want to skip deployment for specific events while allowing all others.

Supported events: `push`, `pull_request_target`, `schedule`, `workflow_dispatch`

**Common use case:** Disable on schedule only

```jsonc
{
  // Deploy on everything except schedule
  "disabledOn": ["schedule"]
}
```

**Common use case:** Disable deployment for both push and pull request events.

```jsonc
{
  // Disable for push and PR events
  "disabledOn": ["push", "pull_request_target"]
}
```

### Precedence Order

Disables are restrictive and always win. The following order determines if a deployment is enabled (checked top-to-bottom):

1. **`disabled: true` (global)** → The deployment is always disabled, regardless of any other settings.
2. **`disabledOn` specified** → The deployment is disabled if the current event is in the denylist.
3. **`enabledOn` specified** → The deployment is enabled **only** if the current event is in the `enabledOn` list; everything else is disabled.
4. **Default** → The deployment is enabled.

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
