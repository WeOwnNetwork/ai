import base64
from typing import Any, Dict, List, Optional

import requests

from config import settings


class FluentCartService:
    """
    Service class to interact with FluentCart API for customer creation, order processing, and checkout."""
    def __init__(self) -> None:
        self.api_url = settings.FLUENTCART_API_URL.rstrip("/") if settings.FLUENTCART_API_URL else ""
        self.username = settings.WP_APP_USERNAME
        self.password = settings.WP_APP_PASSWORD

    def _get_auth_header(self) -> str:
        credentials = f"{self.username}:{self.password}"
        encoded_credentials = base64.b64encode(credentials.encode()).decode()
        return f"Basic {encoded_credentials}"

    def _headers(self) -> Dict[str, str]:
        return {
            "Authorization": self._get_auth_header(),
            "Content-Type": "application/json",
        }

    def create_customer(self, payload: Dict[str, Any], mock: bool = False) -> Dict[str, Any]:
        if mock or not self.api_url:
            return {
                "success": True,
                "data": {
                    "id": payload.get("email", "demo-customer"),
                    **payload,
                },
                "message": "Mock FluentCart customer created",
            }

        response = requests.post(f"{self.api_url}/customers", json=payload, headers=self._headers())
        response.raise_for_status()
        return response.json()

    def create_order(self, payload: Dict[str, Any], mock: bool = False) -> Dict[str, Any]:
        if mock or not self.api_url:
            return {
                "success": True,
                "data": {
                    "id": f"demo-order-{payload.get('customer_id', 'unknown')}",
                    **payload,
                    "status": "created",
                },
                "message": "Mock FluentCart order created",
            }

        response = requests.post(f"{self.api_url}/orders", json=payload, headers=self._headers())
        response.raise_for_status()
        return response.json()

    def process_checkout(self, payload: Dict[str, Any], mock: bool = False) -> Dict[str, Any]:
        if mock or not self.api_url:
            return {
                "success": True,
                "data": {
                    "checkout_id": f"demo-checkout-{payload.get('customer', {}).get('email', 'unknown')}",
                    "payment_status": "paid",
                    **payload,
                },
                "message": "Mock FluentCart checkout processed",
            }

        response = requests.post(f"{self.api_url}/checkout/process", json=payload, headers=self._headers())
        response.raise_for_status()
        return response.json()

    def build_demo_checkout_payload(
        self,
        customer: Dict[str, Any],
        product_id: Optional[str] = None,
        quantity: int = 1,
    ) -> Dict[str, Any]:
        return {
            "customer": {
                "first_name": customer.get("first_name"),
                "last_name": customer.get("last_name"),
                "email": customer.get("email"),
                "phone": customer.get("phone", ""),
            },
            "items": [
                {
                    "product_id": product_id or settings.FLUENTCART_PRODUCT_ID or "demo-burnedoutadvisor-offer",
                    "quantity": quantity,
                }
            ],
            "meta": {
                "source": "demo-e2e",
                "campaign": customer.get("campaign", "#ZeroTo100"),
            },
        }
