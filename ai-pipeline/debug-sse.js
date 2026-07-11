// debug-sse.js — dump raw SSE events from upstream API
const https = require('https');
const fs = require('fs');
const path = require('path');
const TOKEN_FILE = path.join(__dirname, 'data', 'session-tokens.json');

let cookies = '';
try {
  const data = JSON.parse(fs.readFileSync(TOKEN_FILE, 'utf8'));
  cookies = data.cookies.map(c => `${c.name}=${c.value}`).join('; ');
  console.log('Cookies loaded:', data.cookies.length);
} catch(e) {
  console.log('No cookies file');
  process.exit(1);
}

const prompt = 'Say exactly: Hello World ABC DEF GHI';
const msgBody = JSON.stringify({
  action: 'next',
  messages: [{
    id: 'debug-' + Date.now(),
    author: { role: 'user' },
    create_time: Date.now() / 1000,
    content: { content_type: 'text', parts: [prompt] }
  }],
  model: 'gpt-5-5-thinking',
  timezone_offset_min: -480,
  timezone: 'Asia/Shanghai'
});

const options = {
  hostname: 'ai.nbai88.top',
  port: 443,
  path: '/backend-api/f/conversation',
  method: 'POST',
  headers: {
    'Cookie': cookies,
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'text/event-stream',
    'Origin': 'https://ai.nbai88.top',
    'Referer': 'https://ai.nbai88.top/'
  }
};

console.log('Sending request to ai.nbai88.top...');
const req = https.request(options, (res) => {
  console.log('Status:', res.statusCode);
  let buffer = '';
  let eventCount = 0;

  res.on('data', (chunk) => {
    buffer += chunk.toString();
    const parts = buffer.split(/\n\n+/);
    buffer = parts.pop() || '';

    for (const part of parts) {
      if (!part.trim()) continue;
      eventCount++;
      const lines = part.split('\n');
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const json = line.slice(6);
          if (json === '[DONE]') {
            console.log(`\n[EVENT ${eventCount}] [DONE]`);
            continue;
          }
          try {
            const d = JSON.parse(json);
            const msg = d.v?.message || d.message;
            const summary = {
              has_o: !!d.o,
              o: d.o,
              v_str: typeof d.v === 'string' ? d.v.substring(0, 60) : null,
              msg_role: msg?.author?.role,
              msg_status: msg?.status,
              parts_len: (msg?.content?.parts || []).length,
              parts_str: (msg?.content?.parts || []).map(p => typeof p === 'string' ? p.substring(0, 50) : typeof p).join(' | '),
              conv_id: d.conversation_id
            };
            console.log(`[EVENT ${eventCount}]`, JSON.stringify(summary, null, 2).replace(/\n/g, ' '));
          } catch(e) {
            console.log(`[EVENT ${eventCount}] RAW:`, line.substring(0, 100));
          }
        }
      }
    }
  });

  res.on('end', () => {
    console.log('\nTotal events:', eventCount);
    if (buffer.trim()) console.log('Remaining buffer:', buffer.substring(0, 300));
  });
});

req.on('error', (e) => console.error('Error:', e.message));
req.write(msgBody);
req.end();
