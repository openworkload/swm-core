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
