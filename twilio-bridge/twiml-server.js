require('dotenv').config();
const express = require('express');
const twilio = require('twilio');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

app.post('/twiml/voice', (req, res) => {
    console.log('TwiML Voice Request - From:', req.body.From, 'To:', req.body.To);

    const twiml = new twilio.twiml.VoiceResponse();
    const numberToDial = req.body.To;
    
    if (!numberToDial) {
        twiml.say('Error: No number provided.', { voice: 'alice' });
        twiml.hangup();
    } else {
        if (numberToDial === '+14158861234' || numberToDial === '14158861234') {
            twiml.dial().number('+14158861234');
        } else {
            const dial = twiml.dial({
                timeout: 30,
                record: 'do-not-record',
                answerOnMedia: false,
                action: '/twiml/dial-status',
                method: 'POST'
            });
            dial.number(numberToDial);
        }
    }
    
    res.type('text/xml');
    res.send(twiml.toString());
});

app.post('/twiml/dial-status', (req, res) => {
    console.log('Dial Status:', req.body.DialCallStatus);
    
    const twiml = new twilio.twiml.VoiceResponse();
    
    if (req.body.DialCallStatus === 'completed') {
        twiml.say('Call completed. Goodbye.', { voice: 'alice' });
    } else if (req.body.DialCallStatus === 'busy') {
        twiml.say('The number is busy. Goodbye.', { voice: 'alice' });
    } else if (req.body.DialCallStatus === 'no-answer') {
        twiml.say('No answer. Goodbye.', { voice: 'alice' });
    } else if (req.body.DialCallStatus === 'failed' || req.body.DialCallStatus === 'canceled') {
        twiml.say('Call could not be completed. Goodbye.', { voice: 'alice' });
    } else {
        twiml.say('Call ended. Goodbye.', { voice: 'alice' });
    }
    
    twiml.hangup();
    res.type('text/xml');
    res.send(twiml.toString());
});

app.post('/twiml/status', (req, res) => {
    console.log('Call Status:', req.body.CallStatus);
    res.status(200).send('OK');
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
});

app.get('/', (req, res) => {
    res.json({
        message: 'Twilio TwiML Server',
        voice: '/twiml/voice',
        status: '/twiml/status'
    });
});

app.listen(PORT, () => {
    console.log(`TwiML Server running on port ${PORT}`);
    console.log(`Voice endpoint: http://localhost:${PORT}/twiml/voice`);
});

app.use((err, req, res, next) => {
    console.error('Server Error:', err);
    res.status(500).json({ error: 'Internal server error' });
});
