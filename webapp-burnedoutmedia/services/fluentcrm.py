import os
import requests
import base64
from typing import Dict, Any

from config import settings

class FluentCRMService:
    def __init__(self):
        self.api_url = settings.FLUENTCRM_API_URL
        self.username = settings.WP_APP_USERNAME
        self.password = settings.WP_APP_PASSWORD

    def _get_auth_header(self) -> str:
        credentials = f"{self.username}:{self.password}"
        encoded_credentials = base64.b64encode(credentials.encode()).decode()
        return f"Basic {encoded_credentials}"

    def create_contact(self, first_name: str, last_name: str, email: str, phone: str, webinar: str) -> Dict[str, Any]:
        """
        Creates a contact in FluentCRM using WordPress Application Passwords.
        """
        url = f"{self.api_url}/subscribers"
        headers = {
            "Authorization": self._get_auth_header()
        }
        
        # FluentCRM expects form-encoded data, not JSON
        payload = {
            "first_name": first_name,
            "last_name": last_name,
            "email": email,
            "phone": phone,
            "status": "subscribed",
            "custom_values[webinar_choice]": webinar
        }

        # Catching and raising errors correctly based on WordPress API schema
        response = requests.post(url, data=payload, headers=headers)
        
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            # We print the response text for debugging
            print(f"FluentCRM HTTP Error: {response.status_code}")
            print(f"Response: {response.text}")
            raise e
