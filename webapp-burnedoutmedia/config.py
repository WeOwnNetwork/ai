from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DEMO_MODE: bool = True

    # FluentCRM Setup
    FLUENTCRM_API_URL: str
    WP_APP_USERNAME: str
    WP_APP_PASSWORD: str

    # FluentCart Setup
    FLUENTCART_API_URL: str = ""
    FLUENTCART_PRODUCT_ID: str = ""

    # Eventbrite Setup
    EVENTBRITE_API_URL: str
    EVENTBRITE_PRIVATE_TOKEN: str
    EVENTBRITE_ORGANIZATION_ID: str = ""  # Optional: for listing organization events
    EVENTBRITE_DEFAULT_TIMEZONE: str = "America/Denver"

    # LinkedIn Lead Sync Setup
    LINKEDIN_CLIENT_ID: str = ""
    LINKEDIN_CLIENT_SECRET: str = ""
    LINKEDIN_ACCESS_TOKEN: str = ""
    LINKEDIN_REDIRECT_URI: str = ""

    # Defaults for Demo/Tests
    DEFAULT_EVENTBRITE_EVENT_ID: str = "1234567890"
    DEFAULT_EVENTBRITE_TICKET_CLASS_ID: str = "9876543210"
    DEFAULT_WEBINAR_TOPIC: str = "BurnedOutAdvisor Webinar"

    class Config:
        env_file = ".env"


settings = Settings()
