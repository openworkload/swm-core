Sky Port Azure Integration
==========================

# Prepare credentials.json

Copy template priv/examples/credentials.json to directory $HOME/.swm and fill azure section:
* subscriptionid: Azure subscription ID,
* tenantid: Azure tenant ID,
* appid: Azure application ID,
* usersshcert: public user ssh certificate content (generated manually on a user host).

The following parameters are optional and needed in case if user jobs will pull container images from a registry that requires credentials.
* containerregistryuser: container registry user name,
* containerregistrypass: container registry password or token.


# Prepare your Azure account

## Create a service principal

In a subscription, you must have User Access Administrator
or Role Based Access Control Administrator permissions, or
higher, to create a service principal.

### Login to Azure:
```bash
az login
```

### Add a new service principal (application will be created with the same name):
```bash
az ad sp create-for-rbac --name swmSP --role Contributor --scopes /subscriptions/$SUBSCRIPTION_ID --cert @/opt/swm/spool/secure/node/cert.pem
```

### Get the service principal application id:
```bash
az ad sp list --display-name swmSP --query "[].appId" --output tsv
```

### Update the service principal application with a new certificate:
```bash
az ad app credential reset --id <app-id> --cert @/opt/swm/spool/secure/node/cert.pem
```

## Upload container image to Azure

### Create container registry
```bash
az group create --name containerImages --location eastus
az acr create --resource-group containerImages --name swmregistry --sku Basic
```

### Create access token:
```bash
az acr token create --name swmpull --registry swmregistry --scope-map _repositories_pull
```
Save the token name and returned password in ACR_TONE_NAME and ACR_TOKEN_PASSWORD parameters of your ~/.swm/credentials.json

### Upload container image to the Azure registry
```bash
az acr login --name swmregistry
docker pull quay.io/jupyter/pytorch-notebook:cuda12-hub-5.2.1
docker tag quay.io/jupyter/pytorch-notebook:cuda12-hub-5.2.1 swmregistry.azurecr.io/jupyter/pytorch-notebook:cuda12-hub-5.2.1
docker push swmregistry.azurecr.io/jupyter/pytorch-notebook:cuda12-hub-5.2.1
```

### List uploaded container images in the Azure repository:
```bash
az acr repository list --name swmregistry
az acr repository show-tags --name swmregistry --repository jupyter/pytorch-notebook
```

### Delete container image from the Azure repository:
```bash
az acr repository delete --name swmregistry --image jupyter/pytorch-notebook:cuda12-hub-5.2.1
```

## Save credentials locally

Copy credentials template file priv/examples/credentials.json to ~/.swm/credentials.json and
fill values in "azure" section.

Mandatory parameters (used in all calls to Azure API):

* subscriptionid: ID of your Azure subscription that will be used to create resources,
* tenantid: your Azure tenant ID,
* appid: your Azure application ID.

Optional container registry (that stores job containers) authentication parameters:
* containerregistryuser: user name,
* containerregistrypass: password or token.


# Troubleshooting

## Get authentication information

If you later need tenant and subscription IDs, then the following command can be used:
```bash
az account list
```
where id in the output will show the id.

To get application ID the following command can be used
```bash
az ad app list
```

To get resource group ID:
```bash
az group show --name swm-09ccc5c0-resource-group --query id --output tsv
```

List deployed resources in the resource group:
```bash
az resource list --resource-group swm-09ccc5c0-resource-group
```

## Register namespace
If deployment creation fails with error like "Microsoft.Network namespace is not registered",
then the following actions can be performed (for each namespace).
```bash
az provider list --query "[?namespace=='Microsoft.Network']" --output table
az provider register --namespace Microsoft.Network
```
