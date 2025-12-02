import os

import streamlit as st
from dotenv import load_dotenv

from db import init_db, create_user, get_user_by_email, update_user_inquiry, update_user_status_by_inquiry
from persona_client import create_inquiry, get_inquiry_with_includes, summarize_kyc, PersonaError

# Load env
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

# Initialize DB schema
init_db()


def get_persona_hosted_url(inquiry_id: str) -> str:
    """Best-effort construction of Persona's hosted verification URL.

    This may need adjustment based on your Persona configuration.
    """
    return f"https://withpersona.com/verify?inquiry-id={inquiry_id}"


def ensure_session_state():
    if "step" not in st.session_state:
        st.session_state["step"] = "landing"
    st.session_state.setdefault("user_id", None)
    st.session_state.setdefault("email", "")
    st.session_state.setdefault("full_name", "")
    st.session_state.setdefault("inquiry_id", None)
    st.session_state.setdefault("kyc_status", "NOT_STARTED")


def landing_page():
    st.title("Payless Tax – Smart KYC Demo")
    st.subheader("Connex.ai-style onboarding experience")

    st.markdown(
        """
        Welcome to **Payless Tax** – a modern, AI-assisted tax service that
        automates lead capture, onboarding, and document collection across
        voice, SMS, and web channels.

        This demo focuses on the **web KYC onboarding** journey:

        1. Capture basic lead info.
        2. Redirect the user into a **Persona** identity verification flow.
        3. Poll for the verification result and show it in the UI.
        """
    )

    st.markdown("---")
    st.header("Get Started – Create Your Payless Tax Account")

    with st.form("signup_form"):
        full_name = st.text_input("Full name", value=st.session_state.get("full_name", ""))
        email = st.text_input("Email address", value=st.session_state.get("email", ""))
        submitted = st.form_submit_button("Sign up and start KYC")

    if submitted:
        if not full_name or not email:
            st.error("Please provide both full name and email.")
            return

        existing = get_user_by_email(email)
        if existing:
            user_id = existing["id"]
            st.info("Welcome back! We found an existing record for this email.")
            st.session_state["kyc_status"] = existing.get("kyc_status", "NOT_STARTED")
            st.session_state["inquiry_id"] = existing.get("persona_inquiry_id")
        else:
            user_id = create_user(email=email, full_name=full_name)
            st.success("Account created. Let's verify your identity.")

        st.session_state["user_id"] = user_id
        st.session_state["email"] = email
        st.session_state["full_name"] = full_name
        st.session_state["step"] = "kyc_start"


def kyc_start_page():
    st.header("Step 2 – Verify your identity")

    st.write(
        """
        Before we can onboard you to Payless Tax, we need to verify your identity.
        We use **Persona** for secure, compliant KYC checks. In this demo we use
        Persona's **sandbox** environment.
        """
    )

    st.info(
        "When you click **Start KYC with Persona**, we'll create a new Persona "
        "inquiry in the backend and open the hosted verification flow in a "
        "new tab. After you complete the steps there, come back and click "
        "**Refresh Status**."
    )

    if st.session_state.get("inquiry_id"):
        st.success(f"Existing inquiry found: {st.session_state['inquiry_id']}")

    col1, col2 = st.columns(2)
    with col1:
        if st.button("Start KYC with Persona"):
            try:
                reference_id = str(st.session_state.get("user_id")) if st.session_state.get("user_id") else None
                inquiry = create_inquiry(reference_id=reference_id)
                inquiry_id = inquiry.get("data", {}).get("id")
                if not inquiry_id:
                    st.error("Persona did not return an inquiry ID. Check logs.")
                else:
                    st.session_state["inquiry_id"] = inquiry_id
                    st.session_state["kyc_status"] = "PENDING"
                    update_user_inquiry(st.session_state["user_id"], inquiry_id, "PENDING")
                    hosted_url = get_persona_hosted_url(inquiry_id)
                    st.success("Inquiry created. Open the Persona verification in a new tab:")
                    st.markdown(f"[Open Persona Verification]({hosted_url})")
            except PersonaError as exc:
                st.error(f"Failed to create Persona inquiry: {exc}")

    with col2:
        if st.button("Skip for now"):
            st.session_state["step"] = "landing"

    if st.session_state.get("inquiry_id"):
        st.markdown("---")
        st.subheader("Already started?")
        st.write("If you've already completed the Persona flow, click below to refresh your status.")
        if st.button("Refresh KYC Status"):
            check_status_page(auto=False)


def check_status_page(auto: bool = True):
    inquiry_id = st.session_state.get("inquiry_id")
    if not inquiry_id:
        st.error("No inquiry has been created yet.")
        return

    try:
        inquiry = get_inquiry_with_includes(inquiry_id)
        summary = summarize_kyc(inquiry)
    except PersonaError as exc:
        st.error(f"Error fetching inquiry: {exc}")
        return

    persona_status = summary.get("status") or "unknown"
    persona_decision = summary.get("decision")
    allowed = summary.get("allowed", False)
    watchlist_reports = summary.get("watchlist_reports", [])

    if allowed:
        internal_status = "VERIFIED"
    elif persona_decision == "declined":
        internal_status = "FAILED"
    else:
        internal_status = "PENDING"

    st.session_state["kyc_status"] = internal_status
    update_user_status_by_inquiry(inquiry_id, internal_status)

    st.write(f"Persona status: {persona_status}, decision: {persona_decision or 'none'}")

    if internal_status == "VERIFIED":
        st.success("✅ Your identity has been verified and passed sanctions / watchlist screening.")
        st.session_state["step"] = "dashboard"
    elif internal_status == "FAILED":
        if watchlist_reports:
            st.error("❌ Verification failed due to sanctions or watchlist checks.")
            for r in watchlist_reports:
                st.write(
                    f"- {r.get('type') or 'watchlist'}: status={r.get('status')}, decision={r.get('decision')}"
                )
        else:
            st.error("❌ Your verification did not pass. Please contact support or try again.")
        st.session_state["step"] = "kyc_failed"
    else:
        if persona_status == "review" or persona_decision is None:
            st.info("Your verification is complete but under manual review. Please check back later.")
        else:
            if auto:
                st.info("Your verification is still pending. Please complete the steps in the Persona window.")
            else:
                st.warning("Status still pending. Try again in a few seconds after completing the Persona flow.")


def dashboard_page():
    st.header("Payless Tax – Onboarding Complete")
    st.success("Your KYC verification is complete.")

    st.markdown(
        """
        In a full Payless Tax deployment, this page would:

        - Show your upcoming appointment details.
        - Provide a personalized checklist of documents to upload.
        - Let you chat with the Payless Tax AI assistant about next steps.

        For this demo, you've successfully completed the **Persona KYC flow**
        and seen how the backend status is reflected in the app.
        """
    )


def kyc_failed_page():
    st.header("Verification Issue")
    st.error("Your identity verification did not pass.")
    st.write(
        """
        In a real system, this would trigger a manual review by the compliance team,
        or offer guidance on how to retry with clearer documents.
        """
    )
    if st.button("Back to start"):
        st.session_state["step"] = "landing"


def main():
    ensure_session_state()

    step = st.session_state["step"]

    if step == "landing":
        landing_page()
    elif step == "kyc_start":
        kyc_start_page()
    elif step == "dashboard":
        dashboard_page()
    elif step == "kyc_failed":
        kyc_failed_page()
    else:
        landing_page()


if __name__ == "__main__":
    main()
