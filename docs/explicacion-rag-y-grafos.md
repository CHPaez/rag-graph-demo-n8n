# RAG, vectores y grafos: explicación sencilla + infraestructura del demo

Documento para quien está empezando con esto. Va de lo más simple a lo más técnico.
No hace falta saber programar para entender las secciones 1 a 4.

---

## 1. El problema

Tenemos manuales técnicos largos (por ejemplo, la interfaz HL7 de un monitor médico).
Queremos **preguntarles en lenguaje natural**:

> "¿Qué significa el código de error E-214?"

Un modelo de IA (ChatGPT, Gemini...) **no conoce nuestros manuales**. Si le preguntamos
directo, inventa o dice que no sabe. Y pegarle el manual completo en cada pregunta es
lento, caro y a veces ni cabe.

## 2. La solución: RAG

**RAG** = *Retrieval-Augmented Generation* (generación aumentada con recuperación).

La idea en una frase: **antes de preguntarle a la IA, buscamos los 4 párrafos del manual
que más se parecen a la pregunta y se los entregamos junto con la pregunta.**

Analogía: es un examen a libro abierto. El alumno (la IA) no se sabe el libro, pero
tiene un índice muy bueno que le abre el libro justo en las páginas correctas.

```
  Pregunta ──▶ [Buscar los párrafos más parecidos] ──▶ [IA redacta la respuesta
                       en nuestros manuales               usando SOLO esos párrafos]
```

## 3. ¿Cómo "busca por parecido"? Embeddings y vectores

Una computadora no entiende significado, entiende números. Un **modelo de embeddings**
convierte un texto en una lista de números (un **vector**) que representa su significado.

```
 "El monitor reintenta el envío"   ──▶  [0.12, -0.80, 0.33, ... ]   (cientos de números)
 "El equipo vuelve a mandar datos" ──▶  [0.10, -0.77, 0.35, ... ]   ← muy parecido
 "La receta lleva dos huevos"      ──▶  [-0.60, 0.21, 0.90, ... ]   ← muy distinto
```

Textos con significado parecido quedan **cerca** en ese espacio, **aunque no compartan
ninguna palabra**. Por eso la búsqueda funciona mejor que un Ctrl+F.

Imaginalo como un mapa: cada párrafo es un punto, y los párrafos que hablan de lo
mismo viven en el mismo barrio.

```
        ▲
        │      · error E-214        · reintentos
        │        · códigos de error   · timeout
        │
        │                                   · puertos     · IP del HIS
        │                                     · conexión
        │  · receta de cocina
        └──────────────────────────────────────────────────▶
```

Cuando llega una pregunta, también se convierte en punto, y se buscan los 4 puntos
más cercanos. Eso es **búsqueda vectorial** (la hace la extensión **pgvector** dentro de
PostgreSQL).

## 4. Las dos fases del demo

### Fase A. Ingesta (se hace una vez por manual)

```
┌──────────┐   ┌───────────────┐   ┌─────────────┐   ┌──────────────────┐
│  Manual  │──▶│ Dividir en    │──▶│ Embeddings  │──▶│ Guardar en       │
│ .md/.pdf │   │ trozos de     │   │ texto→vector│   │ PostgreSQL       │
│          │   │ ~800 caract.  │   │             │   │ (vector + texto) │
└──────────┘   └───────────────┘   └─────────────┘   └──────────────────┘
```

¿Por qué trozos? Un manual entero es un "punto" demasiado borroso. Un párrafo de ~800
caracteres tiene un significado concreto y se encuentra con precisión.

### Fase B. Consulta (en cada pregunta)

```
┌──────────┐   ┌────────────┐   ┌────────────────┐   ┌───────────┐   ┌───────────┐
│ Pregunta │──▶│ Embedding  │──▶│ pgvector: los  │──▶│    LLM    │──▶│ Respuesta │
│          │   │ (vector)   │   │ 4 trozos más   │   │ redacta   │   │ basada en │
│          │   │            │   │ cercanos       │   │ con ellos │   │ el manual │
└──────────┘   └────────────┘   └────────────────┘   └───────────┘   └───────────┘
```

Ventajas: más **barato** y **rápido** (la IA lee 4 párrafos, no 200 páginas), más
**preciso** y **actualizable** (cambiás el manual, no reentrenás nada).

---

## 5. Grafos de conocimiento y GraphRAG (implementado en este repo)

> **Alcance:** este repositorio implementa las dos cosas y las pone lado a lado: RAG con
> vectores (pgvector) y GraphRAG (Neo4j), más un agente híbrido que usa ambas. Las cifras de
> esta sección son **medidas** (detalle completo en [`resultados-pruebas.md`](resultados-pruebas.md)).

### 5.1 Qué es un grafo de conocimiento

Guarda **entidades** (los nodos: cosas) y **relaciones** (las flechas: cómo se conectan).
Cada dato es una frase corta: *sujeto → relación → objeto*. Un extracto real del grafo que
genera el demo (consulta `MATCH (a:Entity)-[r]->(b:Entity) RETURN a.name, type(r), b.name`):

```
   (ACME M-100) ──CONNECTS_TO──▶ (HIS-Connect) ◀──CONNECTS_TO── (GW-7)
        │                            │   ▲
     RAISES                  LISTENS_ON  └──DEPENDS_ON── (CA-2)
        ▼                            ▼
     (E-214)                  (Puerto 6661) ◀──CONFIGURED_BY── (listener.port)
        │
   CAUSED_BY ──▶ (HIS)
```

Analogía: los vectores son un **buscador** ("dame lo que se parece a esto"); el grafo es un
**mapa de metro** ("¿cómo llego de A a B y por dónde paso?").

### 5.2 Qué se esperaba y qué se midió

| Tipo de pregunta | Vectores | Grafo | Qué pasó en las pruebas |
|---|---|---|---|
| Dato puntual ("¿qué puerto usa el HIS?") | Muy bien | Bien | Los tres caminos respondieron bien (6661). |
| Texto literal ("la trama ORU^R01") | Muy bien | Flojo | El grafo respondió el orden de segmentos pero **no devolvió la trama de ejemplo**: se pierde en la extracción. |
| Seguir relaciones entre documentos | Bien si todo cae en un trozo | Bien | Con manuales tan cortos, el trozo "Puertos" de la guía ya listaba los 3 equipos: **los vectores también acertaron**. |
| Causa + efecto repartidos en secciones | Acertó (esta vez) | **Falló la causa** | El grafo se quedó con la causa "cola saturada" y omitió el reinicio dominical; además sumó un equipo (GW-7) que los manuales no mencionan como afectado por el reinicio. |
| Trazabilidad ("¿por qué dices eso?") | Muestra trozos | Muestra la arista | El híbrido citó `CA-2 -[DEPENDS_ON]-> HIS-Connect`. |

Conclusión honesta: **con un corpus de dos manuales cortos no se demostró una ventaja
clara del grafo sobre los vectores**. Lo que sí se vio es que el **híbrido** fue el más
completo y consistente (trama literal + campos, tres causas del E-214, cadena causal con la
arista citada). La ventaja del grafo aparece cuando hay decenas de documentos y los vectores
ya no traen todos los trozos necesarios; este demo no llega a esa escala.

### 5.3 Cómo funciona (lo que está implementado)

**Ingesta del grafo (flujo `03`, una llamada al LLM por trozo):**

```
┌──────────┐   ┌─────────────┐   ┌─────────────────────┐   ┌─────────────────┐
│ Manuales │──▶│ Trozos por  │──▶│ Gemini EXTRAE       │──▶│ Neo4j (MERGE)   │
│ .md/.txt │   │ sección "##"│   │ entidades+relaciones│   │ Entity, Chunk,  │
│          │   │ (13 trozos) │   │ (JSON), con reintento│  │ MENTIONS, ...   │
└──────────┘   └─────────────┘   │ y pausa de 5 s      │   └─────────────────┘
                                 └─────────────────────┘
        (en paralelo, flujo 01: los mismos manuales ──▶ embeddings ──▶ pgvector)
```

Resultado medido: **13 trozos → 39 entidades, 54 relaciones semánticas + 69 `MENTIONS`**,
13 llamadas a Gemini, ~3 minutos.

**Consulta (tres agentes de n8n con el mismo LLM):**

```
 02 Vector            04 Grafo                      05 Híbrido
 Pregunta             Pregunta                      Pregunta
   │                    │                             │
   ▼                    ▼                             ▼
 PGVector (4 trozos)  Neo4j: entidad coincidente    1) PGVector: trozos literales
   │                  + vecinos a 1 y 2 saltos      2) Neo4j: entidades nombradas en esos
   ▼                    │                              trozos + vecinos (1-2 saltos)
 LLM redacta            ▼                             ▼
                      LLM redacta                   LLM redacta con ambas fuentes
```

El "híbrido" lo decide el agente: la instrucción le pide usar primero la búsqueda semántica
(punto de entrada) y luego consultar el grafo con los nombres que aparecen en esos trozos.
No hay un enlace automático trozo-vectorial → nodo; el agente hace de puente.

### 5.4 Lo que aprendimos al construirlo (gotchas)

- **Resolución de entidades:** el LLM nombra igual cosas distintas ("Monitor ACME M-100",
  "M-100", "M100"). Se mejoró con reglas en el prompt, pero quedan duplicados (`M-100` y
  `M100` conviven con `ACME M-100`). En producción hay que hacer una pasada de fusión.
- **Pérdida de detalle:** el grafo guarda hechos en una frase por entidad; las tramas y
  tablas literales viven mejor en los trozos de texto.
- **Nodo HTTP como herramienta:** en n8n 2.42.7 el nodo "HTTP Request Tool" de LangChain
  (`toolHttpRequest`) falla con el Agente 3.1 (`has a "supplyData" method but no "execute"
  method`). Se usa el nodo HTTP Request normal como herramienta (`httpRequestTool`).
- **No existe nodo de Neo4j** en n8n 2.42.7: se usa su API HTTP transaccional
  (`POST /db/neo4j/tx/commit`) con credencial Basic Auth.
- **Cuotas y picos del proveedor:** el extractor reintenta con espera de 30 s ante `429`/`5xx`
  (máx. 6) y pausa 5 s entre trozos. Durante las pruebas `gemini-flash-latest` devolvió
  `503` de forma sostenida; se usó `gemini-flash-lite-latest`.

### 5.5 Dos formas de alojar el grafo

```
 Camino 1: grafo DENTRO de PostgreSQL           Camino 2 (el elegido): base de grafos aparte
 ┌─────────────────────────────────┐            ┌──────────┐      ┌──────────────┐
 │ PostgreSQL                      │            │   n8n    │─────▶│ PostgreSQL   │
 │  ├─ pgvector  (vectores)        │            │          │      │ (vectores)   │
 │  └─ extensión de grafos         │            │          │─────▶┌──────────────┐
 │     (p. ej. Apache AGE)         │            └──────────┘      │ Neo4j (grafo)│
 └─────────────────────────────────┘                              └──────────────┘
   + 1 solo servicio que mantener                 + herramienta especializada, navegador
   − menos maduro/documentado                       visual de grafos y Cypher
                                                  − 1 contenedor más y ~0.7 GB de RAM
```

### 5.6 Herramientas que existen (no usadas aquí)

| Herramienta | Qué es | Cuándo mirarla |
|---|---|---|
| **GraphRAG (Microsoft)** | Librería que construye el grafo y resúmenes por comunidades | Preguntas globales sobre muchos documentos |
| **LightRAG** | Alternativa más liviana, grafo + vectores | Si se busca algo más simple de operar |
| **Apache AGE** | Extensión de grafos para PostgreSQL | Camino 1 |

> Validar versión, licencia y requisitos antes de elegir; se nombran como punto de partida.

### 5.7 Qué falta para producción

| Tema | Estado |
|---|---|
| Actualización incremental del grafo (hoy se borra y se reconstruye) | No hecho |
| Fusión de entidades duplicadas | No hecho |
| PDF en la extracción del grafo (el flujo 01 sí admite PDF; el 03 solo `.md`/`.txt`) | No hecho |
| Permisos de solo lectura para el agente en Neo4j | No hecho (usa el usuario `neo4j`) |
| Evaluación con muchos documentos / más preguntas | No hecho |

---

## 6. Infraestructura del demo

### Piezas

| Pieza | Rol | Versión / licencia |
|---|---|---|
| **n8n** | Orquesta los flujos (ingesta, extracción del grafo, chats) con bloques visuales | 2.42.7 |
| **PostgreSQL + pgvector** | Guarda los vectores y busca por cercanía | pg18 + pgvector 0.8.x |
| **Neo4j Community** | Guarda el grafo (entidades y relaciones) y lo recorre con Cypher | 5.26.32 (LTS), licencia **GPLv3** (texto en la imagen: `/var/lib/neo4j/LICENSE.txt`) |
| **Modelo de embeddings** | Texto → vector (API externa) | Gemini `gemini-embedding-001` (gratis) u OpenAI `text-embedding-3-small` |
| **Modelo de chat (LLM)** | Redacta respuestas y **extrae el grafo** (API externa) | Gemini `gemini-flash-latest` (o `gemini-flash-lite-latest`) u OpenAI `gpt-4o-mini` (la extracción del grafo solo está probada con Gemini) |
| **Docker Compose** | Levanta todo con un comando | 3 contenedores: `db`, `neo4j`, `n8n` (proyecto `ragraph-demo`) |

Neo4j Community es GPLv3; la edición Enterprise es comercial y no se usa. Usar el servidor
como servicio interno no impone obligaciones a este repo, pero conviene que legal lo revise
antes de redistribuir la imagen.

### Diagrama de despliegue (local, sin publicar)

```
 ╔═════════════════════ Servidor (Linux, Docker) ═══════════════════════╗
 ║  127.0.0.1:5679   127.0.0.1:7474   127.0.0.1:7687   (solo local)     ║
 ║       │                │                │                            ║
 ║  ┌─── Docker Compose "ragraph-demo" ───────────────────────────┐    ║
 ║  │    ▼                ▼                ▼                       │    ║
 ║  │ ┌────────┐      ┌──────────────────────┐                     │    ║
 ║  │ │  n8n   │ HTTP │ Neo4j 5.26 Community │  límite 1 GB        │    ║
 ║  │ │ flujos │─────▶│ :7474 HTTP/Cypher    │  heap 256-512 MB    │    ║
 ║  │ │ 01..06 │ tx/  │ :7687 bolt           │  (grafo)            │    ║
 ║  │ │        │commit└──────────────────────┘                     │    ║
 ║  │ │        │ SQL  ┌──────────────────────┐                     │    ║
 ║  │ │        │─────▶│ PostgreSQL + pgvector│  límite 300 MB      │    ║
 ║  │ └───┬────┘      │ tabla "manuales"     │  (vectores)         │    ║
 ║  │     │ ./manuales (solo lectura)         └──────────────────────┘    ║
 ║  │     │  límite 800 MB                                         │    ║
 ║  └─────┼────────────────────────────────────────────────────────┘    ║
 ╚════════╪═════════════════════════════════════════════════════════════╝
          │ API (embeddings, chat, extracción)
          ▼
   Gemini u OpenAI (externo)

 Opcional (NO incluido ni desplegado): nginx + certbot + autenticación delante del puerto 5679,
 como en rag-demo-n8n. Aquí todo queda en 127.0.0.1.
```

### Decisiones de diseño (y por qué)

- **Todo escucha solo en `127.0.0.1`.** Docker publica puertos saltándose el firewall (ufw).
  Puertos distintos al demo original (5679/7474/7687) y volúmenes propios
  (`ragraph-demo_db-data`, `_n8n-data`, `_neo4j-data`) para convivir con otras demos.
- **Todo se crea solo al arrancar** (`scripts/bootstrap.sh`): administrador, credenciales
  (Postgres, Neo4j, Gemini/OpenAI), importación y publicación de los flujos.
- **Neo4j se consulta por HTTP** (no hay nodo oficial en n8n 2.42.7), con la credencial
  `Neo4j HTTP (auto)`; las consultas del agente son Cypher **fijo** y el LLM solo aporta un
  parámetro (`$term`), no escribe Cypher.
- **Cada agente tiene un webhook** (`/webhook/ask-vector|ask-graph|ask-hybrid|compare`) además
  del chat, para poder probar y comparar desde scripts.
- **Dos proveedores de IA intercambiables** (`AI_PROVIDER=gemini|openai`); los vectores de un
  proveedor no sirven para otro.

### Memoria medida (`docker stats --no-stream`, stack en reposo tras las pruebas)

| Contenedor | Uso | Límite |
|---|---|---|
| neo4j | ~660 MiB | 1 GiB |
| n8n | ~460 MiB | 800 MiB |
| db (pgvector) | ~30 MiB | 300 MiB |
| **Total** | **~1.15 GiB** | 2.1 GiB (suma de límites) |

El servidor de pruebas tiene 3.8 GB en total y compartía memoria con otros servicios y
sesiones: llegó a tener menos de 100 MB disponibles mientras arrancaba n8n. **Este stack
necesita ~1.2 GB libres además de lo que ya corra en la máquina.**

### Límites a tener presentes

- **Privacidad:** los textos viajan al proveedor de IA (y la extracción del grafo envía cada
  trozo). En el nivel gratuito de Gemini, Google puede usarlos para mejorar sus productos.
  Solo manuales **no confidenciales**.
- **Cuotas y disponibilidad:** `429` por cuota y `503` por demanda del modelo son posibles.
- **Duplicados:** ingestar dos veces el mismo archivo duplica los vectores (el grafo, en cambio,
  se reconstruye desde cero en cada ejecución del flujo 03).
- **Recursos:** primera descarga de imágenes ~3.4 GB (n8n 1.8 GB, pgvector 0.6 GB, Neo4j 1 GB).

---

## 7. Cómo probarlo (resumen)

1. `./setup.sh gemini TU_API_KEY` (o `python3 setup_web.py`) y `docker compose up -d`.
2. En n8n (`http://localhost:5679`): ejecutar **01 - Ingesta** (vectores) y **03 - Extracción
   del grafo** (Neo4j). Revisar el grafo en `http://localhost:7474`.
3. Abrir **06 - Comparador** → *Open chat* y preguntar; o por consola:
   `./scripts/compare.sh "¿Qué puerto usa el HIS por defecto?"`.

## 8. Glosario rápido

| Término | Significado simple |
|---|---|
| **LLM** | Modelo de IA que redacta texto (ChatGPT, Gemini) |
| **Embedding** | Convertir un texto en números que representan su significado |
| **Vector** | Esa lista de números |
| **pgvector** | Extensión de PostgreSQL para guardar vectores y buscar los más cercanos |
| **Chunk (trozo)** | Fragmento de un documento (~800 caracteres aquí) |
| **RAG** | Buscar trozos relevantes y dárselos a la IA para que responda con ellos |
| **Grafo de conocimiento** | Red de entidades y sus relaciones |
| **GraphRAG** | RAG que además recorre relaciones de un grafo |
| **Cypher** | Lenguaje de consultas de Neo4j |
| **Híbrido** | Agente que usa vectores como punto de entrada y el grafo para seguir relaciones |
| **n8n** | Herramienta visual para encadenar pasos (flujos) sin programar |
