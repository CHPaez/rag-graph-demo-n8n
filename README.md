# Demo RAG vectorial vs GraphRAG con n8n (pgvector + Neo4j)

Demo para **comparar dos formas de consultar manuales técnicos con lenguaje natural**, lado a lado:

- **RAG vectorial:** el manual se trocea, se vectoriza y se guarda en PostgreSQL + pgvector. El agente trae los 4 trozos más parecidos a la pregunta.
- **GraphRAG:** un LLM extrae **entidades y relaciones** de cada trozo y las guarda en **Neo4j**. El agente responde recorriendo el grafo (vecinos a 1 y 2 saltos).
- **Híbrido:** el agente usa vectores como punto de entrada y el grafo para seguir relaciones.

Todo orquestado con n8n y construido **sobre** [`rag-demo-n8n`](https://github.com/CHPaez/rag-demo-n8n) (el pipeline vectorial original sigue igual; se agregó el grafo). Contenido y manuales **ficticios**.

> Explicación conceptual con diagramas, comparación y resultados medidos: [`docs/explicacion-rag-y-grafos.md`](docs/explicacion-rag-y-grafos.md). Respuestas completas de las pruebas: [`docs/resultados-pruebas.md`](docs/resultados-pruebas.md).

---

## Inicio rápido

Requisitos: Docker con Compose, ~**1.2 GB de RAM libre** (ver [Recursos](#recursos)) y una API key de Gemini (gratis, <https://aistudio.google.com/apikey>).

```bash
git clone https://github.com/CHPaez/rag-graph-demo-n8n.git
cd rag-graph-demo-n8n
./setup.sh gemini TU_API_KEY      # crea .env (contraseñas generadas); o: python3 setup_web.py
docker compose up -d              # db + neo4j + n8n (la primera vez descarga ~3.4 GB)
```

Servicios (solo `127.0.0.1`, no hay nada publicado):

| Servicio | URL / puerto |
|---|---|
| n8n | <http://localhost:5679> (usuario y contraseña en `.env`: `OWNER_EMAIL` / `OWNER_PASSWORD`) |
| Neo4j Browser | <http://localhost:7474> (usuario `neo4j`, contraseña `NEO4J_PASSWORD` de `.env`) |
| Neo4j bolt | `127.0.0.1:7687` |

Proyecto Compose `ragraph-demo`, volúmenes propios (`ragraph-demo_db-data`, `_n8n-data`, `_neo4j-data`). Si falta alguna variable, `./setup.sh` la completa sin tocar las existentes.

## Usar la demo

En n8n (flujos creados y publicados al arrancar):

1. **`01 - Ingesta de manuales (vectorizar)`** → *Execute workflow*. Vectoriza todo `manuales/` en pgvector.
2. **`03 - Extraccion del grafo (LLM -> Neo4j)`** → *Execute workflow*. Borra el grafo, extrae con Gemini (una llamada por trozo, ~3 min con 13 trozos) y escribe en Neo4j. Al final muestra el resumen de nodos y relaciones.
3. Ver el grafo: `./scripts/graph-summary.sh`, o en <http://localhost:7474>:
   ```cypher
   MATCH (a:Entity)-[r]->(b:Entity) RETURN a, r, b LIMIT 100
   ```
4. Preguntar:
   - **`06 - Comparador`** → *Open chat*: contesta con los tres caminos y muestra lo que recuperó cada uno. Por consola: `./scripts/compare.sh "¿Qué puerto usa el HIS por defecto?"`.
   - O cada agente por separado: `02` (vector), `04` (grafo), `05` (híbrido), cada uno con chat y con webhook (`POST /webhook/ask-vector|ask-graph|ask-hybrid` con `{"question": "..."}`).

Preguntas de ejemplo: *¿Cómo es la trama ORU^R01 que envía el monitor?*, *¿Qué significa el código de error E-214?*, *¿Qué puerto usa el HIS por defecto?*, *El monitor reintenta una y otra vez, ¿qué reviso?*, y las de varios saltos: *Si cambio el puerto de escucha del HIS, ¿qué equipos hay que actualizar?*

### Los manuales

`manuales/manual-ejemplo-monitor-m100.md` (original) y `manuales/guia-integracion-his-connect.md` (nuevo, ficticio, referencia al primero: mismo puerto 6661, error E-214, equipos que dependen del HIS). Con un solo manual corto el grafo no aporta; con dos que se cruzan hay algo que recorrer. La **extracción del grafo solo lee `.md` y `.txt`**; la ingesta vectorial admite también PDF.

## Resultados medidos (resumen)

Gemini gratis, modelo de chat `gemini-flash-lite-latest`, 6 preguntas x 3 caminos, primer intento sin errores (detalle y respuestas en [`docs/resultados-pruebas.md`](docs/resultados-pruebas.md)):

| Pregunta | Vector | Grafo | Híbrido |
|---|---|---|---|
| P1 trama ORU^R01 | Correcta, con la trama literal | **Parcial**: segmentos y orden, sin la trama de ejemplo | Correcta, trama + campos |
| P2 significado de E-214 | Correcta (3 causas) | Correcta pero **parcial** (una causa) | Correcta (3 causas) |
| P3 puerto del HIS | 6661 | 6661 | 6661 |
| P4 "reintenta sin parar" | Correcta, breve (2 causas) | Correcta, más pasos de revisión | Correcta (ACK, MSH-10, cola) |
| P5 qué actualizar si cambia el puerto (2 manuales) | Correcta (3 equipos) | Correcta (+ HIS-Connect y `his-connect.conf`) | Correcta (3 equipos + reinicio) |
| P6 E-214 un domingo 03:00, ¿qué más se afecta? | Correcta (reinicio; CA-2) | **Causa incorrecta** (cola saturada, omite el reinicio) y suma GW-7 | Correcta, cita `CA-2 -[DEPENDS_ON]-> HIS-Connect` |
| Tiempo medio por respuesta | 9.5 s | 16.9 s | 12.2 s |
| Llamadas a herramientas (media) | 1.0 | 2.7 | 2.0 |

Lectura honesta: **con dos manuales cortos los vectores casi igualan al grafo** (los trozos ya contienen las relaciones) y el grafo perdió detalle literal (P1) y falló una causa (P6). El híbrido fue el más completo. La ventaja del grafo debería notarse con muchos documentos; **no se probó a esa escala**.

## Cómo funciona

```
 flujo 01  manuales ──▶ trozos ──▶ embeddings ──▶ pgvector (tabla manuales)
 flujo 03  manuales ──▶ secciones ──▶ Gemini extrae JSON ──▶ Cypher ──▶ Neo4j
                                      (reintento 30 s ante 429/5xx, pausa 5 s entre trozos)
 02 vector: pregunta ──▶ pgvector (4 trozos) ──▶ LLM
 04 grafo : pregunta ──▶ LLM elige un término ──▶ Cypher fijo en Neo4j (entidad + 1-2 saltos) ──▶ LLM
 05 híbrido: ambas herramientas; primero vector, luego grafo con los nombres hallados
```

Modelo del grafo: `(:Entity {key,name,type,description})`, `(:Chunk {id,text,source})`, `(:Chunk)-[:MENTIONS]->(:Entity)` y relaciones semánticas (`CONNECTS_TO`, `LISTENS_ON`, `RAISES`, `DEPENDS_ON`...) con una propiedad `evidence`. Resultado medido: 13 trozos, 39 entidades, 54 relaciones + 69 `MENTIONS`.

### Costo de la extracción

Una llamada al LLM por trozo: **13 llamadas** con los dos manuales de ejemplo (~3 min). Está pensado **solo para los manuales de ejemplo**: con el nivel gratuito de Gemini, un manual grande agotaría la cuota (`429`). El flujo reintenta hasta 6 veces con 30 s de espera y pausa 5 s entre trozos; si la cuota se agota, falla con un mensaje claro y se puede relanzar más tarde. Además, cada trozo se envía a Google (ver privacidad).

## Qué se automatiza al arrancar

`scripts/bootstrap.sh` (antes de n8n): crea el administrador, las credenciales con ID fijo (Postgres, **Neo4j HTTP**, OpenAI, Gemini; en cada arranque) e importa y **publica** los flujos (la primera vez o al cambiar de proveedor/modelo/revisión de flujos). `scripts/adapt-workflows.js` reemplaza los nodos de OpenAI por los de Gemini y fija el modelo en el flujo 03. Cambiar una key: editar `.env` y `docker compose up -d --force-recreate n8n`.

## Detalles técnicos que importan

- **Neo4j:** imagen oficial `neo4j:5.26.32-community` (tag verificado en Docker Hub; línea LTS 5.26). **Licencia: GPLv3** (Community); Enterprise es comercial y no se usa. Heap 256-512 MB, page cache 128 MB, límite de contenedor 1 GB.
- **n8n 2.42.7 no tiene nodo de Neo4j** (verificado dentro de la imagen). Se usa la API HTTP transaccional (`POST /db/neo4j/tx/commit`) con Basic Auth.
- **El nodo `toolHttpRequest` de LangChain no funciona con el Agente 3.1** de esta versión (`has a "supplyData" method but no "execute" method`); se usa el nodo **HTTP Request normal como herramienta** (`httpRequestTool`).
- **Seguridad de las consultas:** el LLM no escribe Cypher; solo aporta el parámetro `$term` de una consulta fija. Aun así el agente usa el usuario `neo4j` (admin): para algo real, crear un usuario de solo lectura.
- **Gemini:** durante las pruebas `gemini-flash-latest` (el valor por defecto) devolvió `503 high demand` de forma sostenida, así que **todas las pruebas se hicieron con `GEMINI_CHAT_MODEL=gemini-flash-lite-latest`**. Con otro modelo las respuestas pueden cambiar.
- Los límites gratuitos de Gemini cambian; en las pruebas no hubo `429`.
- Para ejecutar un flujo por consola sin chocar con el puerto interno del broker de tareas: `docker compose exec -e N8N_RUNNERS_BROKER_PORT=5690 n8n n8n execute --id=ragIngesta01`.

## Recursos

Límites en `docker-compose.yml` y uso medido con `docker stats --no-stream` tras las pruebas:

| Contenedor | Uso medido | Límite |
|---|---|---|
| neo4j | ~660 MiB | 1 GiB |
| n8n | ~460 MiB | 800 MiB |
| db (pgvector) | ~30 MiB | 300 MiB |
| **Total** | **~1.15 GiB** | 2.1 GiB |

## Comandos útiles

```bash
docker compose ps                  # estado
docker compose logs -f n8n         # logs (incluye mensajes [bootstrap])
./scripts/graph-summary.sh         # conteos y muestra del grafo
./scripts/compare.sh "pregunta"    # los tres agentes lado a lado
docker compose down                # apagar (conserva datos)
docker compose down -v             # apagar y BORRAR todo (flujos, vectores, grafo)
```

## Estado de validación

**Verificado de punta a punta** (n8n 2.42.7, Neo4j 5.26.32, pgvector pg18, Gemini real): arranque con bootstrap (credenciales, importación y publicación de 6 flujos); ingesta vectorial (8 trozos en pgvector); extracción del grafo (13 trozos, 39 entidades, 54 relaciones, 69 `MENTIONS`; repetida dos veces); 6 preguntas x 3 caminos por webhook y el comparador `06` (con una pregunta).

**No verificado:**
- `setup_web.py` (asistente web) en este repo: solo se añadió `NEO4J_PASSWORD` y el puerto 5679 y se comprobó que compila; no se ejecutó. Su botón "Vectorizar" y sus chequeos son del repo original y no conocen Neo4j.
- `setup.sh` interactivo (pantalla): solo el modo no interactivo (`./setup.sh gemini KEY`) y la sintaxis.
- Proveedor OpenAI: heredado del repo original; la extracción del grafo está escrita para la API de Gemini y no funciona con OpenAI.
- `gemini-flash-latest` (modelo por defecto): no se pudo probar por los `503`.
- Los chats (`Open chat`) en el navegador: se probó por webhook, no desde la interfaz.
- Escala: dos documentos pequeños; no se midió cómo se comportan vectores y grafo con muchos documentos.
- Publicación en un dominio (nginx/Cloudflare): no hecha ni probada; todo es local.

## Notas importantes

- **Confidencialidad:** el texto de los manuales **se envía al proveedor de IA** (Google, en el nivel gratuito puede usarse para mejorar sus productos). Solo manuales no confidenciales.
- Los secretos viven en `.env` (no se sube a git). Guardá `N8N_ENCRYPTION_KEY`.
- Re-ejecutar la ingesta vectorial **duplica** los vectores (`docker compose exec db psql -U rag -d rag -c "DROP TABLE manuales;"` para empezar de cero); el flujo 03 sí reconstruye el grafo desde cero cada vez.
- Entidades duplicadas en el grafo (`M-100`, `M100`, `ACME M-100`): falta una pasada de fusión.

## Estructura del repo

```
.
├── docker-compose.yml          # db (PostgreSQL + extensión pgvector: vectores) + neo4j (base de grafos) + n8n, proyecto ragraph-demo
├── setup.sh / setup_web.py     # configuración (.env) heredada, con NEO4J_PASSWORD
├── .env.example
├── scripts/
│   ├── bootstrap.sh            # admin, credenciales, importación y publicación de flujos
│   ├── adapt-workflows.js      # openai -> gemini; modelo del flujo 03
│   ├── compare.sh              # pregunta a los 3 agentes (webhook /compare)
│   └── graph-summary.sh        # conteos y muestra del grafo
├── manuales/                   # manual M-100 + guía HIS-Connect (ficticios)
├── workflows/
│   ├── 01-ingesta.json         # vectorizar (original)
│   ├── 02-chat-agente.json     # RAG vectorial (original + webhook)
│   ├── 03-extraccion-grafo.json  # el LLM extrae entidades y relaciones -> Neo4j (grafo)
│   ├── 04-chat-grafo.json      # GraphRAG: responde recorriendo el grafo
│   ├── 05-chat-hibrido.json    # híbrido: vectores (punto de entrada) + grafo (conexiones)
│   └── 06-comparador.json      # vectores vs grafo vs híbrido, lado a lado
└── docs/
    ├── arquitectura-vectores-y-grafos.md  # una página: arquitectura y cómo se conectan
    ├── explicacion-rag-y-grafos.md        # explicación para principiantes
    └── resultados-pruebas.md              # resultados medidos
```
