from flask import Flask, request, jsonify
import requests, random, string, os
from datetime import datetime
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential
from azure.storage.queue import QueueClient

app = Flask(__name__)
app.config["DEBUG"] = True

number_url = os.environ["THIRD_PARTY_API_ENDPOINT"]

# Authenticate with Azure. First, obtain the DefaultAzureCredential
credential = DefaultAzureCredential()

# Next, get the client for the Key Vault. You must have first enabled managed identity
# on the App Service for the credential to authenticate with Key Vault.
key_vault_url = os.environ["KEY_VAULT_URL"]
keyvault_client = SecretClient(vault_url=key_vault_url, credential=credential)

# Obtain the secret: for this step to work you must add the app's service principal to
# the key vault's access policies for secret management.
api_secret_name = os.environ["THIRD_PARTY_API_SECRET_NAME"]
vault_secret = keyvault_client.get_secret(api_secret_name)

# The "secret" from Key Vault is an object with multiple properties. The key we
# want for the third-party API is in the value property. 
access_key = vault_secret.value

# Set up the Storage queue client to which we write messages
queue_url = os.environ["STORAGE_QUEUE_URL"]
queue_client = QueueClient.from_queue_url(queue_url=queue_url, credential=credential)


@app.route('/', methods=['GET'])
def home():
    return f'Home page of the main app. Make a request to <a href="./api/v1/getcode">/api/v1/getcode</a>.'


def random_char(num):
       return ''.join(random.choice(string.ascii_letters) for x in range(num))


@app.route('/api/v1/getcode', methods=['GET'])
def get_code():
    headers = {
        'Content-Type': 'application/json',
        'x-functions-key': access_key
        }

    r = requests.get(url = number_url, headers = headers)
    
    if (r.status_code != 200):       
        return "Could not get you a code.", r.status_code

    data = r.json()
    chars1 = random_char(3)
    chars2 = random_char(3)
    code_value = f"{chars1}-{data['value']}-{chars2}"
    code = { "code": code_value, "timestamp" : str(datetime.utcnow()) }

    # Log a queue message with the code for, say, a process that invalidates
    # the code after a certain period of time.
    queue_client.send_message(code)

    return jsonify(code)


if __name__ == '__main__':
    app.run()
