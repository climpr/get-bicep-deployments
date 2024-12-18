targetScope = 'subscription'

module localSubmodule '.bicep/submodule.bicep' = {
  name: '${deployment().name}-submodule'
}

module remoteSubmodule 'br/public:avm/res/resources/resource-group:0.2.3' = {
  name: '${deployment().name}-rg'
  params: {
    name: 'resourceGroupName'
  }
}
