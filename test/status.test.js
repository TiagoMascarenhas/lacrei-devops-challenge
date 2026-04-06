const http = require("http");

const options = {
  hostname: "localhost",
  port: 3000,
  path: "/status",
  method: "GET",
};

const req = http.request(options, (res) => {
  let data = "";
  res.on("data", (chunk) => { data += chunk; });
  res.on("end", () => {
    try {
      const json = JSON.parse(data);
      if (res.statusCode !== 200) {
        console.error("FAIL: status code esperado 200, recebido", res.statusCode);
        process.exit(1);
      }
      if (json.status !== "ok") {
        console.error("FAIL: campo status esperado ok, recebido", json.status);
        process.exit(1);
      }
      if (!json.timestamp) {
        console.error("FAIL: campo timestamp ausente");
        process.exit(1);
      }
      console.log("PASS: /status retornou", JSON.stringify(json));
      process.exit(0);
    } catch (e) {
      console.error("FAIL: resposta nao e JSON valido", e.message);
      process.exit(1);
    }
  });
});

req.on("error", (e) => {
  console.error("FAIL: erro na requisicao", e.message);
  process.exit(1);
});

req.end();
