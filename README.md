# Get Bicep Deployments

This action assists in determining which Bicep deployments should be deployed based on conditions like the Github event, modified files, regex and environment filters and the `deploymentconfig.json` or `deploymentconfig.jsonc` configuration file.

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

### `pattern`
If this parameter is specified, only the deployments matching the specified regex pattern is included.
> NOTE: This pattern is matched against the deployment **directory**. I.e. `sample-deployment` in the following directory structure: `deployments/sample-deployment/prod.bicepparam`.

## Examples:

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
    runs-on: ubuntu-22.04
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
    runs-on: ubuntu-22.04
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
    runs-on: ubuntu-22.04
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
