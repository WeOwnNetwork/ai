
from __future__ import annotations

import os
import time
from typing import Optional

import mysql.connector
import stripe
import streamlit as st
from dotenv import load_dotenv

from persona_client import PersonaError, create_inquiry, get_inquiry_with_includes, summarize_kyc


def _load_env() -> None:
    load_dotenv(override=False)
    sibling = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "withPersona", ".env"))
    if os.path.exists(sibling):
        load_dotenv(dotenv_path=sibling, override=False)


_load_env()


def _env(name: str, default: Optional[str] = None) -> str:
    v = os.getenv(name)
    if v is None or v == "":
        return default or ""
    return v.strip().strip('"')


def _db_conn(database: Optional[str] = None):
    return mysql.connector.connect(
        host=_env("DB_HOST", "localhost"),
        port=int(_env("DB_PORT", "3306")),
        user=_env("DB_USER", "payless_user"),
        password=_env("DB_PASSWORD", "payless_password"),
        database=database,
        autocommit=True,
    )


def init_db() -> None:
    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=None)
    cur = conn.cursor()
    cur.execute(f"CREATE DATABASE IF NOT EXISTS `{db_name}`")
    cur.close()
    conn.close()

    conn2 = _db_conn(database=db_name)
    cur2 = conn2.cursor()
    cur2.execute(
        """
        CREATE TABLE IF NOT EXISTS kyc_users (
          id INT AUTO_INCREMENT PRIMARY KEY,
          email VARCHAR(255) NOT NULL UNIQUE,
          inquiry_id VARCHAR(64),
          kyc_status VARCHAR(32) NOT NULL DEFAULT 'PENDING',
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
        """
    )

    cur2.execute(
        """
        CREATE TABLE IF NOT EXISTS stripe_checkouts (
          id INT AUTO_INCREMENT PRIMARY KEY,
          email VARCHAR(255) NOT NULL,
          inquiry_id VARCHAR(64),
          product_key VARCHAR(64) NOT NULL,
          amount_cents INT NOT NULL,
          currency VARCHAR(8) NOT NULL DEFAULT 'usd',
          stripe_session_id VARCHAR(255) NOT NULL,
          stripe_payment_status VARCHAR(64),
          stripe_status VARCHAR(64),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          KEY idx_email (email),
          KEY idx_inquiry (inquiry_id),
          UNIQUE KEY uniq_session (stripe_session_id)
        )
        """
    )
    cur2.close()
    conn2.close()


def _stripe_enabled() -> bool:
    return bool(_env("STRIPE_SECRET_KEY"))


def _stripe_configure() -> None:
    stripe.api_key = _env("STRIPE_SECRET_KEY")


def _app_base_url() -> str:
    return _env("APP_BASE_URL", "http://localhost:8501").rstrip("/")


def _persona_hosted_flow_base_url() -> str:
    return _env("PERSONA_HOSTED_FLOW_BASE_URL", "https://inquiry.withpersona.com/inquiry").rstrip("/")


def build_persona_inquiry_url(*, inquiry_id: str) -> str:
    # Persona Hosted Flow URLs are constructed from the inquiry id (Persona does not always
    # return a direct inquiry-url in API responses).
    # Ref: https://docs.withpersona.com/quickstart-hosted-flow
    return f"{_persona_hosted_flow_base_url()}?inquiry-id={inquiry_id}"


PRODUCTS = {
    "agency_pro": {
        "name": "Agency Pro Bundle",
        "amount_cents": 197700,
        "currency": "usd",
        "description": "Basic + full stack WordPress + agentic workflow setup",
    },
    "weown_lite": {
        "name": "WeOwn Lite Setup",
        "amount_cents": 9700,
        "currency": "usd",
        "description": "Basic WordPress personal website + AnythingLLM open-source model setup",
    },
}


def create_checkout_session(*, product_key: str, email: str, inquiry_id: str) -> str:
    if product_key not in PRODUCTS:
        raise ValueError("Unknown product")
    if not _stripe_enabled():
        raise RuntimeError("Stripe is not configured. Missing STRIPE_SECRET_KEY.")

    p = PRODUCTS[product_key]
    _stripe_configure()

    success_url = f"{_app_base_url()}/?payment=success&session_id={{CHECKOUT_SESSION_ID}}"
    cancel_url = f"{_app_base_url()}/?payment=cancel"

    session = stripe.checkout.Session.create(
        mode="payment",
        customer_email=email,
        line_items=[
            {
                "quantity": 1,
                "price_data": {
                    "currency": p["currency"],
                    "unit_amount": p["amount_cents"],
                    "product_data": {
                        "name": p["name"],
                        "description": p["description"],
                    },
                },
            }
        ],
        success_url=success_url,
        cancel_url=cancel_url,
        metadata={
            "product_key": product_key,
            "email": email,
            "inquiry_id": inquiry_id,
        },
    )

    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=db_name)
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO stripe_checkouts (
          email, inquiry_id, product_key, amount_cents, currency,
          stripe_session_id, stripe_payment_status, stripe_status
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
          stripe_payment_status=VALUES(stripe_payment_status),
          stripe_status=VALUES(stripe_status)
        """,
        (
            email,
            inquiry_id,
            product_key,
            int(p["amount_cents"]),
            str(p["currency"]),
            session.id,
            session.get("payment_status"),
            session.get("status"),
        ),
    )
    cur.close()
    conn.close()

    return str(session.url)


def _sync_checkout_session(session_id: str) -> dict:
    _stripe_configure()
    sess = stripe.checkout.Session.retrieve(session_id)

    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=db_name)
    cur = conn.cursor()
    cur.execute(
        """
        UPDATE stripe_checkouts
        SET stripe_payment_status=%s, stripe_status=%s
        WHERE stripe_session_id=%s
        """,
        (sess.get("payment_status"), sess.get("status"), session_id),
    )
    cur.close()
    conn.close()
    return dict(sess)


def _latest_checkout_for_email(email: str) -> Optional[dict]:
    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=db_name)
    cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT * FROM stripe_checkouts
        WHERE email=%s
        ORDER BY created_at DESC
        LIMIT 1
        """,
        (email,),
    )
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row


def get_user_by_inquiry_id(inquiry_id: str) -> Optional[dict]:
    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=db_name)
    cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT email, inquiry_id, kyc_status
        FROM kyc_users
        WHERE inquiry_id=%s
        LIMIT 1
        """,
        (inquiry_id,),
    )
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row


def upsert_user(email: str, inquiry_id: Optional[str] = None, status: Optional[str] = None) -> None:
    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=db_name)
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO kyc_users (email, inquiry_id, kyc_status)
        VALUES (%s, %s, %s)
        ON DUPLICATE KEY UPDATE
          inquiry_id = COALESCE(VALUES(inquiry_id), inquiry_id),
          kyc_status = COALESCE(VALUES(kyc_status), kyc_status)
        """,
        (email, inquiry_id, status or "PENDING"),
    )
    cur.close()
    conn.close()


def update_user_status_by_inquiry(inquiry_id: str, status: str) -> None:
    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=db_name)
    cur = conn.cursor()
    cur.execute("UPDATE kyc_users SET kyc_status=%s WHERE inquiry_id=%s", (status, inquiry_id))
    cur.close()
    conn.close()


def get_user_by_email(email: str) -> Optional[dict]:
    db_name = _env("DB_NAME", "payless_tax")
    conn = _db_conn(database=db_name)
    cur = conn.cursor(dictionary=True)
    cur.execute(
        """
        SELECT email, inquiry_id, kyc_status
        FROM kyc_users
        WHERE email=%s
        LIMIT 1
        """,
        (email,),
    )
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row


def _reset(keep_email: bool = False) -> None:
    preserve = {"email"} if keep_email else set()
    for k in [
        "step",
        "email",
        "inquiry_id",
        "inquiry_url",
        "kyc_status",
        "stripe_session_url",
        "selected_product",
        "_stripe_return_session_id",
    ]:
        if k in preserve:
            continue
        if k in st.session_state:
            del st.session_state[k]


def _ensure_inquiry_url(inquiry_id: str) -> Optional[str]:
    if not inquiry_id:
        return None
    return build_persona_inquiry_url(inquiry_id=inquiry_id)


def restart_kyc_for_email(email: str) -> None:
    resp = create_inquiry(reference_id=email)
    data = resp.get("data") or {}
    inquiry_id = data.get("id")
    if not inquiry_id:
        raise PersonaError("Persona did not return an inquiry id.")

    inquiry_url = _ensure_inquiry_url(inquiry_id)

    st.session_state["email"] = email
    st.session_state["inquiry_id"] = inquiry_id
    st.session_state["inquiry_url"] = inquiry_url
    st.session_state["kyc_status"] = "PENDING"
    upsert_user(email=email, inquiry_id=inquiry_id, status="PENDING")
    st.session_state["step"] = "verify"


def route_user(email: str) -> None:
    user = get_user_by_email(email)
    if user:
        st.session_state["email"] = email
        st.session_state["inquiry_id"] = user.get("inquiry_id")
        st.session_state["kyc_status"] = user.get("kyc_status")

        if user.get("kyc_status") == "VERIFIED":
            st.session_state["step"] = "billing"
            return

        if user.get("kyc_status") in ("PENDING", "FAILED") and user.get("inquiry_id"):
            st.session_state["inquiry_url"] = _ensure_inquiry_url(user["inquiry_id"]) or st.session_state.get("inquiry_url")
            st.session_state["step"] = "verify"
            return

    restart_kyc_for_email(email)


def start_page() -> None:
    st.title("Payless Tax – Persona KYC")
    email = st.text_input("Email", value=st.session_state.get("email", ""))
    if st.button("Continue"):
        if not email or "@" not in email:
            st.error("Please enter a valid email.")
            return
        if not _env("PERSONA_API_KEY"):
            st.error("Missing PERSONA_API_KEY. Set it in your .env and restart the app.")
            return

        try:
            route_user(email)
        except PersonaError as exc:
            st.error(str(exc))
            return

        st.rerun()


def verify_page() -> None:
    st.header("Complete verification")
    inquiry_url = st.session_state.get("inquiry_url")
    if inquiry_url:
        st.link_button("Open Persona verification", inquiry_url)
    else:
        st.warning("No inquiry URL found. You can still complete verification via the Persona dashboard.")

    if st.button("Check status"):
        st.session_state["step"] = "check"
        st.rerun()

    if st.button("Start over"):
        email = st.session_state.get("email")
        if not email:
            inquiry_id = st.session_state.get("inquiry_id")
            if inquiry_id:
                user = get_user_by_inquiry_id(inquiry_id)
                email = (user or {}).get("email")
        if email:
            try:
                restart_kyc_for_email(email)
            except PersonaError as exc:
                st.error(str(exc))
                return
            st.rerun()
        _reset()
        st.rerun()


def check_status_page(auto: bool = True) -> None:
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
    allowed = bool(summary.get("allowed"))
    blocked_by_watchlist = bool(summary.get("blocked_by_watchlist"))
    watchlist_reports = summary.get("watchlist_reports") or []

    persona_status_l = (persona_status or "").lower()
    persona_decision_l = (persona_decision or "").lower()

    if allowed:
        internal_status = "VERIFIED"
    elif blocked_by_watchlist or persona_decision_l in ("declined", "rejected") or persona_status_l in (
        "declined",
        "failed",
        "rejected",
    ):
        internal_status = "FAILED"
    else:
        internal_status = "PENDING"

    st.session_state["kyc_status"] = internal_status
    update_user_status_by_inquiry(inquiry_id, internal_status)

    st.write(f"Persona status: {persona_status}, decision: {persona_decision or 'none'}")

    if internal_status == "VERIFIED":
        st.success("Your identity has been verified and passed sanctions / watchlist screening.")
        st.session_state["step"] = "billing"
        st.rerun()
    elif internal_status == "FAILED":
        if watchlist_reports:
            st.error("Verification failed due to sanctions or watchlist checks.")
            for r in watchlist_reports:
                st.write(f"- {r.get('type')}: status={r.get('status')}, decision={r.get('decision')}")
        else:
            st.error("Verification did not pass. Please contact support or try again.")
        st.session_state["step"] = "kyc_failed"
        st.rerun()
    else:
        if auto:
            st.info("Verification is still pending. Complete the steps in the Persona window, then check again.")
        if st.button("Refresh"):
            time.sleep(1)
            st.rerun()
        if st.button("Back"):
            st.session_state["step"] = "verify"
            st.rerun()


def dashboard_page() -> None:
    st.header("Dashboard")
    st.success("KYC: VERIFIED")
    st.write(f"Email: {st.session_state.get('email', '')}")

    email = st.session_state.get("email")
    if email:
        latest = _latest_checkout_for_email(email)
        if latest and latest.get("stripe_payment_status") == "paid":
            st.success(f"Payment received for: {latest.get('product_key')}")
        elif latest:
            st.info(
                f"Latest checkout: status={latest.get('stripe_status')}, payment_status={latest.get('stripe_payment_status')}"
            )
        else:
            st.warning("No payment found yet. Proceed to checkout.")
            if st.button("Choose a plan"):
                st.session_state["step"] = "billing"
                st.rerun()

    if st.button("Start over"):
        _reset()
        st.rerun()


def billing_page() -> None:
    st.header("Choose your plan")
    st.write("Select a product to proceed to Stripe Checkout.")

    if not _stripe_enabled():
        st.error("Stripe is not configured. Set STRIPE_SECRET_KEY in your environment.")
        st.stop()

    email = st.session_state.get("email")
    inquiry_id = st.session_state.get("inquiry_id")
    if not email or not inquiry_id:
        st.error("Missing session context. Please restart the flow.")
        if st.button("Start over"):
            _reset()
            st.rerun()
        st.stop()

    col1, col2 = st.columns(2)
    with col1:
        st.subheader("$1977 – Agency Pro Bundle")
        st.write("Features:")
        st.write("- Basic")
        st.write("- Full stack WordPress")
        st.write("- Agentic workflow setup")
        if st.button("Checkout – Agency Pro", key="checkout_agency_pro"):
            try:
                url = create_checkout_session(product_key="agency_pro", email=email, inquiry_id=inquiry_id)
            except Exception as exc:
                st.error(f"Stripe error: {exc}")
                return
            st.session_state["stripe_session_url"] = url

    with col2:
        st.subheader("$97 – WeOwn Lite Setup")
        st.write("Features:")
        st.write("- Basic WordPress personal website")
        st.write("- AnythingLLM open-source model setup")
        if st.button("Checkout – WeOwn Lite", key="checkout_weown_lite"):
            try:
                url = create_checkout_session(product_key="weown_lite", email=email, inquiry_id=inquiry_id)
            except Exception as exc:
                st.error(f"Stripe error: {exc}")
                return
            st.session_state["stripe_session_url"] = url

    url = st.session_state.get("stripe_session_url")
    if url:
        st.success("Redirecting you to Stripe Checkout...")
        st.link_button("Continue to Stripe", url)
        st.markdown(
            f"""
            <meta http-equiv="refresh" content="0; url={url}">
            """,
            unsafe_allow_html=True,
        )

    if st.button("Back"):
        st.session_state["step"] = "dashboard"
        st.rerun()


def payment_success_page(session_id: Optional[str]) -> None:
    st.header("Payment successful")
    if not _stripe_enabled():
        st.warning("Stripe is not configured on this server; cannot verify payment.")
    elif session_id:
        try:
            sess = _sync_checkout_session(session_id)
            st.write(f"Stripe session: {sess.get('id')}")
            st.write(f"Payment status: {sess.get('payment_status')}")
        except Exception as exc:
            st.error(f"Failed to verify payment with Stripe: {exc}")
    else:
        st.warning("Missing Stripe session_id")

    st.session_state["step"] = "dashboard"
    if st.button("Continue"):
        st.rerun()


def payment_cancel_page() -> None:
    st.header("Payment canceled")
    st.info("You canceled the checkout. You can try again anytime.")
    if st.button("Back to plans"):
        st.session_state["step"] = "billing"
        st.rerun()


def failed_page() -> None:
    st.header("KYC Failed")
    st.error("Your verification did not pass.")
    if st.button("Start over"):
        email = st.session_state.get("email")
        if not email:
            inquiry_id = st.session_state.get("inquiry_id")
            if inquiry_id:
                user = get_user_by_inquiry_id(inquiry_id)
                email = (user or {}).get("email")
        if email:
            try:
                restart_kyc_for_email(email)
            except PersonaError as exc:
                st.error(str(exc))
                return
            st.rerun()
        _reset()
        st.rerun()


def main() -> None:
    st.set_page_config(page_title="Payless Tax Persona KYC", layout="centered")
    init_db()

    qp = st.query_params
    payment_flag = qp.get("payment")
    if isinstance(payment_flag, list):
        payment_flag = payment_flag[0] if payment_flag else None
    session_id = qp.get("session_id")
    if isinstance(session_id, list):
        session_id = session_id[0] if session_id else None

    if payment_flag == "success":
        st.session_state["step"] = "payment_success"
        st.session_state["_stripe_return_session_id"] = session_id
    elif payment_flag == "cancel":
        st.session_state["step"] = "payment_cancel"

    step = st.session_state.get("step", "start")
    if step == "start":
        start_page()
    elif step == "verify":
        verify_page()
    elif step == "check":
        check_status_page(auto=True)
    elif step == "billing":
        billing_page()
    elif step == "payment_success":
        payment_success_page(st.session_state.get("_stripe_return_session_id"))
    elif step == "payment_cancel":
        payment_cancel_page()
    elif step == "dashboard":
        dashboard_page()
    elif step == "kyc_failed":
        failed_page()
    else:
        _reset()
        start_page()


if __name__ == "__main__":
    main()
