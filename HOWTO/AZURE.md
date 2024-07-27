Sky Port Azure Integration
==========================

# Prepare a new Azure account

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
az ad sp create-for-rbac --name swmSP --role Contributor --scopes /subscriptions/$SUBSCRIPTION_ID --cert @~/.swm/cert.pem
```

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

## Upload container image to Azure

### Create container registry
```bash
az group create --name contImagesRG --location eastus
az acr create --resource-group contImagesRG --name swmregistry --sku Basic
```

### Create access token:
```bash
az acr token create --name swmpull --registry swmregistry --scope-map _repositories_pull
```
Save the token name and returned password in ACR_TONE_NAME and ACR_TOKEN_PASSWORD parameters of your ~/.swm/azure.env

### Upload container image to the Azure registry
```bash
az acr login --name swmregistry
docker tag jupyter/datascience-notebook:hub-3.1.1 swmregistry.azurecr.io/jupyter/datascience-notebook:hub-3.1.1
```

### List uploaded container images in the Azure repository:
```bash
az acr repository list --name swmregistry
az acr repository show-tags --name swmregistry --repository  jupyter/datascience-notebook
```

### Delete container image from the Azure repository:
```bash
az acr repository delete --name swmregistry --image  jupyter/datascience-notebook:hub-3.1.1
```
