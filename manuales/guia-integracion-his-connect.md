# Guía de integración HIS-Connect (receptor HL7)

> Documento FICTICIO creado solo para la demo. No describe ningún producto real.

## 1. Descripción

HIS-Connect es el servicio receptor de mensajes HL7 del sistema de información hospitalario (HIS).
Escucha conexiones TCP con encuadre MLLP y entrega cada mensaje al módulo de historia clínica.
El servicio se instala en el servidor `his-app-01` y se configura en el archivo `his-connect.conf`.

## 2. Puerto de escucha

El puerto de escucha se define con la clave `listener.port` de `his-connect.conf`.
El valor de fábrica es 6661. Cambiar el puerto exige reiniciar el servicio `his-connect`,
y mientras dura el reinicio todas las conexiones activas se cierran.

Los equipos que se conectan a HIS-Connect son:

- Monitor ACME M-100 (unidad de cuidados intensivos, 12 camas).
- Central de alarmas CA-2 (estación de enfermería de la UCI).
- Pasarela de quirófano GW-7 (reenvía los monitores de las salas de cirugía).

Cada uno de estos equipos tiene el puerto del HIS grabado en su propia configuración de red;
si `listener.port` cambia, hay que actualizar el puerto en cada uno de ellos.

## 3. Validación del ACK

HIS-Connect responde con un ACK de aplicación. Si el mensaje no pasa la validación del segmento MSH,
responde `AR` y registra el evento ACK-07 en el log. Un mensaje con MSH-10 repetido se responde con `AE`.
El ACK se envía en menos de 2 segundos con la carga normal del servidor.

## 4. Cola de entrada y saturación

HIS-Connect guarda los mensajes recibidos en una cola de 5000 mensajes antes de procesarlos.
Si la cola se llena, el servicio deja de enviar ACK hasta que se libere espacio.
Un monitor ACME M-100 que no recibe ACK dentro de 10 segundos reintenta y, tras 3 reintentos,
muestra la alarma E-214. Por eso una cola saturada en HIS-Connect se manifiesta como alarmas E-214
en los monitores M-100.

## 5. Mantenimiento programado

Los reinicios de HIS-Connect se hacen los domingos a las 03:00. Durante la ventana de mantenimiento
los monitores M-100 acumulan alarmas E-214 que se cierran solas al restablecerse la conexión.
Avisar siempre a enfermería de la UCI antes de reiniciar el servicio, porque la central de alarmas CA-2
deja de mostrar datos en vivo durante el reinicio.
