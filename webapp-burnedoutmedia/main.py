from fastapi import FastAPI, Query, HTTPException
from typing import Dict, Any, List, Optional

from models import BulkLeadRequest, DemoE2ERequest, DemoEventRequest
from services.demo_pipeline import demo_pipeline
from services.demo_store import store
from services.fluentcrm import FluentCRMService
from services.eventbrite import EventbriteService
from services.linkedin import LinkedInLeadSyncService
from config import settings

app = FastAPI(title="BurnedOutMedia Integrations")

# Initialize services
fluentcrm_svc = FluentCRMService()
eventbrite_svc = EventbriteService()
linkedin_svc = LinkedInLeadSyncService()


# =============================================================================
# Health & Info
# =============================================================================

@app.get("/")
async def root():
    """Root endpoint with service status."""
    return {
        "message": "BurnedOutMedia Integration Service is running.",
        "services": ["fluentcrm", "eventbrite", "linkedin", "demo_pipeline"],
        "project": "PRJ-012 BurnedOutAdvisor.com #ZeroTo100",
        "demo_mode": settings.DEMO_MODE,
    }


# =============================================================================
# LinkedIn Lead Sync Endpoints
# =============================================================================

@app.get("/webhook/linkedin")
async def linkedin_webhook_challenge(challenge: str = None):
    """
    LinkedIn webhook verification challenge endpoint.
    LinkedIn sends a GET with 'challenge' param during webhook registration.
    """
    if challenge:
        return {"challenge": challenge}
    return {"status": "ok"}


@app.post("/webhook/linkedin")
async def process_linkedin_webhook(payload: Dict[str, Any]):
    """
    Webhook receiver for LinkedIn Lead Gen Forms real-time notifications.
    
    LinkedIn sends lead notifications here. We:
    1. Parse the notification to get lead response URN
    2. Fetch full lead details from LinkedIn API
    3. Standardize the lead data
    4. Register for webinar based on availability
    5. Add to FluentCRM
    """
    try:
        # Parse the webhook notification
        notification = linkedin_svc.parse_lead_notification(payload)
        
        # If this is a DELETED action, skip processing
        if notification.get('action') == 'DELETED':
            return {"status": "skipped", "reason": "Lead deleted"}
        
        # Fetch full lead data
        lead_data = linkedin_svc.fetch_and_parse_lead(payload)
        
        if not lead_data:
            raise HTTPException(status_code=404, detail="Could not fetch lead data")
        
        # Extract standardized lead info
        # The lead form responses contain answers mapped by questionId
        # We need to map these to standard field names
        form_responses = lead_data.get('formResponse', {}).get('answers', [])
        
        lead_info = _extract_lead_fields(form_responses)
        
        return {
            "status": "received",
            "lead": lead_info,
            "notification": notification
        }
        
    except Exception as e:
        print(f"Error processing LinkedIn webhook: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


def _extract_lead_fields(form_responses: List[Dict]) -> Dict[str, Any]:
    """
    Extract standardized fields from LinkedIn lead form responses.
    
    Maps predefined fields (FIRST_NAME, LAST_NAME, EMAIL) and
    custom questions to standardized output.
    """
    extracted = {}
    
    # Known predefined field mappings
    PREDEFINED_MAP = {
        "FIRST_NAME": "first_name",
        "LAST_NAME": "last_name", 
        "EMAIL": "email",
        "PHONE": "phone",
        "JOB_TITLE": "job_title",
        "COMPANY_NAME": "company_name",
        "LINKEDIN_PROFILE_URL": "linkedin_url",
        "CITY": "city",
        "STATE": "state",
        "COUNTRY": "country",
    }
    
    for answer in form_responses:
        question_id = answer.get('questionId')
        answer_details = answer.get('answerDetails', {})
        
        # Text answer
        if 'textQuestionAnswer' in answer_details:
            value = answer_details['textQuestionAnswer'].get('answer', '')
            # Map common fields
            if question_id == 1:
                extracted['first_name'] = value
            elif question_id == 2:
                extracted['last_name'] = value
            elif question_id == 3:
                extracted['email'] = value
            else:
                extracted[f'custom_field_{question_id}'] = value
        
        # Multiple choice answer
        elif 'multipleChoiceAnswer' in answer_details:
            options = answer_details['multipleChoiceAnswer'].get('options', [])
            extracted[f'choice_field_{question_id}'] = options
            
        # Phone answer
        elif 'phoneQuestionAnswer' in answer_details:
            extracted['phone'] = answer_details['phoneQuestionAnswer'].get('answer', '')
    
    return extracted


# =============================================================================
# LinkedIn Lead Retrieval Endpoints
# =============================================================================

@app.get("/linkedin/leads")
async def get_linkedin_leads(
    owner: str = Query(..., description="Organization or SponsoredAccount URN"),
    owner_type: str = Query("organization", description="organization or sponsoredAccount"),
    lead_type: str = Query("SPONSORED", description="SPONSORED, EVENT, COMPANY, or ORGANIZATION_PRODUCT"),
    limit: int = Query(50, description="Max leads to return")
):
    """
    Fetch leads from LinkedIn Lead Sync API.
    
    Args:
        owner: URN of the form owner (e.g., urn:li:organization:123456)
        owner_type: Type of owner (organization or sponsoredAccount)
        lead_type: Type of leads to retrieve
        limit: Maximum number of leads
        
    Returns:
        List of standardized lead records
    """
    try:
        # Fetch lead responses from LinkedIn
        response = linkedin_svc.get_lead_responses(
            owner=owner,
            owner_type=owner_type,
            lead_type=lead_type
        )
        
        elements = response.get('elements', [])
        
        # Standardize each lead
        standardized_leads = []
        for lead in elements[:limit]:
            standardized = _standardize_linkedin_lead(lead)
            standardized_leads.append(standardized)
        
        return {
            "count": len(standardized_leads),
            "total_available": response.get('paging', {}).get('total', 0),
            "leads": standardized_leads
        }
        
    except Exception as e:
        print(f"Error fetching LinkedIn leads: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


def _standardize_linkedin_lead(lead_response: Dict) -> Dict[str, Any]:
    """
    Standardize a LinkedIn lead response to a consistent format.
    
    Maps LinkedIn's response schema to our internal lead format
    suitable for CRM and webinar registration.
    """
    # Extract form responses
    form_responses = lead_response.get('formResponse', {}).get('answers', [])
    
    # Build standardized field map
    fields = _extract_lead_fields(form_responses)
    
    return {
        "lead_id": lead_response.get('id'),
        "submitted_at": lead_response.get('submittedAt'),
        "lead_type": lead_response.get('leadType'),
        "is_test": lead_response.get('testLead', False),
        "first_name": fields.get('first_name', ''),
        "last_name": fields.get('last_name', ''),
        "email": fields.get('email', ''),
        "phone": fields.get('phone', ''),
        "job_title": fields.get('job_title', ''),
        "company_name": fields.get('company_name', ''),
        "city": fields.get('city', ''),
        "state": fields.get('state', ''),
        "country": fields.get('country', ''),
        "linkedin_url": fields.get('linkedin_url', ''),
        "raw_responses": fields,
        # PRJ-012 specific
        "qualifies_for_webinar": _check_webinar_qualification(fields)
    }


def _check_webinar_qualification(fields: Dict) -> Dict[str, Any]:
    """
    Check if lead qualifies for BurnedOutAdvisor webinar.
    
    Based on PRJ-012: Target audience is financial advisors
    with 10+ years experience.
    """
    job_title = fields.get('job_title', '').lower()
    company = fields.get('company_name', '').lower()
    
    # Basic qualification indicators
    financial_keywords = ['financial', 'advisor', 'wealth', 'investment', 'capital']
    
    is_financial_advisor = any(kw in job_title or kw in company for kw in financial_keywords)
    
    return {
        "is_qualified": is_financial_advisor,
        "reason": "Financial advisor detected" if is_financial_advisor else "May not match target persona",
        "requires_review": not is_financial_advisor
    }


@app.get("/linkedin/forms")
async def get_linkedin_forms(
    owner: str = Query(..., description="Organization or SponsoredAccount URN"),
    owner_type: str = Query("organization", description="organization or sponsoredAccount"),
    limit: int = Query(10, description="Max forms to return")
):
    """
    Retrieve available LinkedIn Lead Gen Forms for an owner.
    """
    try:
        response = linkedin_svc.get_lead_forms(
            owner=owner,
            owner_type=owner_type,
            count=limit
        )
        
        forms = []
        for form in response.get('elements', []):
            forms.append({
                "id": form.get('id'),
                "name": form.get('name'),
                "state": form.get('state'),
                "created": form.get('created'),
                "questions": _extract_form_questions(form)
            })
        
        return {
            "count": len(forms),
            "forms": forms
        }
        
    except Exception as e:
        print(f"Error fetching LinkedIn forms: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


def _extract_form_questions(form: Dict) -> List[Dict]:
    """Extract question schema from a LinkedIn form."""
    questions = []
    for q in form.get('content', {}).get('questions', []):
        questions.append({
            "id": q.get('questionId'),
            "name": q.get('name'),
            "predefined_field": q.get('predefinedField'),
            "question_text": q.get('question', {}).get('localized', {}).get('en_US', ''),
            "required": q.get('responseRequired', False)
        })
    return questions


# =============================================================================
# Webinar Registration Endpoints
# =============================================================================

@app.get("/webinars")
async def list_webinars(
    topic_filter: Optional[str] = Query(None, description="Filter events by name keyword"),
    status: str = Query("live", description="Event status (live, draft, etc.)")
):
    """
    List available webinars from Eventbrite.
    
    Returns upcoming webinars that can accommodate registrations.
    Optionally filtered by topic/name keyword.
    """
    try:
        events = eventbrite_svc.get_upcoming_webinars(topic_filter=topic_filter)
        
        # Format for response
        formatted_events = []
        for event in events:
            formatted_events.append({
                "id": event.get('id'),
                "name": event.get('name', {}).get('text', ''),
                "description": event.get('description', {}).get('text', '')[:200],
                "start": event.get('start'),
                "end": event.get('end'),
                "url": event.get('url'),
                "venue": event.get('venue', {}).get('name', 'Online'),
                "capacity": event.get('venue', {}).get('capacity')
            })
        
        return {
            "count": len(formatted_events),
            "events": formatted_events
        }
        
    except Exception as e:
        print(f"Error listing webinars: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/webinars/availability")
async def check_webinar_availability(
    event_id: Optional[str] = Query(None, description="Specific event ID"),
    preferred_dates: Optional[str] = Query(None, description="Comma-separated preferred dates (YYYY-MM-DD)"),
    topic_filter: Optional[str] = Query(None, description="Filter by topic keyword")
):
    """
    Check webinar availability based on user preferences.
    
    If event_id provided, check that specific event.
    Otherwise, find best available webinar matching criteria.
    """
    try:
        if event_id:
            # Get specific event availability
            event = eventbrite_svc.get_event_availability(event_id)
            return {
                "event_id": event_id,
                "availability": event.get('ticket_availability'),
                "event": event
            }
        else:
            # Find best available
            dates_list = preferred_dates.split(',') if preferred_dates else None
            match = eventbrite_svc.find_best_available_webinar(
                preferred_dates=dates_list,
                topic_filter=topic_filter
            )
            
            if not match:
                return {"available": False, "message": "No available webinars found"}
            
            return {
                "available": True,
                "event": match['event'],
                "availability": match['availability'],
                "match_reason": match.get('match_reason')
            }
            
    except Exception as e:
        print(f"Error checking availability: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/webinar/register")
async def register_for_webinar(
    first_name: str = Query(...),
    last_name: str = Query(...),
    email: str = Query(...),
    event_id: Optional[str] = Query(None, description="Specific event ID (uses first available if not set)"),
    preferred_dates: Optional[str] = Query(None, description="Comma-separated preferred dates (YYYY-MM-DD)"),
    availability_note: Optional[str] = Query(None, description="Additional availability context"),
    phone: Optional[str] = Query(None, description="Contact phone"),
    job_title: Optional[str] = Query(None, description="Lead job title for qualification"),
    company_name: Optional[str] = Query(None, description="Lead company name")
):
    """
    Register a lead for a webinar with availability preferences.
    
    This is the main endpoint for PRJ-012 webinar invitations.
    Takes a lead from LinkedIn (or other source), qualifies them,
    and registers them for the best available webinar.
    
    Steps:
    1. Standardize lead data
    2. Check qualification (financial advisor target)
    3. Find best available webinar (or use specified event)
    4. Register for webinar via Eventbrite
    5. Add/update contact in FluentCRM
    """
    try:
        # Parse preferred dates
        dates_list = preferred_dates.split(',') if preferred_dates else None
        
        # Prepare lead data for FluentCRM
        webinar_topic = availability_note or "BurnedOutAdvisor"
        
        # 1. Register for Eventbrite webinar
        if event_id:
            # Direct registration for specific event
            event = eventbrite_svc.get_event_with_registration_info(event_id)
            registration = eventbrite_svc.register_attendee(
                first_name=first_name,
                last_name=last_name,
                email=email,
                event_id=event_id,
                availability_preference=availability_note
            )
            registration_result = {
                "success": True,
                "event": event,
                "registration": registration
            }
        else:
            # Find best available based on preferences
            registration_result = eventbrite_svc.register_with_availability_check(
                first_name=first_name,
                last_name=last_name,
                email=email,
                preferred_dates=dates_list,
                topic_filter=topic_filter if 'topic_filter' in locals() else None,
                ticket_class_id=None
            )
            
            if not registration_result.get('success'):
                return {
                    "status": "failed",
                    "reason": registration_result.get('error', 'Unknown error')
                }
        
        # 2. Add to FluentCRM
        try:
            crm_response = fluentcrm_svc.create_contact(
                first_name=first_name,
                last_name=last_name,
                email=email,
                phone=phone or '',
                webinar=webinar_topic
            )
            crm_status = "success"
            crm_id = crm_response.get('id')
        except Exception as crm_err:
            print(f"FluentCRM error (non-fatal): {crm_err}")
            crm_status = "failed"
            crm_id = None
        
        # 3. Return combined response
        return {
            "status": "success",
            "lead": {
                "first_name": first_name,
                "last_name": last_name,
                "email": email,
                "phone": phone,
                "job_title": job_title,
                "company_name": company_name
            },
            "webinar": registration_result,
            "crm": {
                "status": crm_status,
                "contact_id": crm_id
            }
        }
        
    except Exception as e:
        print(f"Error in webinar registration: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/webhook/linkedin/e2e")
async def process_linkedin_lead_e2e(payload: Dict[str, Any]):
    """
    End-to-end processing of a LinkedIn lead for webinar registration.
    
    This endpoint:
    1. Receives lead data (from LinkedIn webhook or direct submission)
    2. Standardizes the lead
    3. Qualifies against PRJ-012 criteria (financial advisors)
    4. Registers for webinar based on availability preferences
    5. Adds to FluentCRM
    
    Expected payload:
    {
        "first_name": "...",
        "last_name": "...",
        "email": "...",
        "phone": "...",  // optional
        "job_title": "...",  // for qualification
        "company_name": "...",  // for qualification
        "preferred_dates": ["2026-03-15", "2026-03-16"],  // optional
        "linkedin_responses": {}  // raw LinkedIn form responses if from webhook
    }
    """
    try:
        # Extract lead fields
        first_name = payload.get("first_name", "Unknown")
        last_name = payload.get("last_name", "Unknown")
        email = payload.get("email", "")
        phone = payload.get("phone", "")
        job_title = payload.get("job_title", "")
        company_name = payload.get("company_name", "")
        preferred_dates = payload.get("preferred_dates", [])
        linkedin_responses = payload.get("linkedin_responses", {})
        
        if not email:
            raise HTTPException(status_code=400, detail="Missing required field: email")
        
        # Check qualification based on job title/company
        fields_for_qual = {
            "job_title": job_title,
            "company_name": company_name
        }
        qualification = _check_webinar_qualification(fields_for_qual)
        
        if qualification.get("requires_review"):
            # Log for manual review but continue
            print(f"Lead may not match target persona: {qualification.get('reason')}")
        
        # Parse preferred dates for API
        dates_str = ",".join(preferred_dates) if preferred_dates else None
        
        # Register for webinar
        webinar_result = eventbrite_svc.register_with_availability_check(
            first_name=first_name,
            last_name=last_name,
            email=email,
            preferred_dates=preferred_dates if preferred_dates else None
        )
        
        # Add to FluentCRM
        webinar_topic = "BurnedOutAdvisor Webinar"
        if linkedin_responses:
            webinar_topic += " (LinkedIn Lead)"
            
        try:
            crm_response = fluentcrm_svc.create_contact(
                first_name=first_name,
                last_name=last_name,
                email=email,
                phone=phone,
                webinar=webinar_topic
            )
            crm_id = crm_response.get("id")
        except Exception as crm_err:
            print(f"FluentCRM error (non-fatal): {crm_err}")
            crm_id = None
        
        return {
            "status": "success",
            "lead": {
                "first_name": first_name,
                "last_name": last_name,
                "email": email,
                "qualification": qualification
            },
            "webinar": webinar_result,
            "crm_id": crm_id
        }
        
    except Exception as e:
        print(f"Error in E2E processing: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# =============================================================================
# Legacy Webhook (for backward compatibility / testing)
# =============================================================================

@app.post("/webhook/linkedin/legacy")
async def process_linkedin_lead_legacy(payload: Dict[str, Any]):
    """
    Legacy endpoint for direct lead submission (not from LinkedIn webhook).
    
    Maintained for E2E testing and backwards compatibility.
    New integrations should use /webhook/linkedin/e2e
    """
    try:
        first_name = payload.get("first_name", "Unknown")
        last_name = payload.get("last_name", "Unknown")
        email = payload.get("email", "")
        phone = payload.get("phone", "")
        webinar = payload.get("webinar", "General")
        
        if not email:
            raise HTTPException(status_code=400, detail="Missing required field: email")

        # 1. Send Lead to FluentCRM
        crm_response = fluentcrm_svc.create_contact(
            first_name=first_name,
            last_name=last_name,
            email=email,
            phone=phone,
            webinar=webinar
        )
        print(f"FluentCRM Success: {crm_response}")

        # 2. Register for Eventbrite Webinar
        event_id = settings.DEFAULT_EVENTBRITE_EVENT_ID
        ticket_class_id = settings.DEFAULT_EVENTBRITE_TICKET_CLASS_ID
        
        eb_response = eventbrite_svc.register_attendee(
            first_name=first_name,
            last_name=last_name,
            email=email,
            event_id=event_id,
            ticket_class_id=ticket_class_id
        )
        print(f"Eventbrite Success: {eb_response}")

        return {
            "status": "success",
            "message": "Lead processed and registered successfully",
            "crm_id": crm_response.get("id"),
            "eventbrite_order_id": eb_response.get("id")
        }

    except Exception as e:
        print(f"Error processing lead: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# =============================================================================
# Demo Mode Endpoints
# =============================================================================

@app.post("/demo/reset")
async def reset_demo_state():
    store.reset()
    return {"status": "success", "message": "Demo state reset"}


@app.get("/demo/state")
async def get_demo_state():
    return {"status": "success", "state": store.get_state()}


@app.post("/demo/linkedin/mock-leads")
async def create_mock_linkedin_leads(
    count: int = Query(5, ge=1, le=100),
    campaign: str = Query("#ZeroTo100"),
):
    leads = demo_pipeline.ingest_mock_leads(count=count, campaign=campaign)
    return {
        "status": "success",
        "count": len(leads),
        "leads": leads,
    }


@app.post("/demo/linkedin/ingest")
async def ingest_demo_linkedin_leads(request: BulkLeadRequest):
    leads = demo_pipeline.ingest_custom_leads([lead.model_dump() for lead in request.leads])
    return {
        "status": "success",
        "count": len(leads),
        "leads": leads,
    }


@app.post("/demo/eventbrite/draft-event")
async def create_demo_eventbrite_draft(
    request: Optional[DemoEventRequest] = None,
    create_live_in_eventbrite: bool = Query(False),
):
    request = request or DemoEventRequest()
    if create_live_in_eventbrite:
        result = eventbrite_svc.create_demo_webinar_event(
            name=request.name,
            days_from_now=request.days_from_now,
            duration_minutes=request.duration_minutes,
            capacity=request.capacity,
        )
        stored = store.add_event(
            {
                "provider": "eventbrite",
                "mode": "live",
                "event": result.get("event"),
                "ticket_class": result.get("ticket_class"),
            }
        )
    else:
        stored = store.add_event(
            {
                "provider": "eventbrite",
                "mode": "mock",
                "event": {
                    "id": settings.DEFAULT_EVENTBRITE_EVENT_ID or "demo-event",
                    "name": request.name,
                    "days_from_now": request.days_from_now,
                    "duration_minutes": request.duration_minutes,
                    "capacity": request.capacity,
                    "ticket_class_id": settings.DEFAULT_EVENTBRITE_TICKET_CLASS_ID or "demo-ticket-class",
                },
            }
        )

    return {
        "status": "success",
        "event": stored,
    }


@app.get("/demo/eventbrite/orders")
async def get_demo_eventbrite_orders(event_id: str = Query(...)):
    orders = eventbrite_svc.get_event_orders(event_id=event_id)
    order_items = orders.get("orders", [])
    emails = [o.get("email") for o in order_items if o.get("email")]
    return {
        "status": "success",
        "event_id": event_id,
        "order_count": len(order_items),
        "emails": emails,
        "orders": order_items,
    }


@app.post("/demo/e2e/run")
async def run_demo_e2e(request: DemoE2ERequest):
    persist_input = True
    leads = [lead.model_dump() for lead in request.leads]
    if not leads and store.leads:
        leads = store.get_state()["leads"]
        persist_input = False
    elif not leads:
        leads = demo_pipeline.mock_linkedin.generate_mock_leads(
            count=request.count,
            campaign=request.campaign,
        )

    result = demo_pipeline.run_e2e(
        leads=leads,
        event_id=request.event_id,
        mock_external=request.mock_external,
        persist_input=persist_input,
    )

    return {
        "status": "success",
        **result,
    }
