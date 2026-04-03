import requests
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, List, Optional

from config import settings


class EventbriteService:
    """
    Eventbrite API service for webinar/Event management.
    
    Supports:
    - Event registration (attendee ordering)
    - Event discovery (listing organization events)
    - Event details (including ticket availability)
    - Availability checking for webinar scheduling
    - Attendee management
    
    PRJ-012 Note: Used for #ZeroTo100 webinar invitations to
    BurnedOutAdvisor.com leads (financial advisors).
    """
    
    def __init__(self):
        self.api_url = settings.EVENTBRITE_API_URL
        self.private_token = settings.EVENTBRITE_PRIVATE_TOKEN
        self.organization_id = getattr(settings, 'EVENTBRITE_ORGANIZATION_ID', None)

    def _get_headers(self) -> Dict[str, str]:
        return {
            "Authorization": f"Bearer {self.private_token}",
            "Content-Type": "application/json"
        }

    def _handle_error(self, response: requests.Response) -> None:
        """Log and raise Eventbrite API errors."""
        print(f"Eventbrite HTTP Error: {response.status_code}")
        print(f"Response: {response.text}")
        response.raise_for_status()

    def get_my_organizations(self) -> Dict[str, Any]:
        url = f"{self.api_url}/users/me/organizations/"
        response = requests.get(url, headers=self._get_headers())
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    # =========================================================================
    # Event Discovery
    # =========================================================================
    
    def list_organization_events(
        self,
        status: str = "live",
        time_filter: str = "current_future",
        expand: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        List events for the organization.
        
        Args:
            status: Filter by status (draft, live, started, ended, canceled)
            time_filter: Filter by time (past, current_future, all)
            expand: List of fields to expand (venue, ticket_classes, ticket_availability)
            
        Returns:
            Dict with events array and pagination info
        """
        if not self.organization_id:
            raise ValueError("EVENTBRITE_ORGANIZATION_ID not configured")
            
        params = {
            "status": status,
            "time_filter": time_filter,
        }
        
        if expand:
            params["expand"] = ",".join(expand)
        
        url = f"{self.api_url}/organizations/{self.organization_id}/events/"
        response = requests.get(url, headers=self._get_headers(), params=params)
        
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    def get_event(
        self,
        event_id: str,
        expand: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Get detailed information about a specific event.
        
        Args:
            event_id: The event ID
            expand: Fields to expand (venue, ticket_classes, ticket_availability, 
                   organizer, format, category, subcategory)
            
        Returns:
            Full event details
        """
        params = {}
        if expand:
            params["expand"] = ",".join(expand)
            
        url = f"{self.api_url}/events/{event_id}/"
        response = requests.get(url, headers=self._get_headers(), params=params)
        
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    # =========================================================================
    # Availability Checking
    # =========================================================================
    
    def get_event_availability(self, event_id: str) -> Dict[str, Any]:
        """
        Get ticket availability for an event.
        
        Returns:
            Dict with has_available_tickets, minimum/maximum ticket prices,
            is_sold_out, sales dates
        """
        return self.get_event(event_id, expand=["ticket_availability"])
    
    def get_upcoming_webinars(
        self,
        name_contains: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Get list of upcoming webinar events.
        
        Filters for live events that may be webinars based on naming conventions.
        
        Args:
            name_contains: Optional filter for event name containing this string
            
        Returns:
            List of upcoming event dicts with id, name, start_date, venue
        """
        events_data = self.list_organization_events(
            status="live",
            time_filter="current_future",
            expand=["venue", "ticket_availability"]
        )
        
        events = events_data.get("events", [])
        
        # Filter by name if specified
        if name_contains:
            events = [
                e for e in events 
                if name_contains.lower() in e.get("name", {}).get("text", "").lower()
            ]
        
        return events

    def find_best_available_webinar(
        self,
        preferred_dates: Optional[List[str]] = None,
        topic_filter: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        """
        Find the best available webinar based on user availability preferences.
        
        Args:
            preferred_dates: List of preferred date strings (YYYY-MM-DD)
            topic_filter: Filter events by topic/name keyword
            
        Returns:
            Best matching event or None if no available events
        """
        upcoming = self.get_upcoming_webinars(name_contains=topic_filter)
        
        if not upcoming:
            return None
        
        # If user has preferred dates, find events matching those dates
        if preferred_dates:
            preferred_set = set(preferred_dates)
            
            for event in upcoming:
                start_str = event.get("start", {}).get("local", "")
                if start_str:
                    event_date = start_str[:10]  # Extract YYYY-MM-DD
                    if event_date in preferred_set:
                        # Check availability
                        event_id = event.get("id")
                        availability = self.get_event_availability(event_id)
                        ticket_avail = availability.get("ticket_availability", {})
                        
                        if ticket_avail.get("has_available_tickets", False):
                            return {
                                "event": event,
                                "availability": ticket_avail,
                                "match_reason": f"matches preferred date {event_date}"
                            }
            
            # If no exact date match, return first available
            for event in upcoming:
                event_id = event.get("id")
                availability = self.get_event_availability(event_id)
                ticket_avail = availability.get("ticket_availability", {})
                
                if ticket_avail.get("has_available_tickets", False):
                    return {
                        "event": event,
                        "availability": ticket_avail,
                        "match_reason": "first available after preferred dates"
                    }
        else:
            # Return first available event
            for event in upcoming:
                event_id = event.get("id")
                availability = self.get_event_availability(event_id)
                ticket_avail = availability.get("ticket_availability", {})
                
                if ticket_avail.get("has_available_tickets", False):
                    return {
                        "event": event,
                        "availability": ticket_avail,
                        "match_reason": "first available"
                    }
        
        return None

    # =========================================================================
    # Event Creation
    # =========================================================================

    def create_draft_event(
        self,
        name: str,
        start_utc: str,
        end_utc: str,
        currency: str = "USD",
        timezone_name: Optional[str] = None,
        summary: Optional[str] = None,
        online_event: bool = True,
        listed: bool = False,
        invite_only: bool = True,
        capacity: int = 100,
    ) -> Dict[str, Any]:
        if not self.organization_id:
            raise ValueError("EVENTBRITE_ORGANIZATION_ID not configured")

        payload = {
            "event": {
                "name": {"html": name},
                "start": {
                    "timezone": timezone_name or settings.EVENTBRITE_DEFAULT_TIMEZONE,
                    "utc": start_utc,
                },
                "end": {
                    "timezone": timezone_name or settings.EVENTBRITE_DEFAULT_TIMEZONE,
                    "utc": end_utc,
                },
                "currency": currency,
                "online_event": online_event,
                "listed": listed,
                "invite_only": invite_only,
                "capacity": capacity,
            }
        }
        if summary:
            payload["event"]["summary"] = summary

        url = f"{self.api_url}/organizations/{self.organization_id}/events/"
        response = requests.post(url, json=payload, headers=self._get_headers())
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    def create_free_ticket_class(
        self,
        event_id: str,
        name: str = "General Admission",
        quantity_total: int = 100,
    ) -> Dict[str, Any]:
        payload = {
            "ticket_class": {
                "name": name,
                "quantity_total": quantity_total,
                "free": True,
            }
        }
        url = f"{self.api_url}/events/{event_id}/ticket_classes/"
        response = requests.post(url, json=payload, headers=self._get_headers())
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    def create_demo_webinar_event(
        self,
        name: str = "BurnedOutAdvisor Demo Webinar",
        days_from_now: int = 7,
        duration_minutes: int = 60,
        capacity: int = 50,
    ) -> Dict[str, Any]:
        start = datetime.now(timezone.utc) + timedelta(days=days_from_now)
        end = start + timedelta(minutes=duration_minutes)
        event = self.create_draft_event(
            name=name,
            start_utc=start.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            end_utc=end.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            summary="Draft webinar for BurnedOutAdvisor demo pipeline",
            capacity=capacity,
        )
        ticket_class = self.create_free_ticket_class(event.get("id"), quantity_total=capacity)
        return {
            "event": event,
            "ticket_class": ticket_class,
        }

    # =========================================================================
    # Registration
    # =========================================================================
    
    def register_attendee(
        self,
        first_name: str,
        last_name: str,
        email: str,
        event_id: str,
        ticket_class_id: Optional[str] = None,
        availability_preference: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Registers an attendee for an Eventbrite event/webinar.
        
        Args:
            first_name: Attendee first name
            last_name: Attendee last name
            email: Attendee email address
            event_id: Event to register for
            ticket_class_id: Optional ticket class ID (uses default if not specified)
            availability_preference: Optional availability note (e.g., "March 15 preferred")
            
        Returns:
            Order confirmation with attendee details
        """
        payload = {
            "orders": [{
                "ticket_class_ids": [ticket_class_id] if ticket_class_id else [],
                "attendee": {
                    "first_name": first_name,
                    "last_name": last_name,
                    "email": email
                }
            }]
        }
        
        # If availability preference provided, add as order question
        if availability_preference:
            payload["orders"][0]["questions"] = [
                {
                    "question": "Availability Preference",
                    "answer": availability_preference
                }
            ]

        url = f"{self.api_url}/events/{event_id}/orders/"
        response = requests.post(url, json=payload, headers=self._get_headers())
        
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    def register_with_availability_check(
        self,
        first_name: str,
        last_name: str,
        email: str,
        preferred_dates: Optional[List[str]] = None,
        topic_filter: Optional[str] = None,
        ticket_class_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Register a lead for a webinar, finding best match based on availability.
        
        This is the main entry point for PRJ-012 webinar invitations.
        
        Args:
            first_name: Lead first name
            last_name: Lead last name  
            email: Lead email
            preferred_dates: List of preferred dates (YYYY-MM-DD)
            topic_filter: Filter webinars by topic keyword
            ticket_class_id: Optional specific ticket class
            
        Returns:
            Dict with registration confirmation and event details
        """
        # Find best available webinar
        match = self.find_best_available_webinar(
            preferred_dates=preferred_dates,
            topic_filter=topic_filter
        )
        
        if not match:
            return {
                "success": False,
                "error": "No available webinars found matching criteria"
            }
        
        event = match["event"]
        event_id = event.get("id")
        availability_note = f"User preferred: {preferred_dates}" if preferred_dates else None
        
        # Register for the event
        registration = self.register_attendee(
            first_name=first_name,
            last_name=last_name,
            email=email,
            event_id=event_id,
            ticket_class_id=ticket_class_id,
            availability_preference=availability_note
        )
        
        return {
            "success": True,
            "registration": registration,
            "event": {
                "id": event.get("id"),
                "name": event.get("name"),
                "start": event.get("start"),
                "end": event.get("end"),
                "url": event.get("url"),
            },
            "match_reason": match.get("match_reason")
        }

    # =========================================================================
    # Attendee Management
    # =========================================================================
    
    def get_attendees(self, event_id: str) -> Dict[str, Any]:
        """
        Get list of attendees for an event.
        
        Returns:
            Attendees data with pagination
        """
        url = f"{self.api_url}/events/{event_id}/attendees/"
        response = requests.get(url, headers=self._get_headers())
        
        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    def get_event_orders(self, event_id: str, status: str = "all_not_deleted", expand_attendees: bool = True) -> Dict[str, Any]:
        """
        Get orders for a given event to verify ticket registrations.
        """
        params = {"status": status}
        if expand_attendees:
            params["expand"] = "attendees"
        url = f"{self.api_url}/events/{event_id}/orders/"
        response = requests.get(url, headers=self._get_headers(), params=params)

        try:
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError:
            self._handle_error(response)

    def get_event_with_registration_info(self, event_id: str) -> Dict[str, Any]:
        """
        Get event details with all relevant registration information.
        
        Returns combined info: event details + ticket classes + availability
        """
        return self.get_event(
            event_id,
            expand=[
                "venue",
                "ticket_classes", 
                "ticket_availability",
                "organizer",
                "format"
            ]
        )
