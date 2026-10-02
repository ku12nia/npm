const http = require('http');
const port = 3000;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Hello, this is a test of the Jenkins > GitHub > ArgoCD pipeline running successfully on Kubernetes!\n');
});

server.listen(port, () => {
  console.log(`Server is up and on standby at the port. ${port}`);
});
