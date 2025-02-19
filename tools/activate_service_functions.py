import os
import requests
import xmltodict
from dotenv import load_dotenv

load_dotenv()
backend_address = os.environ.get("BACKEND_ADDRESS")
access_token = os.environ.get("ACCESS_TOKEN")


def get_accounts():
    accounts = []
    page = 1
    while True:
        params = {"access_token": access_token, "page": page}
        headers = {"accept": "*/*"}
        api_url = f"{backend_address}/admin/api/accounts.xml"
        response = requests.get(api_url, params=params, headers=headers)
        batch = xmltodict.parse(response.content)
        if not accounts:
            accounts = batch
        else:
            if isinstance(batch['accounts']['account'], list):
                accounts['accounts']['account'].extend(batch['accounts']['account'])
            else:
                accounts['accounts']['account'].append(batch['accounts']['account'])

        if int(batch['accounts']['@total_pages'])==page:
            break
        
        page += 1

    return accounts

def get_services():
    params = {"access_token": access_token}
    headers = {"accept": "*/*"}
    api_url = f"{backend_address}/admin/api/services.xml"
    response = requests.get(api_url, params=params, headers=headers)
    services = xmltodict.parse(response.content)

    return services

def get_service_plans():
    params = {"access_token": access_token}
    headers = {"accept": "*/*"}
    api_url = f"{backend_address}/admin/api/application_plans.xml"
    response = requests.get(api_url, params=params, headers=headers)
    plans = xmltodict.parse(response.content)

    return plans

def get_service_plan_by_service_id(plans, service_id: int):
    plan_id = None
    for plan in plans["plans"]["plan"]:
        if int(plan["service_id"]) == service_id:
            plan_id = int(plan["id"])
            break

    return plan_id

def create_dummy_application(account_id: int, plan_id: int):
    payload = {
        "access_token": access_token,
        "plan_id": plan_id,
        "name": "dummy_application",
    }
    headers = {
        "accept": "*/*",
        "Content-Type": "application/x-www-form-urlencoded",
    }
    api_url = f"{backend_address}/admin/api/accounts/{account_id}/applications.xml"
    response = requests.post(api_url, data=payload, headers=headers)
    application = xmltodict.parse(response.content)
    application_id = application["application"]["id"]

    return application_id

def delete_application(account_id: int, application_id: int):
    params = {"access_token": access_token}
    headers = {"accept": "*/*"}
    api_url = f"{backend_address}/admin/api/accounts/{account_id}/applications/{application_id}.xml"
    response = requests.delete(api_url, params=params, headers=headers)

    return response
