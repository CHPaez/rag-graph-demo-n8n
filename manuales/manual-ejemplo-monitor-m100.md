# Manual de interfaz HL7 — Monitor de signos vitales ACME M-100

> Documento FICTICIO creado solo para la demo. No describe ningún dispositivo real.

## 1. Introducción

El monitor ACME M-100 envía los signos vitales del paciente a un sistema de información
hospitalario (HIS) mediante mensajes HL7 v2.5 sobre TCP/IP, usando el protocolo MLLP.
El monitor actúa como cliente y abre la conexión hacia el HIS.

## 2. Parámetros de conexión

- Protocolo de transporte: TCP con encuadre MLLP.
- Puerto por defecto del HIS: 6661.
- Tiempo máximo de espera del ACK: 10 segundos.
- Reintentos ante falta de ACK: 3, con 5 segundos entre cada uno.
- Codificación de caracteres: UTF-8.

## 3. Encuadre MLLP

Cada mensaje HL7 se envuelve así:

- Byte de inicio: 0x0B (VT).
- Contenido del mensaje HL7.
- Bytes de fin: 0x1C (FS) seguido de 0x0D (CR).

## 4. Mensaje de resultados de observación (ORU^R01)

El monitor envía un ORU^R01 cada 60 segundos con los últimos valores medidos.
Los segmentos, en orden, son: MSH, PID, PV1, OBR y uno o más OBX.

Ejemplo de trama:

```
MSH|^~\&|M100|UCI-CAMA-04|HIS|HOSPITAL|20261012201500||ORU^R01|MSG000123|P|2.5
PID|1||HC-889123^^^HOSPITAL||PEREZ^JUAN||19600315|M
PV1|1|I|UCI^04^A
OBR|1|||VITALS^Signos vitales
OBX|1|NM|8867-4^Frecuencia cardiaca^LN||78|/min|60-100|N|||F
OBX|2|NM|59408-5^Saturacion de oxigeno^LN||97|%|94-100|N|||F
OBX|3|NM|8480-6^Presion sistolica^LN||122|mmHg|90-140|N|||F
```

### Campos importantes del segmento MSH

- MSH-3: aplicación emisora (siempre `M100`).
- MSH-4: identificador de la cama, formato `UNIDAD-CAMA-NN`.
- MSH-9: tipo de mensaje, `ORU^R01`.
- MSH-10: identificador único del mensaje, usado para correlacionar el ACK.

### Campos importantes del segmento OBX

- OBX-3: código LOINC y nombre del parámetro.
- OBX-5: valor medido.
- OBX-6: unidad de medida.
- OBX-8: bandera de anormalidad (`N` normal, `H` alto, `L` bajo, `HH` crítico alto).

## 5. Confirmación (ACK)

El HIS debe responder con un mensaje ACK que repita MSH-10 en MSA-2.
Un código `AA` en MSA-1 indica aceptación. `AE` o `AR` indican error o rechazo.

## 6. Solución de problemas

- **No llega ningún mensaje al HIS:** verificar que el puerto 6661 esté abierto y que la
  dirección IP del HIS esté configurada en el menú Red > Servidor HL7 del monitor.
- **El monitor reintenta una y otra vez:** el HIS no está devolviendo el ACK dentro de 10 s,
  o el ACK no repite correctamente MSH-10.
- **Caracteres raros en el nombre del paciente:** confirmar que el HIS interpreta UTF-8.
- **Alarma de comunicación en pantalla (código E-214):** se pierde la conexión con el HIS
  durante más de 3 reintentos consecutivos.
