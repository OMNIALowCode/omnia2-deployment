# Migrate Accounts

## SYNOPSIS

This set of scripts is used to export an account and import it in another subscription of the OMNIA platform.  

## DESCRIPTION

The account migration process is based on 2 moments. First, you export the Data from the origin account and second, you import it to the destination account.
This is used with 2 scripts, import.ps1 and export.ps1.
The user should have access to the source and destination subscription.

### REQUIREMENTS

Be sure that:

    - you can access to the Sql Database from your current network
    
    - you have the Azure Powershell installed
    
    - you have the AzCopy (version 5.0.0.0) installed at:   %programfiles(x86)%\Microsoft SDKs\Azure\AzCopy
    
    - you have co-admin rights to the destination Resource Group
    
    - you are running powershell as Admin

------------------------------

# EXPORT.PS1
 
Before executing, you should be authenticated via Azure RM:

```powershell
Login-AzureRmAccount
```

## PARAMETERS

### tenant [text]

The tenant code (GUID).

### WebsiteName [text]

The full URL of the Azure website (https:\\xxx.azurewebsites.net format

### SubscriptionName [text]

The name of the Azure subscription (analogous to other -SubscriptionName in Azure Powershell

### ResourceGroupName [text]

The name of the Azure resource group (analogous to other -ResourceGroupName in Azure Powershell)

## EXAMPLES
### Export example


```powershell
.\export.ps1 -tenant A0000000-B111-C222-D333-E44444444444 -WebsiteName https:\\waomnia12345.azurewebsites.net -SubscriptionName omnia12345 -ResourceGroupName omnia12345
```
        
------------------------------


# IMPORT.PS1

Before executing, you should be authenticated via Azure RM:

```powershell
Login-AzureRmAccount
```
    
## PARAMETERS

### tenant [text]

The tenant code (GUID).

### WebsiteName [text]

The full URL of the Azure website (https:\\xxx.azurewebsites.net format

### SubscriptionName [text]

The name of the Azure subscription (analogous to other -SubscriptionName in Azure Powershell

### ResourceGroupName [text]

The name of the Azure resource group (analogous to other -ResourceGroupName in Azure Powershell)

### shortcode [text]

{The tenant short code, that will be created in the destination subscription}

### tenantname [text]

{The tenant name, that will be created in the destination subscription}

### maxNumberOfUsers [int] (Optional – Default value 10)

{The maximum number of users that can be created in the new account}

### subGroupCode [text] (Optional – Default value “DefaultSubGroup”)

{The Sub Group Code that the tenant will be part of. The sub group should already exists in the destination account}

### tenantAdmin [text]

{The user that will be created has the tenant Admin}

### tenantAdminPwd [text]

{The password for the user that will be created has the tenant Admin}

### oem [text]

{The code of the OEM the tenant will be part of. The oem should already exists in the destination account}

### master [text]

{An user with System Admin Role in the destination subscription}

### masterpwd [text]

{The password of the user with System Admin Role in the destination subscription}

## EXAMPLES

### Import example


```powershell
.\import.ps1 -tenant A0000000-B111-C222-D333-E44444444444 -WebsiteName https:\\waomnia12345.azurewebsites.net -SubscriptionName omnia12345 -ResourceGroupName omnia12345 -shortcode tenantshortcode -tenantname 'My Tenant Name' -maxNumberOfUsers 10 -subGroupCode DefaultSubGroup -tenantAdmin admin@admin.com -tenantAdminPwd Password0 -oem omnia -master admin@admin.com -masterpwd Password0
```
        
