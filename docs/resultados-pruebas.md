# Resultados de las pruebas (medidos)

Ejecutadas contra el stack real (n8n 2.42.7, Neo4j 5.26.32-community, pgvector pg18) con la API de Gemini (nivel gratuito).
Modelo de chat usado: `gemini-flash-lite-latest` (ver nota en el README: `gemini-flash-latest` devolvió HTTP 503 de forma sostenida durante la sesión de pruebas). Embeddings: `gemini-embedding-001`.
Cada pregunta se envió una vez por camino (webhooks `/webhook/ask-vector|ask-graph|ask-hybrid`). Primer intento en las 18 llamadas; no hubo 429 ni errores de flujo.

Las respuestas se muestran recortadas a ~900 caracteres; la columna *Recuperación* lista las llamadas a herramientas que hizo el agente.

## P1. ¿Cómo es la trama ORU^R01 que envía el monitor?

**RAG vectorial** (11.2 s, 1 llamada(s) a herramientas)

> El monitor envía un mensaje `ORU^R01` cada 60 segundos con los últimos valores medidos. Los segmentos, en orden, son: MSH, PID, PV1, OBR y uno o más OBX.
> 
> Ejemplo de trama tal como aparece en el manual:
> 
> ```hl7
> MSH|^~\&|M100|UCI-CAMA-04|HIS|HOSPITAL|20261012201500||ORU^R01|MSG000123|P|2.5
> PID|1||HC-889123^^^HOSPITAL||PEREZ^JUAN||19600315|M
> PV1|1|I|UCI^04^A
> OBR|1|||VITALS^Signos vitales
> OBX|1|NM|8867-4^Frecuencia cardiaca^LN||78|/min|60-100|N|||F
> OBX|2|NM|59408-5^Saturacion de oxigeno^LN||97|%|94-100|N|||F
> OBX|3|NM|8480-6^Presion sistolica^LN||122|mmHg|90-140|N|||F
> ```

Recuperación: `Buscar_en_manuales_PGVector({"input": "ORU R01 trama monitor"})`

**GraphRAG** (20.2 s, 3 llamada(s) a herramientas)

> El mensaje **ORU^R01** es un mensaje HL7 de resultados de observación enviado periódicamente (el monitor M100 lo envía cada 60 segundos). 
> 
> Los segmentos que contiene el mensaje, en orden, son:
> - **MSH** (Segmento de cabecera)
> - **PID** (Segmento de identificación del paciente)
> - **PV1** (Segmento de visita)
> - **OBR** (Segmento de petición de observación)
> - **OBX** (Uno o más segmentos de resultados de observación)

Recuperación: `Recorrer_el_grafo_Neo4j({"term": "ORU^R01"})`; `Recorrer_el_grafo_Neo4j({"term": "CONTAINS"})`; `Recorrer_el_grafo_Neo4j({"term": "MSH"})`

**Híbrido** (14.5 s, 2 llamada(s) a herramientas)

> El monitor ACME M-100 envía un mensaje **ORU^R01** (Resultados de Observación) cada **60 segundos** con los últimos valores de signos vitales medidos. Cada trama se transmite mediante el protocolo de transporte TCP utilizando el encuadre MLLP (con un byte de inicio `0x0B`, seguido del contenido HL7, y finalizado con `0x1C` y `0x0D`).
> 
> ### Orden de los Segmentos
> Los segmentos que componen la trama, en orden estricto, son:
> 1. **MSH** (Encabezado del mensaje)
> 2. **PID** (Identificación del paciente)
> 3. **PV1** (Información de la visita/admisión)
> 4. **OBR** (Observación de solicitud / Conjunto de signos vitales)
> 5. **OBX** (Uno o más segmentos con los valores individuales de las mediciones)
> 
> ---
> 
> ### Ejemplo de Trama ORU^R01
> ```hl7
> MSH|^~\&|M100|UCI-CAMA-04|HIS|HOSPITAL|20261012201500||ORU^R01|MSG000123|P|2.5
> PID|1||HC-889123^^^HOSPITAL||PEREZ^JUAN||19600315|M
> PV1|1|I|UCI^04^A
> OBR|1|||VITALS [...]

Recuperación: `Buscar_en_manuales_PGVector({"input": "ORU^R01 monitor trama mensaje"})`; `Recorrer_el_grafo_Neo4j({"term": "ORU^R01"})`

## P2. ¿Qué significa el código de error E-214?

**RAG vectorial** (13.4 s, 1 llamada(s) a herramientas)

> Según los manuales técnicos, el código de error **E-214** es una **alarma de comunicación en pantalla** que indica que **se pierde la conexión con el HIS durante más de 3 reintentos consecutivos**. 
> 
> Esto también puede ocurrir cuando:
> * Un monitor ACME M-100 no recibe un mensaje `ACK` dentro de 10 segundos, realiza 3 reintentos y la cola de entrada de HIS-Connect se satura.
> * Se producen reinicios del servicio HIS-Connect (por ejemplo, durante el mantenimiento programado de los domingos a las 03:00), momento en el cual los monitores M-100 acumulan estas alarmas, las cuales se cierran solas al restablecerse la conexión.

Recuperación: `Buscar_en_manuales_PGVector({"input": "E-214"})`

**GraphRAG** (8.6 s, 1 llamada(s) a herramientas)

> El código de error **E-214** es una **alarma de comunicación en pantalla generada al perder la conexión con el HIS durante más de 3 reintentos consecutivos.**

Recuperación: `Recorrer_el_grafo_Neo4j({"term": "E-214"})`

**Híbrido** (4.4 s, 2 llamada(s) a herramientas)

> El código de error **E-214** es una **alarma de comunicación en pantalla** que se genera en los monitores (como el **ACME M-100**). 
> 
> ### Significado y Causas principales:
> 1. **Pérdida de conexión:** Se produce cuando el monitor pierde la conexión con el **HIS** (o con el servicio *HIS-Connect*) durante más de **3 reintentos consecutivos**.
> 2. **Saturación en la cola de entrada:** Si el servicio *HIS-Connect* se satura y su cola de mensajes se llena (límite de 5000 mensajes), deja de enviar respuestas `ACK`. Como el monitor M-100 espera un `ACK` durante un máximo de 10 segundos y reintenta hasta 3 veces sin éxito, acaba mostrando la alarma **E-214**.
> 3. **Ventanas de mantenimiento:** Es común que los monitores acumulen alarmas E-214 durante los reinicios programados del servicio HIS-Connect (por ejemplo, los domingos), aunque estas alarmas se cierran automáticamente una vez que se restab [...]

Recuperación: `Buscar_en_manuales_PGVector({"input": "E-214"})`; `Recorrer_el_grafo_Neo4j({"term": "E-214"})`

## P3. ¿Qué puerto usa el HIS por defecto?

**RAG vectorial** (11.7 s, 1 llamada(s) a herramientas)

> Según el manual de integración HIS-Connect, el puerto de escucha por defecto (valor de fábrica) del HIS es el **6661** (definido en la clave `listener.port` del archivo `his-connect.conf`).

Recuperación: `Buscar_en_manuales_PGVector({"input": "puerto HIS por defecto"})`

**GraphRAG** (11.1 s, 1 llamada(s) a herramientas)

> El puerto por defecto del HIS es el **Puerto 6661**.

Recuperación: `Recorrer_el_grafo_Neo4j({"term": "HIS"})`

**Híbrido** (15.3 s, 2 llamada(s) a herramientas)

> El puerto que usa el HIS por defecto es el **6661** (configurado a través de la clave `listener.port` en el archivo `his-connect.conf`).

Recuperación: `Buscar_en_manuales_PGVector({"input": "HIS puerto por defecto"})`; `Recorrer_el_grafo_Neo4j({"term": "HIS"})`

## P4. El monitor reintenta una y otra vez, ¿qué reviso?

**RAG vectorial** (8.5 s, 1 llamada(s) a herramientas)

> Según el manual, si el monitor reintenta una y otra vez, debes revisar lo siguiente:
> 
> * El HIS no está devolviendo el ACK dentro de 10 segundos.
> * El ACK no repite correctamente MSH-10.

Recuperación: `Buscar_en_manuales_PGVector({"input": "reintenta una y otra vez"})`

**GraphRAG** (15.8 s, 3 llamada(s) a herramientas)

> El monitor (como el ACME M-100) reintenta el envío de forma continua porque **no recibe el mensaje ACK** de confirmación en un plazo de 10 segundos. Si esto ocurre durante 3 reintentos consecutivos, el monitor genera la alarma de comunicación en pantalla con el código **E-214**.
> 
> Para solucionar este problema, debe revisar lo siguiente:
> 
> 1. **Conectividad y Red:**
>    - Verifique que el puerto **6661** esté abierto y accesible.
>    - Compruebe que la dirección IP y el puerto del HIS estén configurados correctamente en el monitor (en el menú *Red > Servidor HL7*).
>    - Asegúrese de que el monitor pueda establecer la conexión TCP/IP hacia el HIS (el monitor actúa como cliente y abre la conexión).
> 
> 2. **Respuesta del Servidor / HIS:**
>    - Verifique si el HIS o **HIS-Connect** está respondiendo con los mensajes **ACK**. Si la cola del servidor está saturada, este puede dejar de enviar ACKs.
>   [...]

Recuperación: `Recorrer_el_grafo_Neo4j({"term": "reintenta"})`; `Recorrer_el_grafo_Neo4j({"term": "E-214"})`; `Recorrer_el_grafo_Neo4j({"term": "ACK"})`

**Híbrido** (15.4 s, 2 llamada(s) a herramientas)

> Según los manuales, si el monitor (*ACME M-100*) reintenta una y otra vez, significa que **el HIS (o HIS-Connect) no está devolviendo el ACK dentro del tiempo límite de 10 segundos**, o bien **el ACK no repite correctamente el campo `MSH-10`**.
> 
> Para solucionarlo, debes revisar los siguientes puntos:
> 
> 1. **Respuesta del HIS / Cola saturada:** 
>    * Comprueba si el HIS/HIS-Connect está respondiendo correctamente a los mensajes. Si la cola de entrada de *HIS-Connect* (de hasta 5000 mensajes) se satura, el servicio deja de enviar ACK temporalmente hasta que se libera espacio.
> 2. **Validación del ACK:** 
>    * Asegúrate de que el ACK devuelto incluya y repita correctamente el identificador único del mensaje (`MSH-10`).
> 3. **Conexión y Red:** 
>    * Verifica que el puerto **6661** esté abierto.
>    * Confirma que la dirección IP del HIS esté configurada correctamente en el menú del monitor: **Re [...]

Recuperación: `Buscar_en_manuales_PGVector({"input": "reintenta una y otra vez"})`; `Recorrer_el_grafo_Neo4j({"term": "HIS-Connect"})`

## P5. Si cambio el puerto de escucha del HIS, ¿qué equipos hay que actualizar?

**RAG vectorial** (6.3 s, 1 llamada(s) a herramientas)

> Si cambia el puerto de escucha del HIS, hay que actualizar el puerto en cada uno de los siguientes equipos, ya que tienen el puerto del HIS grabado en su propia configuración de red:
> 
> - Monitor ACME M-100 (unidad de cuidados intensivos, 12 camas).
> - Central de alarmas CA-2 (estación de enfermería de la UCI).
> - Pasarela de quirófano GW-7 (reenvía los monitores de las salas de cirugía).

Recuperación: `Buscar_en_manuales_PGVector({"input": "cambio el puerto de escucha del HIS"})`

**GraphRAG** (29.8 s, 5 llamada(s) a herramientas)

> Si cambia el puerto de escucha del HIS, los equipos y elementos que tienen configurado o grabado dicho puerto (Puerto 6661 por defecto) y que deben actualizarse son:
> 
> * **HIS-Connect** (a través de su archivo de configuración `his-connect.conf`, modificando la clave `listener.port`)
> * **Monitor ACME M-100** (configurado en el menú Red > Servidor HL7)
> * **Pasarela de quirófano GW-7**
> * **Central de alarmas CA-2**

Recuperación: `Recorrer_el_grafo_Neo4j({"term": "HIS"})`; `Recorrer_el_grafo_Neo4j({"term": "ACME M-100"})`; `Recorrer_el_grafo_Neo4j({"term": "GW-7"})`; `Recorrer_el_grafo_Neo4j({"term": "CA-2"})`; `Recorrer_el_grafo_Neo4j({"term": "his-connect.conf"})`

**Híbrido** (13.9 s, 2 llamada(s) a herramientas)

> Si cambia el puerto de escucha del HIS (`listener.port`), debe actualizar la configuración en los siguientes equipos que se conectan a **HIS-Connect**:
> 
> 1. **Monitor ACME M-100** (unidad de cuidados intensivos, 12 camas).
> 2. **Central de alarmas CA-2** (estación de enfermería de la UCI).
> 3. **Pasarela de quirófano GW-7** (reenvía los monitores de las salas de cirugía).
> 
> Cada uno de estos equipos tiene el puerto del HIS grabado en su propia configuración de red, por lo que es necesario actualizarlo en todos ellos. Además, cambiar este parámetro exige reiniciar el servicio `his-connect` en el servidor (lo que cerrará temporalmente las conexiones activas).

Recuperación: `Buscar_en_manuales_PGVector({"input": "puerto de escucha HIS actualizar equipos conexion configura)`; `Recorrer_el_grafo_Neo4j({"term": "HIS-Connect"})`

## P6. Aparecen alarmas E-214 en varios monitores un domingo a las 3 de la mañana: ¿por qué, y qué otro equipo se ve afectado?

**RAG vectorial** (5.9 s, 1 llamada(s) a herramientas)

> Según los manuales técnicos, esto ocurre debido a los **reinicios de HIS-Connect**, los cuales se realizan programadamente los domingos a las 03:00. Durante esta ventana de mantenimiento, los monitores acumulan alarmas E-214 (las cuales se cierran solas al restablecerse la conexión).
> 
> El otro equipo que se ve afectado es la **central de alarmas CA-2**, la cual deja de mostrar datos en vivo durante el reinicio del servicio.

Recuperación: `Buscar_en_manuales_PGVector({"input": "E-214"})`

**GraphRAG** (16.0 s, 3 llamada(s) a herramientas)

> Las alarmas **E-214** corresponden a una alarma de comunicación en pantalla generada al perder la conexión con el HIS durante más de 3 reintentos consecutivos (el monitor ACME M-100 reintenta el envío si no recibe ACK en 10 segundos). Esto ocurre porque se satura la cola en **HIS-Connect** (o se pierde la conexión con este).
> 
> Los otros equipos que se ven directamente afectados al conectarse a **HIS-Connect** son:
> - **CA-2**: Central de alarmas de la estación de enfermería de la UCI (deja de mostrar datos en vivo).
> - **GW-7**: Pasarela de quirófano que reenvía los monitores de las salas de cirugía hacia HIS-Connect.

Recuperación: `Recorrer_el_grafo_Neo4j({"term": "E-214", "description": "Busca informacion sobre la alarma E-)`; `Recorrer_el_grafo_Neo4j({"term": "HIS-Connect", "description": "Consulta los detalles relacion)`; `Recorrer_el_grafo_Neo4j({"term": "GW-7", "description": "Busca GW-7 para ver si se ve afectado)`

**Híbrido** (9.7 s, 2 llamada(s) a herramientas)

> A partir de los manuales técnicos, aquí tienes la explicación de por qué ocurren las alarmas **E-214** en ese momento y qué otro equipo se ve afectado:
> 
> ### ¿Por qué ocurren las alarmas E-214 a las 3:00 AM de los domingos?
> * **Motivo:** Los domingos a las **03:00 AM** se realizan los **reinicios programados de mantenimiento del servicio HIS-Connect**.
> * **Mecánica del fallo:** Durante este reinicio, el servicio deja temporalmente de procesar mensajes y de enviar acuses de recibo (`ACK`). Si un monitor (ACME M-100) no recibe un `ACK` dentro de los **10 segundos**, realiza hasta **3 reintentos**. Al fallar los reintentos consecutivos por la indisponibilidad del servicio, el monitor interpreta que se ha perdido la conexión y genera la alarma de comunicación en pantalla **E-214**. Estas alarmas se cierran por sí solas una vez que el servicio se restablece.
> 
> ### ¿Qué otro equipo se ve afectad [...]

Recuperación: `Buscar_en_manuales_PGVector({"input": "E-214"})`; `Recorrer_el_grafo_Neo4j({"term": "E-214"})`
