# Integrated security with Azure Active Directory and Key Vault

This sample accompanies the article [Integrated authentication for Python apps with Azure services](https://docs.microsoft.com/en-us/azure/developer/python/walkthrough-tutorial-authentication-01). The sample specifically contains the code described in the article along with Azure CLI scripts to provision the entire sample in your own Azure subscription.

- *main_app* contains a simple Flask main app code that's deployed to Azure App Service. The app has a main page that points to its own open API endpoint that generates a JSON response and writes a message to Azure Queue storage.

- *third_party_api* contains code that's deployed to Azure Functions to simulate a third-party REST API that's protected by an access key. The main app API endpoint calls this secured third-party API using the access key obtained from Azure Key Vault.

- *scripts* contains provisioning and test scripts using the Azure CLI as described in the next section.

## To provision the sample

1. Install the [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest)
1. Install the [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local?tabs=windows%2Ccsharp%2Cbash#v2)
1. Change to the `scripts` folder:

    ```bash
    cd scripts
    ```

1. Run the *provision.cmd* (Windows) or *provision.sh* (macOS/Linux) script. On macOS/Linux, run the script using `source` command to ensure that environment variables are set up in the current shell session.

    ```bash
    chmod +x provision.sh
    source ./provision.sh
    ```

1. The provisioning script runs *test.cmd* or *test.sh* at the end of the process to test the deployed sample. You can run *test.cmd* or test.sh again to repeat the test.
