// Copies the workflow JSON files from <src> to <dst>, swapping the AI nodes for the
// provider selected in AI_PROVIDER (openai | gemini). The repo keeps a single set of
// workflows written for OpenAI; for Gemini the embeddings and chat nodes are replaced.
const fs = require('fs');

const [src, dst] = process.argv.slice(2);
const provider = process.env.AI_PROVIDER === 'gemini' ? 'gemini' : 'openai';
const chatModel = process.env.GEMINI_CHAT_MODEL || 'gemini-flash-latest';
const embedModel = process.env.GEMINI_EMBED_MODEL || 'gemini-embedding-001';
const geminiCred = { googlePalmApi: { id: 'ragGeminiCred', name: 'Gemini RAG (auto)' } };

function adapt(wf) {
  const renamed = {};
  for (const node of wf.nodes) {
    if (node.type.endsWith('.embeddingsOpenAi')) {
      node.type = '@n8n/n8n-nodes-langchain.embeddingsGoogleGemini';
      node.typeVersion = 1;
      node.parameters = { modelName: `models/${embedModel}` };
    } else if (node.type.endsWith('.lmChatOpenAi')) {
      node.type = '@n8n/n8n-nodes-langchain.lmChatGoogleGemini';
      node.typeVersion = 1.2;
      node.parameters = { modelName: `models/${chatModel}`, options: {} };
    } else {
      continue;
    }
    node.credentials = geminiCred;
    const newName = node.name.replace('(OpenAI)', '(Gemini)');
    if (newName !== node.name) {
      renamed[node.name] = newName;
      node.name = newName;
    }
  }
  const connections = {};
  for (const [from, outputs] of Object.entries(wf.connections)) {
    for (const lists of Object.values(outputs)) {
      for (const list of lists) {
        for (const conn of list) {
          if (renamed[conn.node]) conn.node = renamed[conn.node];
        }
      }
    }
    connections[renamed[from] || from] = outputs;
  }
  wf.connections = connections;
}

fs.mkdirSync(dst, { recursive: true });
for (const file of fs.readdirSync(src).filter((f) => f.endsWith('.json'))) {
  // The graph extraction workflow calls the Gemini REST API directly (placeholder = model name).
  const raw = fs.readFileSync(`${src}/${file}`, 'utf8').split('__GEMINI_CHAT_MODEL__').join(chatModel);
  const wf = JSON.parse(raw);
  if (provider === 'gemini') adapt(wf);
  fs.writeFileSync(`${dst}/${file}`, JSON.stringify(wf));
}
console.log(`[adapt] ${provider}`);
