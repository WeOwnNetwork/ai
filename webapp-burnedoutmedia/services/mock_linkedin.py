from __future__ import annotations

from datetime import date, timedelta
from typing import Any, Dict, List, Optional


FINANCIAL_ADVISOR_TITLES = [
    "Senior Financial Advisor",
    "Wealth Advisor",
    "Managing Director, Wealth Management",
    "VP Financial Planning",
    "Investment Advisor Representative",
]

COMPANIES = [
    "Summit Wealth Partners",
    "Blue Ridge Capital Advisors",
    "Aspen Private Wealth",
    "Front Range Financial Group",
    "Evergreen Retirement Advisors",
]

CITIES = ["Denver", "Boulder", "Colorado Springs", "Fort Collins", "Aspen"]


class MockLinkedInService:
    def generate_mock_leads(
        self,
        count: int = 5,
        start_index: int = 0,
        campaign: str = "#ZeroTo100",
    ) -> List[Dict[str, Any]]:
        leads: List[Dict[str, Any]] = []
        base_date = date.today() + timedelta(days=5)

        for offset in range(count):
            index = start_index + offset
            first_name = f"Advisor{index + 1}"
            last_name = "Prospect"
            preferred_dates = [
                (base_date + timedelta(days=offset % 3)).isoformat(),
                (base_date + timedelta(days=(offset % 3) + 2)).isoformat(),
            ]
            leads.append(
                {
                    "source": "linkedin-mock",
                    "campaign": campaign,
                    "first_name": first_name,
                    "last_name": last_name,
                    "email": f"advisor{index + 1}@example.com",
                    "phone": f"+1-303-555-{1000 + index}",
                    "job_title": FINANCIAL_ADVISOR_TITLES[index % len(FINANCIAL_ADVISOR_TITLES)],
                    "company_name": COMPANIES[index % len(COMPANIES)],
                    "city": CITIES[index % len(CITIES)],
                    "state": "CO",
                    "country": "US",
                    "years_experience": 10 + (index % 12),
                    "availability_dates": preferred_dates,
                    "pain_points": [
                        "Working 60+ hours per week",
                        "Client fatigue",
                        "Questioning long-term fit",
                    ],
                    "interest_level": "high" if index % 2 == 0 else "medium",
                    "webinar_topic": "BurnedOutAdvisor Webinar",
                    "raw": {
                        "lead_gen_form": "demo-linkedin-form",
                        "campaign": campaign,
                    },
                }
            )
        return leads

    def normalize_lead(self, lead: Dict[str, Any]) -> Dict[str, Any]:
        normalized = dict(lead)
        normalized.setdefault("source", "linkedin-mock")
        normalized.setdefault("availability_dates", [])
        normalized.setdefault("interest_level", "medium")
        normalized.setdefault("webinar_topic", "BurnedOutAdvisor Webinar")
        normalized.setdefault("years_experience", 10)
        return normalized

    def bulk_normalize(self, leads: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        return [self.normalize_lead(lead) for lead in leads]
