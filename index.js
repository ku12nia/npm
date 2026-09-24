const http = require('http');
const port = 3000;

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Halo bang Dedi, ini uji coba pipeline Jenkins > GitHub > ArgoCD berjalan sukses di Kubernetes!\n');
});

server.listen(port, () => {
  console.log(`Server melek dan standby di port ${port}`);
});
