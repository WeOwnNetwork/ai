from typing import Any, Dict, List, Optional

from pydantic import BaseModel, EmailStr, Field


class DemoLeadInput(BaseModel):
    first_name: str
    last_name: str
    email: EmailStr
    phone: Optional[str] = ""
    job_title: Optional[str] = ""
    company_name: Optional[str] = ""
    city: Optional[str] = ""
    state: Optional[str] = ""
    country: Optional[str] = "US"
    years_experience: int = 10
    availability_dates: List[str] = Field(default_factory=list)
    interest_level: str = "medium"
    webinar_topic: str = "BurnedOutAdvisor Webinar"
    campaign: str = "#ZeroTo100"
    raw: Dict[str, Any] = Field(default_factory=dict)


class BulkLeadRequest(BaseModel):
    leads: List[DemoLeadInput]


class DemoEventRequest(BaseModel):
    name: str = "BurnedOutAdvisor Demo Webinar"
    days_from_now: int = 7
    duration_minutes: int = 60
    capacity: int = 50


class DemoE2ERequest(BaseModel):
    count: int = 5
    leads: List[DemoLeadInput] = Field(default_factory=list)
    event_id: Optional[str] = None
    mock_external: bool = True
    campaign: str = "#ZeroTo100"
