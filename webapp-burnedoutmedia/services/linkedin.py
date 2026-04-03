"""
LinkedIn Lead Sync Service

Implements LinkedIn Marketing API (Lead Sync) for:
- OAuth 2.0 authentication
- Lead form retrieval
- Lead form response (leads) fetching
- Webhook handling for real-time lead notifications

API Reference: https://learn.microsoft.com/en-us/linkedin/marketing/lead-sync/leadsync
"""

import os
import requests
from typing import Dict, Any, List, Optional
from urllib.parse import urlencode
from config import settings


class LinkedInLeadSyncService:
    """
    Service for LinkedIn Lead Gen Form integration.
    
    Supports:
    - OAuth 2.0 authorization code flow
    - Retrieving lead forms by owner (organization or sponsored account)
    - Fetching lead form responses (leads)
    - Real-time webhook notifications
    
    Required OAuth scopes:
    - r_marketing_leadgen_automation
    - r_ads
    - r_organization_admin
    """
    
    API_BASE_URL = "https://api.linkedin.com/rest"
    AUTH_URL = "https://www.linkedin.com/oauth/v2/accessToken"
    AUTHORIZE_URL = "https://www.linkedin.com/oauth/v2/authorization"
    
    # Latest LinkedIn API version
    API_VERSION = "202401"
    
    def __init__(self):
        self.client_id = getattr(settings, 'LINKEDIN_CLIENT_ID', None)
        self.client_secret = getattr(settings, 'LINKEDIN_CLIENT_SECRET', None)
        self.redirect_uri = getattr(settings, 'LINKEDIN_REDIRECT_URI', None)
        self.access_token = getattr(settings, 'LINKEDIN_ACCESS_TOKEN', None)
        
    def _get_headers(self) -> Dict[str, str]:
        """Return headers with OAuth token and API version."""
        return {
            'Authorization': f'Bearer {self.access_token}',
            'LinkedIn-Version': self.API_VERSION,
            'Content-Type': 'application/json',
        }
    
    def _url_encode_urn(self, urn: str) -> str:
        """URL encode a URN for use in query parameters."""
        return requests.utils.quote(urn, safe='')
    
    # =========================================================================
    # OAuth 2.0 Authentication
    # =========================================================================
    
    def get_authorization_url(self, state: Optional[str] = None) -> str:
        """
        Generate LinkedIn OAuth authorization URL.
        
        Args:
            state: Optional state parameter for CSRF protection
            
        Returns:
            Authorization URL to redirect user for LinkedIn login
        """
        scopes = [
            'r_marketing_leadgen_automation',
            'r_ads',
            'r_organization_admin'
        ]
        
        params = {
            'response_type': 'code',
            'client_id': self.client_id,
            'redirect_uri': self.redirect_uri,
            'scope': ' '.join(scopes),
            'state': state or os.urandom(16).hex(),
        }
        
        return f"{self.AUTHORIZE_URL}?{urlencode(params)}"
    
    def exchange_code_for_token(self, code: str) -> Dict[str, Any]:
        """
        Exchange authorization code for access token.
        
        Args:
            code: Authorization code from LinkedIn OAuth callback
            
        Returns:
            Dict containing access_token, expires_in, etc.
        """
        payload = {
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': self.redirect_uri,
            'client_id': self.client_id,
            'client_secret': self.client_secret,
        }
        
        response = requests.post(self.AUTH_URL, data=payload)
        response.raise_for_status()
        
        token_data = response.json()
        self.access_token = token_data.get('access_token')
        
        return token_data
    
    def refresh_access_token(self, refresh_token: str) -> Dict[str, Any]:
        """
        Refresh an expired access token.
        
        Note: LinkedIn may not support refresh tokens for all OAuth flows.
        """
        payload = {
            'grant_type': 'refresh_token',
            'refresh_token': refresh_token,
            'client_id': self.client_id,
            'client_secret': self.client_secret,
        }
        
        response = requests.post(self.AUTH_URL, data=payload)
        response.raise_for_status()
        
        token_data = response.json()
        self.access_token = token_data.get('access_token')
        
        return token_data
    
    # =========================================================================
    # Lead Forms Management
    # =========================================================================
    
    def get_lead_forms(
        self,
        owner: str,
        owner_type: str = "organization",
        count: int = 10,
        start: int = 0
    ) -> Dict[str, Any]:
        """
        Retrieve lead forms for a given owner.
        
        Args:
            owner: Organization URN (urn:li:organization:XXXXX) or 
                   Sponsored Account URN (urn:li:sponsoredAccount:XXXXX)
            owner_type: "organization" or "sponsoredAccount"
            count: Number of results per page
            start: Starting index for pagination
            
        Returns:
            API response with lead forms
        """
        owner_value = f"{owner_type}:{owner}" if owner_type else owner
        encoded_owner = self._url_encode_urn(owner_value)
        
        params = {
            'q': 'owner',
            'owner': f'({encoded_owner})',
            'count': count,
            'start': start,
        }
        
        url = f"{self.API_BASE_URL}/leadForms"
        response = requests.get(url, headers=self._get_headers(), params=params)
        response.raise_for_status()
        
        return response.json()
    
    def get_lead_form(self, form_id: int) -> Dict[str, Any]:
        """
        Get a specific lead form by ID.
        
        Args:
            form_id: The lead form ID
            
        Returns:
            Lead form details
        """
        url = f"{self.API_BASE_URL}/leadForms/{form_id}"
        response = requests.get(url, headers=self._get_headers())
        response.raise_for_status()
        
        return response.json()
    
    def get_lead_form_schema(self, form_id: int) -> Dict[str, Any]:
        """
        Extract field mapping from a lead form.
        
        Returns a dict mapping field names (firstName, email, etc.) to question IDs.
        Useful for standardizing lead data.
        """
        form = self.get_lead_form(form_id)
        
        field_map = {}
        questions = form.get('content', {}).get('questions', [])
        
        for question in questions:
            field_name = question.get('name')
            question_id = question.get('questionId')
            predefined = question.get('predefinedField')
            
            if field_name:
                field_map[field_name] = {
                    'questionId': question_id,
                    'predefinedField': predefined,
                    'question': question.get('question', {}).get('localized', {}).get('en_US', ''),
                }
        
        return field_map
    
    # =========================================================================
    # Lead Form Responses (Leads)
    # =========================================================================
    
    def get_lead_responses(
        self,
        owner: str,
        owner_type: str = "organization",
        lead_type: str = "SPONSORED",
        versioned_form_urn: Optional[str] = None,
        submitted_after: Optional[int] = None,
        limited_to_test_leads: bool = False,
    ) -> Dict[str, Any]:
        """
        Fetch lead form responses (leads) for a given owner.
        
        Args:
            owner: Organization URN or Sponsored Account URN
            owner_type: "organization" or "sponsoredAccount"  
            lead_type: SPONSORED, EVENT, COMPANY, or ORGANIZATION_PRODUCT
            versioned_form_urn: Optional specific form URN to filter by
            submitted_after: Unix timestamp in milliseconds to filter by submission time
            limited_to_test_leads: If True, only return test leads
            
        Returns:
            API response with lead form responses (elements array)
        """
        owner_value = f"{owner_type}:{owner}"
        encoded_owner = self._url_encode_urn(owner_value)
        
        params = {
            'q': 'owner',
            'owner': f'({encoded_owner})',
            'leadType': f'(leadType:{lead_type})',
            'limitedToTestLeads': str(limited_to_test_leads).lower(),
        }
        
        if versioned_form_urn:
            params['versionedLeadGenFormUrn'] = self._url_encode_urn(versioned_form_urn)
        
        if submitted_after:
            # LinkedIn expects epoch milliseconds
            time_range = {
                'start': submitted_after,
            }
            encoded_time_range = self._url_encode_urn(str(time_range))
            params['submittedAtTimeRange'] = encoded_time_range
        
        url = f"{self.API_BASE_URL}/leadFormResponses"
        response = requests.get(url, headers=self._get_headers(), params=params)
        response.raise_for_status()
        
        return response.json()
    
    def get_lead_response(self, lead_response_id: str) -> Dict[str, Any]:
        """
        Fetch a single lead form response by ID.
        
        Args:
            lead_response_id: The lead response URN or ID
            
        Returns:
            Single lead form response details
        """
        url = f"{self.API_BASE_URL}/leadFormResponses/{lead_response_id}"
        response = requests.get(url, headers=self._get_headers())
        response.raise_for_status()
        
        return response.json()
    
    # =========================================================================
    # Lead Notification Subscriptions (Webhooks)
    # =========================================================================
    
    def get_webhook_subscriptions(self, owner: str, owner_type: str = "organization") -> Dict[str, Any]:
        """
        Get existing webhook subscriptions for lead notifications.
        """
        owner_value = f"{owner_type}:{owner}"
        encoded_owner = self._url_encode_urn(owner_value)
        
        params = {
            'q': 'criteria',
            'owner': f'({encoded_owner})',
        }
        
        url = f"{self.API_BASE_URL}/leadNotifications"
        response = requests.get(url, headers=self._get_headers(), params=params)
        response.raise_for_status()
        
        return response.json()
    
    def create_webhook_subscription(
        self,
        webhook_url: str,
        owner: str,
        owner_type: str = "organization",
        lead_type: str = "SPONSORED",
        versioned_form_urn: Optional[str] = None,
        associated_entity: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Create a webhook subscription for real-time lead notifications.
        
        Args:
            webhook_url: HTTPS URL to receive lead notifications
            owner: Organization URN or Sponsored Account URN
            owner_type: "organization" or "sponsoredAccount"
            lead_type: Type of leads to receive (SPONSORED, EVENT, etc.)
            versioned_form_urn: Optional specific form URN
            associated_entity: Optional entity URN (e.g., event URN)
            
        Returns:
            Created subscription details
        """
        payload = {
            'webhook': webhook_url,
            'owner': {owner_type: owner},
            'leadType': lead_type,
        }
        
        if versioned_form_urn:
            payload['versionedForm'] = versioned_form_urn
        if associated_entity:
            payload['associatedEntity'] = {'event': associated_entity}
        
        url = f"{self.API_BASE_URL}/leadNotifications"
        response = requests.post(url, headers=self._get_headers(), json=payload)
        response.raise_for_status()
        
        return response.json()
    
    def delete_webhook_subscription(self, subscription_id: int) -> None:
        """
        Delete a webhook subscription.
        """
        url = f"{self.API_BASE_URL}/leadNotifications/{subscription_id}"
        response = requests.delete(url, headers=self._get_headers())
        response.raise_for_status()
    
    # =========================================================================
    # Utility Methods
    # =========================================================================
    
    def parse_lead_notification(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Parse incoming webhook notification payload.
        
        Extracts lead response URN and metadata for subsequent API call.
        """
        return {
            'lead_response_urn': payload.get('leadGenFormResponse'),
            'lead_form_urn': payload.get('leadGenForm'),
            'owner': payload.get('owner'),
            'lead_type': payload.get('leadType'),
            'action': payload.get('leadAction'),  # CREATED or DELETED
            'occurred_at': payload.get('occurredAt'),
        }
    
    def fetch_and_parse_lead(self, notification_payload: Dict[str, Any]) -> Dict[str, Any]:
        """
        Given a webhook notification, fetch full lead details and return parsed data.
        """
        parsed = self.parse_lead_notification(notification_payload)
        lead_response_urn = parsed['lead_response_urn']
        
        if lead_response_urn:
            # Extract just the UUID part from URN if needed
            lead_id = lead_response_urn.replace('urn:li:leadGenFormResponse:', '')
            lead_data = self.get_lead_response(lead_id)
            return lead_data
        
        return {}


# =============================================================================
# Singleton instance for FastAPI dependency injection
# =============================================================================

_linkedin_service: Optional[LinkedInLeadSyncService] = None


def get_linkedin_service() -> LinkedInLeadSyncService:
    """Get or create the singleton LinkedIn service instance."""
    global _linkedin_service
    if _linkedin_service is None:
        _linkedin_service = LinkedInLeadSyncService()
    return _linkedin_service
