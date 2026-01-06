# Twilio Bridge - Dial Pad

Simple dial pad interface for Twilio voice calls.

## Setup

1. Install dependencies:
```bash
npm install
```

2. Create `.env` file with your Twilio credentials:
```
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_API_KEY_SID=your_api_key_sid
TWILIO_API_KEY_SECRET=your_api_key_secret
TWILIO_TWIML_APP_SID=your_twiml_app_sid
```

3. Generate a token:
```bash
node bridge_identity.js
```

4. Start the TwiML server:
```bash
npm start
```

5. Open `dialpad.html` in your browser

## Usage

1. Run `node bridge_identity.js` to get a Twilio access token
2. Paste the token into the dial pad interface
3. Click "Connect" to initialize the device
4. Enter a phone number (include country code, e.g., +1234567890)
5. Click "Call" to make a call

## Files

- `bridge_identity.js` - Generates Twilio access tokens
- `twiml-server.js` - Webhook server for handling calls
- `dialpad.html` - User interface
- `package.json` - Dependencies

## Notes

- For testing, use Twilio's echo test number: +14158861234
- Trial accounts can only call verified numbers
- Use ngrok to expose the webhook server for testing: `ngrok http 3000`
