@echo off
:: Azure CLI script to provision the eight Azure resources needed for
:: the sample. The resources are numbered in parenthases.

:: Sign in to Azure

echo Running az login; a browser window will open

call az login

:: Create an AZURE_SUBSCRIPTION_ID environment variable using the subscription
:: of the signed-in user. To use a specific subscription, replace this
:: command with set AZURE_SUBSCRIPTION_ID=<id> as needed.

for /f %%i in ('az account show --query id --output tsv') do set AZURE_SUBSCRIPTION_ID=%%i

:: Set an Azure location to use: note that not all services are available in
:: all regions.

set AZURE_LOCATION=centralus

:: Setup: Create environment variables to use as resource names

:: First, the resource group, which need be unique only within your
:: subscription.

set SCENARIO_RG=auth-scenario-rg

:: Many resource names must be unique across Azure. To ensure uniqueness,
:: set the PREFIX environment variable to something like your name or
:: company name, whatever value is likely to be unique. If that variable
:: is not defined, then this script creates the environment variable using
:: a random number.

IF "%PREFIX%"=="" set PREFIX=%RANDOM%

:: Names that must be unique across Azure and thus use the prefix. For
:: Key Vault, names must begin with a letter so we use the prefix instead
:: as a suffix.
set MAIN_APP_NAME=%PREFIX%-main-app
set THIRD_PARTY_API_APP_NAME=%PREFIX%-third-party-api
set KEY_VAULT_NAME=key-vault-%PREFIX%

:: App-related resources that typically use named derived from the app
:: name, often dropping hyphens where not allowed (as with storage
:: accounts). The syntax :-= in a few of these commands does a character
:: substitution on - for no character (nothing following the =). It's
:: the same as in Python with replace('-', '').

set MAIN_APP_PLAN_NAME=%MAIN_APP_NAME%-plan
set MAIN_APP_STORAGE_NAME=%MAIN_APP_NAME:-=%
set THIRD_PARTY_API_STORAGE_NAME=%THIRD_PARTY_API_APP_NAME:-=%

:: Object names used within some of the Azure resources. The third-party
:: API key is the kind of value you'd get through an app registration for
:: the API provider. The queue name is internal to the main app.

set THIRD_PARTY_API_SECRET_NAME=third-party-api-key
set THIRD_PARTY_API_SECRET_VALUE=d0c5atM1cr0s0ft
set STORAGE_QUEUE_NAME=code-requests

:: We're now ready to provision resources.

:: Part 1: Provision a containing resource group (1) for all the other
:: resources. When you're done using this sample, you can just delete
:: the resource group to delete all the resources within it to avoid
:: incurring any ongoing charges.

echo Provisioning resource group %SCENARIO_RG%

call az group create --name %SCENARIO_RG% --location %AZURE_LOCATION%


:: Part 2: Deploy the third-party API to Azure Functions.

:: First, provision the necessary Azure Storage account (2).

echo Provisioning storage account %THIRD_PARTY_API_STORAGE_NAME%

call az storage account create --name %THIRD_PARTY_API_STORAGE_NAME% --location %AZURE_LOCATION% --resource-group %SCENARIO_RG% --sku Standard_LRS

:: Next, provision an Azure Functions app (3) with a backing consumption
:: plan (4), then deploy the code in the third_party_api_folder.
:: 
:: Reference:
:: https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-first-azure-function-azure-cli?tabs=bash%2Cbrowser&pivots=programming-language-python

echo Provisioning Azure Functions app %THIRD_PARTY_API_APP_NAME%

call az functionapp create --resource-group %SCENARIO_RG% --os-type Linux --consumption-plan-location %AZURE_LOCATION% --runtime python --runtime-version 3.7 --functions-version 2 --name %THIRD_PARTY_API_APP_NAME% --storage-account %THIRD_PARTY_API_STORAGE_NAME%

echo Waiting 60 seconds for Functions app to complete, then deploying third-party API app code

timeout 60

cd ../third_party_api
call func azure functionapp publish %THIRD_PARTY_API_APP_NAME%
cd ../scripts

:: Set a function-level access key to secure the endpoint. This action
:: must be done directly through an HTTP request, as neither the Azure CLI
:: nor Azure Functions Core Tools currently support this capability. We
:: use the Azure CLI az rest command for this purpose along with the
:: Azure Functions Key Management REST API.
::
:: References:
:: https://docs.microsoft.com/cli/azure/reference-index?view=azure-cli-latest#az-rest
:: https://github.com/Azure/azure-functions-host/wiki/Key-management-API

:: This first command retrieves the _master key from the Functions app and
:: stores it in  an environment variable AZURE_FUNCTIONS_APP_KEY, which can
:: then be used in further HTTP requests to set the function-level access key.

echo Retrieving master access key for the Azure Functions app

for /f %%i in ('az rest --method post --uri "/subscriptions/%AZURE_SUBSCRIPTION_ID%/resourceGroups/%SCENARIO_RG%/providers/Microsoft.Web/sites/%THIRD_PARTY_API_APP_NAME%/host/default/listKeys?api-version=2018-11-01" --query masterKey --output tsv') do set AZURE_FUNCTIONS_APP_KEY=%%i

:: Now use the Functions key management to set the function-level access key.
:: When deployed, the function has a default key, but we want to demonstrate
:: setting a specific API key as would happen with individual client app
:: registrations.

echo Setting function key %THIRD_PARTY_API_SECRET_NAME% to value %THIRD_PARTY_API_SECRET_VALUE%

call az rest --method put --uri "https://%THIRD_PARTY_API_APP_NAME%.azurewebsites.net/admin/functions/RandomNumber/keys/%THIRD_PARTY_API_SECRET_NAME%?code=%AZURE_FUNCTIONS_APP_KEY%" --body "{\"name\": \"%THIRD_PARTY_API_SECRET_NAME%\", \"value\":\"%THIRD_PARTY_API_SECRET_VALUE%\"}"

:: You can use the following command to retrieve the key from Azure
:: Functions, if desired: call az rest --method get --uri "https://%THIRD_PARTY_API_APP_NAME%.azurewebsites.net/admin/functions/RandomNumber/keys/%THIRD_PARTY_API_SECRET_NAME%?code=%AZURE_FUNCTIONS_APP_KEY%" --query value --output tsv


:: Part 3: Deploy the main app to Azure App Service.
::
:: This step is done prior to setting up the third-party API key in Azure
:: Key Vault because we need the app's managed identity name to set a
:: role permissions in Key Vault.
::
:: call az webapp up creates the App Service plan (5) and App Service
:: app (6), then deploys the code in the current folder.

echo Provisioning Azure App Service and deploying the main app

cd ../main_app

call az webapp up --name %MAIN_APP_NAME% --plan %MAIN_APP_PLAN_NAME% --sku B1 --resource-group %SCENARIO_RG% --location %AZURE_LOCATION%

:: Enable managed identity on the web app and save the object ID in an
:: environment variable named MAIN_APP_OBJECT_ID.
::
:: Reference: https://docs.microsoft.com/azure/app-service/overview-managed-identity?tabs=python#using-the-azure-cli

echo Retrieving the main app's object ID

for /f %%i in ('az webapp identity assign --name %MAIN_APP_NAME% --resource-group %SCENARIO_RG% --query principalId --output tsv') do set MAIN_APP_OBJECT_ID=%%i

:: Provision a storage account (7) for the main app and create a queue

echo Provisioning storage account %MAIN_APP_STORAGE_NAME% for main app

call az storage account create --name %MAIN_APP_STORAGE_NAME% --location %AZURE_LOCATION% --resource-group %SCENARIO_RG% --sku Standard_LRS

:: Retreive the connection string for the storage account and save it 
:: to an environment variable MAIN_APP_STORAGE_CONN_STRING.

echo Retrieving storage account connection string

for /f %%i in ('az storage account show-connection-string --resource-group %SCENARIO_RG% --name %MAIN_APP_STORAGE_NAME% --query connectionString --output tsv') do set MAIN_APP_STORAGE_CONN_STRING=%%i

:: Create a queue within the storage account

echo Creating the storage queue %STORAGE_QUEUE_NAME% in the main app storage account

call az storage queue create --name %STORAGE_QUEUE_NAME% --account-name %MAIN_APP_STORAGE_NAME% --connection-string %MAIN_APP_STORAGE_CONN_STRING%

:: Set a Storage Queue Data Contributor role for the web app so it can
:: write to queues in the storage account. Because of managed identity,
:: the app identity is just the app name.
::
:: References:
:: https://docs.microsoft.com/azure/developer/python/how-to-assign-role-permissions
:: https://docs.microsoft.com/azure/role-based-access-control/built-in-roles#storage-queue-data-contributor

echo Assigning Storage Queue Data Contributor role to main web app

call az role assignment create --assignee %MAIN_APP_OBJECT_ID% --role "Storage Queue Data Contributor" --scope "/subscriptions/%AZURE_SUBSCRIPTION_ID%/resourceGroups/%SCENARIO_RG%/providers/Microsoft.Storage/storageAccounts/%MAIN_APP_STORAGE_NAME%/queueServices/default/queues/%STORAGE_QUEUE_NAME%"

:: Create application settings for the environment variables expected
:: in the main app. We already have THIRD_PARTY_API_SECRET_NAME; the other
:: URLs we need can be derived from the names of the third-party API, the
:: storage queue name, and the Key Vault name. Alternately, we can retrieve
:: those URLs via the Azure CLI (which, for Key Vault, we'd) need to do
:: after provisioning that resource.

echo Creating app settings for the main web app

call az webapp config appsettings set --name %MAIN_APP_NAME% --resource-group %SCENARIO_RG% --settings KEY_VAULT_URL="https://%KEY_VAULT_NAME%.vault.azure.net/" THIRD_PARTY_API_ENDPOINT="https://%THIRD_PARTY_API_APP_NAME%.azurewebsites.net/api/RandomNumber" THIRD_PARTY_API_SECRET_NAME="%THIRD_PARTY_API_SECRET_NAME%" STORAGE_QUEUE_URL="https://%MAIN_APP_STORAGE_NAME%.queue.core.windows.net/%STORAGE_QUEUE_NAME%"

cd ../scripts


:: Provision an Azure Key Vault (8) and store the third-party API access
:: key as a Key Vault "secret".
::
:: Reference: https://docs.microsoft.com/azure/key-vault/secrets/quick-create-cli

echo Provisioning Azure Key Vault %KEY_VAULT_NAME%

call az keyvault create --name %KEY_VAULT_NAME% --resource-group %SCENARIO_RG% --location %AZURE_LOCATION%

echo Setting secret %THIRD_PARTY_API_SECRET_NAME% to value %THIRD_PARTY_API_SECRET_VALUE%   

call az keyvault secret set --vault-name %KEY_VAULT_NAME% --name %THIRD_PARTY_API_SECRET_NAME% --value %THIRD_PARTY_API_SECRET_VALUE%

:: You can use the following command to retrieve the secret's value to
:: verify: call az keyvault secret show --vault-name %KEY_VAULT_NAME% --name %THIRD_PARTY_API_SECRET_NAME% --query value --output tsv

:: Set an access policy for the app with Key Vault to read secrets.
:: Note that Key Vault uses role permissions only for management
:: activities; access to stored values are controlled through access policies.
::
:: References:
:: https://docs.microsoft.com/azure/key-vault/general/secure-your-key-vault#data-plane-and-access-policies
:: https://docs.microsoft.com/cli/azure/keyvault?view=azure-cli-latest#az-keyvault-set-policy

call az keyvault set-policy --name %KEY_VAULT_NAME% --object-id %MAIN_APP_OBJECT_ID% --resource-group %SCENARIO_RG% --secret-permissions get

:: At the end of this script, you should have:
:: (1) a resource group containing:
:: (2) a storage account for the third-party API
:: (3) an App Service plan for the third-party API Functions app
:: (4) an App Service instance for the third-party API Functions app
:: (5) an App Service plan for the main app
:: (6) an App Service instance for the main app with appropriate settings 
::     for expected environment variables (e.g. resources URLs).
:: (7) a storage account for the main app that contains a queue named
::     "code-requests"
:: (8) a Key Vault that contains a secret named "third-party-api-key"
::     with value "d0c5atM1cr0s0ft".
::
:: The main app is authorized to write to storage queues in its storage
:: account by virtue of a role assignment, and authorized to read secrets
:: from Key Vault by virtue of a Key Vault access policy.
::
:: You can now use the test.cmd script to invoke the API endpoint and
:: then retrieve the queue message that the endpoint generated.

echo Press any key to test the deployment by running test.cmd.
echo It takes a few moments for the app to start.

pause

call test.cmd

echo Feel free to run test.cmd again, which is now faster. If you wait a few minutes, however, the message index resets. In that case, remove all messages from the queue with the `az storage message clear` command, or use the Azure portal to clear the queue.

:: az storage message get --connection-string %MAIN_APP_STORAGE_CONN_STRING% --queue-name %STORAGE_QUEUE_NAME%
