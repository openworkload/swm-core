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

### Create a new resource group:
```bash
az group create --name devRG --location eastus
```

### Add a new service principal:
```bash
az ad sp create-for-rbac --name devSP --role Contributor --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/devRG --cert @/opt/swm/spool/secure/cluster/cert.pem
```

### The certificate can be replaced for existing service principal:
```bash
az ad sp credential reset --id $RESOURCE_GROUP_ID --append --cert @/opt/swm/spool/secure/cluster/cert.pem
```

## Delete a service principal

### Delete a resource group:
```bash
az group delete --name devRG
```

### Delete a service principal:
```bash
az ad sp delete --id $SERVICE_PRINCIPAL_ID
```
