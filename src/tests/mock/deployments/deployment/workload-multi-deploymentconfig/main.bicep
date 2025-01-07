targetScope = 'subscription'

module submodule '.bicep/submodule.bicep' = {
  name: '${deployment().name}-submodule'
}
