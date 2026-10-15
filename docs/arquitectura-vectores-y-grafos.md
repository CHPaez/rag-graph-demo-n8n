# Arquitectura del demo: vectores + grafo (en una página)

## La idea en 30 segundos

Queremos preguntarle a un manual técnico en lenguaje natural. Una IA no conoce nuestros
manuales, así que **primero buscamos los fragmentos relevantes y se los damos junto con la
pregunta** (esto se llama **RAG**). Hay dos formas de buscar:

| | Vectores (pgvector) | Grafo (Neo4j) |
|---|---|---|
| Guarda | Fragmentos de texto como números | Cosas y sus relaciones |
| Busca por | **Parecido de significado** | **Conexiones** entre cosas |
| Responde bien | "¿Qué significa el error E-214?" | "Si cambio el puerto del HIS, ¿qué se afecta?" |
| Analogía | Buscador / índice de un libro | Mapa de metro |

**Cómo se conectan:** los vectores encuentran *dónde empezar*; el grafo *recorre las
conexiones desde ahí*. Juntos son el modo **híbrido**.

## Arquitectura

```
                      Internet (HTTPS + contraseña, nginx)
                                   │
 ┌─────────────────────────────────▼──────────────────────────────────┐
 │  Docker Compose "ragraph-demo"                                     │
 │                                                                    │
 │   ┌───────────┐   vectores   ┌────────────────────┐                │
 │   │           │◀────────────▶│ PostgreSQL+pgvector│  "¿qué se      │
 │   │    n8n    │              └────────────────────┘   parece?"     │
 │   │ (orquesta │   relaciones ┌────────────────────┐                │
 │   │  flujos)  │◀────────────▶│       Neo4j        │  "¿qué está    │
 │   │           │              └────────────────────┘   conectado?"  │
 │   └─────┬─────┘                                                    │
 └─────────┼──────────────────────────────────────────────────────────┘
           │ API
           ▼
   Gemini (externo): embeddings + extracción del grafo + redacción
```

## Fase 1: Ingesta (una vez por manual)

```
                       ┌──▶ embeddings ──▶ pgvector      (flujo 01)
 Manual ──▶ trozos ────┤
 (.md/.pdf)  (~800 car)└──▶ el LLM extrae entidades ──▶ Neo4j   (flujo 03)
                            y relaciones de cada trozo
```

- **Vectores:** cada trozo se convierte en una lista de números que representa su
  significado. Textos parecidos quedan "cerca".
- **Grafo:** se le pide al LLM *"lista las entidades y cómo se relacionan"* y se guarda como
  nodos y flechas. Ejemplo: `Monitor M100 ─ENVÍA→ ORU^R01 ─VA_A→ HIS ─ESCUCHA_EN→ Puerto 6661`.
- Esto último es lo **caro**: una llamada al LLM por trozo.

## Fase 2: Consulta (cada pregunta)

```
              ┌── 02 Vectorial:  pregunta → 4 trozos parecidos ────────────┐
 Pregunta ────┼── 04 Grafo:      pregunta → entidades → recorrer vecinos ──┼──▶ LLM ──▶ Respuesta
              └── 05 Híbrido:    vectores (punto de entrada) + grafo ──────┘
```

El flujo **06 Comparador** lanza las tres rutas a la vez para ver las diferencias lado a lado.

**Ejemplo** — *"El monitor reintenta una y otra vez, ¿qué reviso?"*
- Vectores: traen los párrafos que hablan de reintentos y errores.
- Grafo: `Reintentos ← causado por ← E-214 ← se resuelve con → Verificar puerto del HIS`
  (la cadena completa, aunque esté en secciones distintas).
- Híbrido: los párrafos **y** la cadena.

## ¿Cuándo usar cada uno?

- **Vectores solos:** preguntas puntuales sobre un tema. Simple, rápido, barato. Punto de partida.
- **Grafo:** preguntas de dependencias, impacto o que cruzan varios documentos.
- **Híbrido:** cuando se quiere lo mejor de ambos. Es lo más completo, pero más lento y caro.

> **Honestidad sobre el demo:** con solo dos manuales cortos, los vectores casi igualan al
> grafo; la ventaja del grafo se nota con más documentos y preguntas de varios saltos. Los
> resultados medidos están en [`resultados-pruebas.md`](resultados-pruebas.md).

## Piezas

| Pieza | Rol |
|---|---|
| **n8n** | Orquesta los flujos 01–06 con bloques visuales |
| **PostgreSQL + pgvector** | Guarda y busca vectores |
| **Neo4j (Community)** | Guarda y recorre el grafo (se consulta por HTTP; n8n no tiene nodo de Neo4j) |
| **Gemini (API)** | Embeddings, extracción de entidades y redacción de respuestas |
| **nginx + HTTPS** | Puerta pública con contraseña |

**Límites:** los textos viajan al proveedor de IA (usar solo manuales no confidenciales con el
nivel gratuito) y el nivel gratuito tiene cuotas bajas (error `429`).
