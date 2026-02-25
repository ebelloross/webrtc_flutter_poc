const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8080 });
console.log('Signaling server on ws://0.0.0.0:8080');

wss.on('connection', (ws) => {
  ws.on('message', (msg) => {
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(msg);
      }
    });
  });
});
