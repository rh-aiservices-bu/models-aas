# Models as a Service

## Deployment

### Model Serving

- In OpenShift, create projet `llm-hosting`.
- In the namespace YAML definition of the project, add the label `modelmesh-enabled: 'false'`
- In the project, create [OBC to RGW](./deployment/model_serving/obc-rgw.yaml).
- Switch to OpenShift AI dashboard and create a Data Connection `models` with the information from the OBC.
    ![add_data_connection.png](img/add_data_connection.png)
- In OpenShift AI, create and launch an ODH-TEC workbench using the data connection:
    ![odh-tec-1.png](img/odh-tec-1.png)
    ![odh-tec-2.png](img/odh-tec-2.png)
- Using ODH-TEC, import the following models from HuggingFace (don't forget to enter your HuggingFace Token in ODH-TEC Settings!):
  - [Granite-8B-Code-Instruct-128K](https://huggingface.co/ibm-granite/granite-8b-code-instruct-128k)
  - [Mistral-7B-Instruct-v0.3](https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3)
  - [Nomic-embed-text-v1.5](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5)
    ![import-granite-1.png](img/import-granite-1.png)
    ![import-granite-2.png](img/import-granite-2.png)
- From the OpenShift Console, deploy the different model servers using the following RuntimeConfigurations and InferenceServers:
  - [Granite-8B-Code-Instruct-128K](./deployment/model_serving/granite-code-vllm-raw.yaml)
  - [MisMistral-7B-Instruct-v0.3](./deployment/model_serving/mistral-vllm-raw.yaml)
  - [Nomic-embed-text-v1.5](./deployment/model_serving/nomic-embed-raw.yaml)

### Red Hat SSO

- Create the project `rh-sso`.
- Deploy the Red Hat Single Sign-On operator in the `rh-sso` namespace.
- Create a Keycloak instance using [keycloak.yaml](./deployment/rh-sso/keycloak.yaml).
- Create a `rhoai` KeycloakRealm using [keycloakrealm-maas.yaml](./deployment/rh-sso/keycloakrealm-maas.yaml).
- Open the Red Hat Single Sign-on console (route in the Routes section, access credentials in Secrets->`credentials-rh-sso`).
- Switch to the Rhoai realm:
    ![rhoai-realm.png](img/rhoai-realm.png)
- In the Clients section, create a new client named `3scale`, of type `openid-connect`:
    ![add-client.png](img/add-client.png)
- Adjust the following:
  - Access Type: `confidential`
  - Enable only Standard Flow, leave all other toggle to off.
  - For the moment, set Valid Redirect URLs to `*`.
  ![3scale_client.png](img/3scale_client.png)
  - From the Credentials section, take note of the Secret.
  - In the Mappers sections, create two new mappers:
    - Click on `Add Builtin`, select `email verified` and click on `Add selected`. You will end up with this mapping configuration:
    ![email_verified.png](img/email_verified.png)
    - Click on `Create`, enter Name `org_name`, Mapper Type `User Attribute`, User Attribute `email`, Token Claim Name `org_name`, Claim JSON type `string`, first 3 switches to on.
    ![org_name_mapper.png](img/org_name_mapper.png)
  - In this configuration, the organization name for a user will be the same as the user email. This is to achieve full separation of the accounts. Adjust to your likings.
- Create an IdentityProvider to connect your Realm to Red Hat authentication system. The important sections are `Trust Email` to enable, and set `Sync Mode` to import.
  ![google_identity_provider.png](img/google_identity_provider.png)

#### 3Scale

Requirements:

- OpenShift Data Foundation deployed to be able to create an RWX volume for 3Scale system storage.

Deployment:

- Create the project `3scale`.
- Open a Terminal and login to OpenShift.
- Switch to the folder [deployment/3scale/remove_bearer_policy](./deployment/3scale/remove_bearer_policy/) and run the following command:

    ```bash
    oc create secret generic cp-bearer \
        -n 3scale \
    --from-file=./apicast-policy.json \
    --from-file=./init.lua \
    --from-file=./remove-bearer.lua
    ```

- Deploy the Red Hat Integration-3scale operator in the `3scale` namespace only!
- Using the deployed operator, create an APIManager instance using [deployment/3scale/apimanager.yaml](./deployment/3scale/apimanager.yaml).
- Wait for all the Deployments (15) to finish.
- Create a Custom Policy Definition instance using [deployment/3scale/custom_policy_definition.yaml](./deployment/3scale/custom_policy_definition.yaml).

#### Configuration

Base configuration

- Open the 3Scale administration portal for the RHOAI provider. It will be the Route starting with `https://maas-admin-apps...`.
- The credentails are stored in the Secret `system-seed` (`ADMIN_USER` and `ADMIN_PASSWORD`).
- You will be greated by the Wizard that you can directly close:
    ![3scale-wizard-close.png](img/3scale-wizard-close.png).
- In the Account Settings sections (top menu):
  - In Overview, adjust the Account Details to your provider name and Timezone.
    ![account_details.png](img/account_details.png)

- Let's start by doing some cleanup:
  - In the `Products` section, click on the default `API` product:
    ![API-product-default.png](img/API-product-default.png)
  - In the top right, click on `edit`:
    ![API-product-default-edit.png](img/API-product-default-edit.png)
  - In the Backends section, delete the default `API Backend`:
        ![API-backend-default.png](img/API-backend-default.png)

Backends and Products

- We will start by adding the different `Backends` to our models:
  - In the `Backends` section, create a new one for Granite. The `Private Base URL` is the one from the Service exposed by the model:
    ![new-backend-granite.png](img/new-backend-granite.png)
  - Do the same for the other models/endpoints.
    ![all-backends.png](img/all-backends.png)
- We can now create the `Products`. There will be one for each Backend.
    ![all-products.png](img/all-products.png)
- For each product, apply the following configurations:
  - In `Integration->Settings`, change the `Auth user key` field content to `Authorization` and the `Credentials location` field to `As HTTP Headers` (click on `Update product` at the bottom to save):
    ![settings-authorization.png](img/settings-authorization.png)
  - Link the corresponding Backend
  - Add the Policies in this order:
    1. CORS Request Handling:
       1. ALLOW_HEADERS: `Authorization`, `Content-type`, `Accept`.
       2. allow_origine: *
       3. allow_credentials: checked
    2. Remove Bearer from Authorization Policy
    3. 3scale APIcast
  - Add the Methods and the corresponding Mapping Rules: create one pair for each API method/path.
    ![methods.png](img/methods.png)
  - From the Integration->Configuration menu, promote the configuration to staging then production.
  - Along the way you can cleanup the unwanted default Products and Backends.

Plans

- For each Product, from the Applications->Application Plans menu, create a new Application Plan.
  ![standard_application_plan.png](img/standard_application_plan.png)  
- Once created, leave the Default plan to "No plan selected" so that users can choose their services for their applications, and publish it:
  ![publish_plan.png](img/publish_plan.png)
- In Applications->Settings->Usage Rules, set the Default Plan to `Default`. This will allow the users to see the different available Products.
  ![service_plan_default.png](img/service_plan_default.png)

Portal configuration

- Switch to the Audience section from the top menu.
- In Developer Portal->Settings->Domains and Access, remove the Developer Portal Access Code.
- In Developer Portal->Settings->SSO Integrations, create a new SSO Integration: of type Red Hat Single Sign On.
  - Client: `3scale`
  - Client secret: ************
  - Realm: `https://keycloak-rh-sso.apps.prod.rhoai.rh-aiservices-bu.com/auth/realms/maas` (adjust to your cluster domain name).
  - `Published` ticked.
  - Once created, edit the RH-SSO to tick the checkbox `Always approve accounts...`
  ![3scale_sso.png](img/3scale_sso.png)
  - You can now test the authentication flow.

Portal content

- Go to Developer Portal->Content.
- From the [deployment/3scale/portal](./deployment/3scale/portal/) folder, apply all the modifications to the different pages and Publish them.
- The content of this folder is arranged following the same organization of the site.
- New Pages may have to be created with the type depending of the type of content (html, javascript, css), some others have only to be modified.
