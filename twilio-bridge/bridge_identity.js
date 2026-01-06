require('dotenv').config();
const twilio = require('twilio');
const AccessToken = twilio.jwt.AccessToken;
const VoiceGrant = AccessToken.VoiceGrant;

const identity = 'Shahid';

const token = new AccessToken(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_API_KEY_SID,
  process.env.TWILIO_API_KEY_SECRET,
  { identity: identity }
);

const grant = new VoiceGrant({
  outgoingApplicationSid: process.env.TWILIO_TWIML_APP_SID,
  incomingAllow: true,
});

token.addGrant(grant);
console.log("Your Bridge Token:", token.toJwt());