# Mean Reversion EA — MVP para MetaTrader 5

EA monolítico en `MeanReversionEA.mq5`, exclusivamente MQL5 y biblioteca estándar `Trade/Trade.mqh`. Implementa `SPEC_MVP.md`, incluidas las aclaraciones de su sección 16 y las variantes experimentales de su sección 17. `AGENTS.md` contiene las instrucciones del proyecto.

Solo permite inicializar dentro del **Probador de Estrategias de MT5**, en **XAUUSD M5** y con moneda de cuenta **USD**. No se adjunta a gráficos de cuentas reales ni demo: fuera del probador devuelve `INIT_FAILED`. Admite nombres de símbolo que contengan `XAUUSD`, incluidos prefijos/sufijos; no infiere equivalencias como `GOLD`.

## Instalación y compilación

1. Abrir MetaTrader 5 en Windows y elegir **Archivo → Abrir carpeta de datos**.
2. Copiar `MeanReversionEA.mq5` a `MQL5/Experts/MeanReversionEA/` dentro de esa carpeta.
3. Abrir MetaEditor con F4 y abrir el archivo copiado.
4. Compilar con F7. La instalación estándar de MT5 debe proporcionar `MQL5/Include/Trade/Trade.mqh` y sus dependencias estándar.
5. Revisar la pestaña **Errores**, corregir cualquier error y conservar el resultado con sus advertencias. Una compilación correcta debe generar `MeanReversionEA.ex5` junto al fuente.
6. Actualizar **Asesores Expertos** en el Navegador de MT5 si el EA no aparece.

No requiere DLL, Python, APIs, bases de datos, indicadores personalizados ni servicios externos. Las herramientas usadas para revisar el fuente no son dependencias del EA.

**Estado de compilación en este entorno:** se encontró `C:\Program Files\MetaTrader 5\metaeditor64.exe`, pero el intento de invocarlo desde este entorno falló con `WSL ... UtilBindVsockAnyPort ... socket failed 1`. No se ejecutó el compilador MQL5; no existe resultado de errores/advertencias del compilador ni se entrega un EX5 validado.

## Configuración

| Entrada | Valor predeterminado | Significado |
| --- | --- | --- |
| `InpSignalMode` | INTRABAR | Enum: INTRABAR o CLOSED_BAR; ambas variantes son experimentales |
| `InpMagicNumber` | 20261104 | Identidad de las operaciones del EA; debe ser única en el símbolo |
| `InpRiskBaseUSD` | 25000 | Capital fijo de referencia en USD |
| `InpRiskPercent` | 0.25 | Porcentaje por idea: `0.25` significa 0.25%, no 25% |
| `InpBollingerPeriod` | 20 | Periodo Bollinger, SMA y Close |
| `InpBollingerDeviation` | 2.5 | Desviaciones Bollinger, shift del indicador 0 |
| `InpStochasticK` | 14 | Periodo %K |
| `InpStochasticD` | 3 | Periodo %D; las señales solo utilizan %K |
| `InpStochasticSlowing` | 3 | Suavizado; SMA y Low/High |
| `InpATRPeriod` | 14 | Periodo ATR M5 |
| `InpATRMax` | 8 | Rechazar ATR superior a este valor; igualdad permitida |
| `InpTPFactor` | 0.90 | Fracción del recorrido banda exterior → SMA20 |
| `InpDeviationPoints` | 20 | Desviación máxima solicitada, en puntos del símbolo |
| `InpDetailedLogs` | true | Logs de señales y actualizaciones; errores, entradas y cierres esenciales permanecen visibles |

Las distancias E2 = 1 ATR y SL = 3 ATR no son configurables. El ATR se congela desde la última vela cerrada. El presupuesto no depende del balance o equity actuales.

## Variantes experimentales de señal

`InpSignalMode` es el único parámetro nuevo. `INTRABAR` conserva la variante original y continúa siendo el valor predeterminado. `CLOSED_BAR` es una variante de confirmación al cierre para comparar mediante backtesting; ninguna variante supone rentabilidad ni uso en producción.

| Aspecto | INTRABAR | CLOSED_BAR |
| --- | --- | --- |
| Oportunidad | Cada tick elegible | Solo el primer tick disponible de cada nueva vela M5 |
| Low/High, Bollinger y %K de señal | Vela en formación, shift=0 | Misma vela recién cerrada, shift=1 |
| Compra | Low <= banda inferior y %K < 10 | Mismas condiciones en shift=1 y cierre estrictamente dentro de ambas bandas |
| Venta | High >= banda superior y %K > 90 | Mismas condiciones en shift=1 y cierre estrictamente dentro de ambas bandas |
| ATR congelado | shift=1 | shift=1, de la vela de señal |
| TP inicial | Bandas/SMA20 de shift=0 | Bandas/SMA20 de shift=0, aparte de la señal confirmada |
| Actualizaciones posteriores del TP | shift=1 | shift=1 |
| Datos faltantes | Puede volver a leerlos en otro tick de la misma vela | Registra y descarta la oportunidad; no hay entrada tardía |

En `CLOSED_BAR`, tocar la banda admite igualdad, pero Close debe estar estrictamente entre las bandas y %K debe ser estrictamente menor que 10 o mayor que 90. Un %K intrabar que vuelva al rango al cerrar no confirma señal. Los registros `SIGNAL` incluyen `modo=...` y `vela=...`, con la hora de apertura de la vela evaluada. Sus datos Bollinger/%K pertenecen a esa vela; las bandas para el TP inicial se obtienen por separado.

La oportunidad de nueva vela se consume antes de las salidas por idea activa, enfriamiento, cierre en curso o exposición ajena. Si se omite, no se recupera después dentro de esa vela. Si el enfriamiento ya venció al comenzar una nueva vela, esa nueva oportunidad sí es elegible. La inicialización/reinicialización solo establece la referencia actual: no ejecuta señales históricas. Si hay huecos sin ticks, no recorre las velas omitidas; considera únicamente la recién cerrada disponible. La fecha de la vela cerrada y la dirección identifican la señal, con marcas persistidas separadas por modo para evitar interferencias entre experimentos.

No cambian los valores predeterminados Stochastic 14,3,3, las dos direcciones, entradas, distancias, riesgo, cierres, protección netting ni enfriamiento. Las esperas técnicas de reintentos y la cola de resúmenes `EXIT` reconciliados siguen compartidas por ambos modos.

**Verificación de esta variante:** se ejecutó un arnés temporal C++ fuera del repositorio con las funciones reales de selección y oportunidad de señal, evaluación al cierre y `OnTick`, adaptando tipos y simulando datos/operaciones de MT5. Pasaron compras/ventas válidas, límites estrictos de Close/%K, toques con igualdad, Stochastic intrabar que no confirma al cierre, deduplicación, primer tick disponible, ATR[1] y TP inicial[0]. También pasaron descarte y ausencia de entrada tardía para datos OHLC, bandas de señal, bandas de TP inicial, %K, ATR y serie M5 no disponibles; oportunidades omitidas con idea activa, enfriamiento o exposición ajena; inicialización/reinicio; y huecos entre ticks.

La regresión `INTRABAR` pasó señales inmediatas incluso con Close fuera de bandas, ambas direcciones, uso de shift=0, deduplicación y relectura de datos faltantes en la misma vela. Se comprobó la ruta de cierre monetario y, mediante comparación estática, que las funciones compartidas de apertura, riesgo, niveles, TP, cierre, enfriamiento, reintentos y reconciliación del PnL no cambiaron. Estas son pruebas auxiliares y revisión estática; **no son compilación MQL5 ni backtesting MT5**. El intento de invocar MetaEditor volvió a fallar por interoperabilidad Windows/WSL; queda pendiente recompilar esta versión y comparar ambos modos en el Probador.

Para comparar, ejecutar dos backtests con idénticos símbolo, fechas, ticks reales, cuenta y parámetros; cambiar solamente `InpSignalMode`. Revisar `SIGNAL modo=... vela=...`, entradas, rechazos por datos y salidas. La diferencia de resultados entre variantes no sustituye la verificación funcional de cada una.

### Trazabilidad de CLOSED_BAR y evaluación después de pausas

El registro ampliado conserva una sola línea `SIGNAL` por señal aceptada para su evaluación de ejecución; no añade un registro por tick ni vuelve a consultar indicadores. Usa el mismo `MqlRates` de `CopyRates(...,1,1,...)`, bandas/SMA20[1], %K[1] y ATR[1] que se pasaron a la decisión. Las bandas de shift=0 para el TP inicial no se mezclan con los campos de la señal. El formato anterior de `INTRABAR` se conserva.

Formato de la nueva línea, mostrado dividido únicamente para facilitar la lectura (los puntos suspensivos son campos pendientes, no datos históricos):

```text
SIGNAL <fecha_publicacion> idea=<id_previo> modo=CLOSED_BAR
 evaluacion=<fecha_hora> vela=<apertura_vela_senal>
 cierre_nominal=<apertura_vela_senal+300s> segundos_desde_cierre=<segundos>
 direccion=<BUY|SELL> Open=... High=... Low=... Close=...
 LowerBand=... SMA20=... UpperBand=... K=... ATR=...
 cierre_dentro_bandas=<true|false>
 mercado_disponible=true mercado_tick=<fecha_hora_cotizacion>
 mercado_bid=... mercado_ask=... mercado_referencia_e1=...
```

- `evaluacion` es el tiempo del tick del servidor/probador cuando se registra la señal. `vela` es la apertura de la vela de señal, no la fecha de ejecución.
- `cierre_nominal` es siempre apertura + 300 segundos. `segundos_desde_cierre = evaluacion - cierre_nominal` incluye todo el tiempo natural de pausas y fines de semana. Es una medida informativa, no un filtro ni un descarte.
- `Open`, `High`, `Low`, `Close`, las tres líneas Bollinger, %K y ATR son el snapshot de señal de shift=1. `cierre_dentro_bandas` comprueba literalmente `Close > LowerBand && Close < UpperBand`. En las señales válidas del recorrido normal será `true`; las velas que no cumplen condiciones no generan `SIGNAL`.
- `mercado_bid`, `mercado_ask` y `mercado_tick` son una lectura separada de la cotización disponible al registrar. `mercado_referencia_e1` es Ask para compra y Bid para venta; **no es el precio ejecutado**. El precio real de E1 se determina después en la ejecución. Si no puede leerse la cotización para el log, aparece solo `mercado_disponible=false`; esto no añade un rechazo a la estrategia.
- `SIGNAL` se registra antes de `OpenIdea`: no acredita ejecución ni que el riesgo permita operar. El `idea` de su prefijo puede ser 0 porque el ID de la nueva idea se asigna después. Para reconstruir el resultado hay que seguir los eventos del mismo modo, evaluación y vela, la solicitud de mercado, sus deals y los registros `ENTRY`/`REJECTED`/`EXIT`. La ausencia de `ENTRY` por sí sola no demuestra que E1 nunca se ejecutara: puede haberse abortado después de abrir E1.
- Se mantiene el control `InpDetailedLogs`: desactivarlo suprime estos logs de señal. No se agregan logs repetitivos por tick.

**Comportamiento actual tras pausas:** la detección de nueva vela usa el avance de tiempo M5 del tick, pero `shift=1` identifica la barra anterior disponible en la serie. No implica que esa barra abriera exactamente cinco minutos antes del tick actual. Si el símbolo no tiene barras durante una pausa, al reanudarse puede evaluarse la última barra anterior a la pausa, con sus propias bandas, %K y ATR. Esto ocurre en la primera oportunidad nueva y elegible de la instancia; no es un reintento de una oportunidad ya descartada. Si se adjunta/reinicia en ese momento, se conserva la regla de esperar la siguiente nueva vela.

No existe actualmente un filtro de antigüedad, calendario o sesión, ni una condición de proximidad entre Close de la señal y la cotización actual. Una señal antigua puede pasar a `OpenIdea`, sujeta a las comprobaciones existentes de riesgo/propiedad/ejecución. No se añaden descartes automáticos. El retorno de ticks tampoco garantiza que el servidor/probador acepte órdenes en ese instante.

**Observaciones verificadas en el Diario existente:** se leyeron los logs `20261104.log` del terminal y de sus agentes. Los siguientes casos se localizaron en el agente `Agent-127.0.0.1-3001` de la instancia `6FBEE76C719DC78AB2AE839B5A0C7442`, en `%APPDATA%/MetaQuotes/Tester/<instancia>/<agente>/logs/20261104.log`, y se cotejaron con su copia en `%APPDATA%/MetaQuotes/Terminal/<instancia>/Tester/logs/20261104.log`. Son evidencia de un backtest ya realizado, no una nueva ejecución de esta versión.

| Evaluación | Vela de señal | Cierre nominal M5 | Retraso calculado | Intento de E1 | Resultado observado |
| --- | --- | --- | --- | --- | --- |
| 2026.07.06 01:00:02 | 2026.07.03 19:55:00 | 2026.07.03 20:00:00 | 190802 s (53 h y 2 s) | SELL 0.04, idea 1783299602 | Rechazada: Market closed; entradas=0 |
| 2026.07.22 01:00:00 | 2026.07.21 23:55:00 | 2026.07.22 00:00:00 | 3600 s (1 h) | BUY 0.06, idea 1784682000 | Rechazada: Market closed; entradas=0 |
| 2026.10.27 01:00:00 | 2026.10.26 23:55:00 | 2026.10.27 00:00:00 | 3600 s (1 h) | SELL 0.07, idea 1793062800 | Rechazada: Market closed; entradas=0 |

En el archivo del agente, los bloques son las líneas **184428–184433**, **185981–185986** y **201000–201005**, respectivamente: `SIGNAL modo=CLOSED_BAR`, `failed market ... [Market closed]`, confirmación de CTrade, `REJECTED ... E1 rechazada`, `EXIT_REQUEST` y `EXIT ... entradas=0`. Los tres intentos llegaron al envío de E1; **ninguno ejecutó E1**. Los retrasos de la tabla se calcularon a partir de las fechas del log antiguo: todavía no proceden del nuevo campo. Ese log tampoco permite reconstruir Open de la vela ni la cotización actual a partir de `precio`, que en el formato anterior representaba Close de la señal.

**Comprobación de reglas:** `ClosedSignalSide()` rechaza Close en o fuera de los límites y delega en `SignalSide()`, que exige `Low <= LowerBand && K < 10` para compra y `High >= UpperBand && K > 90` para venta. `EvaluateClosedBarSignal()` proporciona todos esos datos con shift=1. No se encontró discrepancia con las reglas solicitadas y no se cambió la lógica.

**Verificaciones de este cambio:** comparación del fuente confirma que solo cambió `SignalLog()`, conservando literalmente su rama `INTRABAR` y todas las funciones operativas. Un arnés temporal C++ ejecutó la función real de registro con snapshots OHLC sintéticos y respuestas de cotización simuladas: comprobó todos los campos, retrasos 190802/3600/3600 s, separación entre Close y Bid/Ask, referencia compra/venta, cotización ausente sin rechazo, booleano de límites y control de logs detallados. También se repitieron las pruebas simuladas de ambos modos, deduplicación y ausencia de entradas tardías. Son verificaciones auxiliares, revisión estática e inspección del Diario existente; no una compilación MQL5 ni un nuevo backtest. Se intentó invocar MetaEditor y volvió a fallar con `WSL ... UtilBindVsockAnyPort ... socket failed 1`; la compilación MQL5 y el backtest de esta versión quedan pendientes.

## Comportamiento implementado

- En el modo predeterminado `INTRABAR`, compra intrabar: `Low[0] <= LowerBand[0]` y `%K[0] < 10`. Venta: `High[0] >= UpperBand[0]` y `%K[0] > 90`. No se espera al cierre de vela ni a regresar dentro de las bandas.
- En `INTRABAR`, una señal se identifica por vela M5 actual y dirección. Se consume al disponer de todos los datos, aunque falle riesgo o ejecución. La falta de datos permite volver a leerlos en ticks posteriores. Variables globales estándar del entorno MT5 guardan las señales consumidas, con clave por cuenta, símbolo y Magic, para conservarlas en una reinicialización. El probador emula estas variables separadamente del terminal.
- E1 se envía a mercado. Se obtiene el volumen y precio medio realmente abiertos antes de calcular los niveles definitivos y verificar otra vez el riesgo conjunto con `OrderCalcProfit()`.
- E2 es una única Buy Limit/Sell Limit, con el mismo lote, a 1 ATR de E1; ambas entradas comparten el SL a 3 ATR de E1. E2 nunca se repone. No hay E3.
- El lote se redondea hacia abajo y se comprueba usando precios normalizados al tick size, volumen mínimo/máximo y paso del símbolo. Un cálculo fallido o riesgo superior al presupuesto impide continuar.
- El TP inicial usa las bandas actuales. En la primera oportunidad de cada nueva vela se actualiza con `shift=1`. Si los datos todavía no están disponibles, conserva la supervisión del objetivo anterior y reintenta la lectura durante esa vela.
- Se supervisan objetivos por tick: compra con Bid y venta con Ask. Si el TP no puede asignarse al servidor, se gestiona lógicamente y se intenta sincronizar después; se intenta retirar el TP antiguo si el nuevo no es válido. Se conserva el SL común, sin trailing ni breakeven.
- El límite monetario usa la suma de `POSITION_PROFIT + POSITION_SWAP` de las posiciones propias. No incorpora comisiones históricas al disparador monetario. El log de resultado realizado sí suma los datos de beneficio, swap, comisión y fee de los deals disponibles de la idea.
- Cualquier cierre de una posición de la idea activa provoca la finalización del conjunto, incluidas sus pendientes. Los estados son `WAITING_SIGNAL`, `ACTIVE_IDEA`, `CLOSING_IDEA` y `COOLDOWN`.
- Después de confirmar la finalización se espera el resto de esa vela y una vela M5 completa. Ejemplo: finalización 10:32 → nuevas señales desde 10:40. Una E1 rechazada sin exposición no inicia enfriamiento; su señal queda consumida.
- Se prefiere FOK para E1; si no está disponible, se utiliza el modo admitido. Una ejecución parcial de E1/E2 aborta la idea, cancela remanentes y cierra exposición propia, sin completar volumen con nuevas entradas.

### Netting, propiedad y reinicios

En hedging se gestionan los tickets propios; en netting se inspeccionan los deals del identificador de la posición para detectar mezcla de Magic Numbers. Todas las operaciones y consultas de limpieza se limitan al símbolo y Magic correspondientes.

**Netting exige uso exclusivo del símbolo.** Una posición o pendiente ajena bloquea nuevas entradas. Si se detecta intervención ajena en una posición del EA, se registra `MANUAL_REQUIRED`, se bloquean entradas y se cancelan pendientes propias, reintentando tras reconciliar fallos. **El EA no cierra ni modifica la posición mezclada.** El bloqueo permanece durante esa instancia: resolver el conflicto manualmente y reinicializar para volver a evaluar el entorno. El EA no retira automáticamente SL/TP que ya estuvieran instalados en esa posición; siguen sujetos a ejecución por el servidor.

No existe una operación atómica de MT5 que reserve el símbolo frente a otros operadores. Es responsabilidad del entorno de prueba garantizar la exclusividad. Otro EA que use el mismo símbolo y Magic es indistinguible de este EA.

Al inicializar no se retoma una idea antigua: se cancelan pendientes propias y se cierran posiciones propias, preservando la protección de posiciones mezcladas. Después se aplica enfriamiento. Sin residuos, se reconstruye el enfriamiento desde cierres/cancelaciones recientes del mismo símbolo y Magic. La exposición propia que aparezca tardíamente fuera del estado activo también se envía a limpieza.

### Solicitudes fallidas o inciertas

Las llamadas usan `CTrade` en modo síncrono y se inspecciona el código del servidor, no solo el booleano devuelto. Las respuestas inciertas se registran por request ID y ticket; se comprueban transacciones, órdenes, posiciones e historial antes de repetir acciones. Un objeto que desaparece o una orden que alcanza un estado terminal permite reconciliar su solicitud.

Los fallos definitivos de modificación de TP, cierre o cancelación se reintentan con una espera técnica fija de 5 segundos, evaluada en ticks posteriores, sin máximo de intentos. Las solicitudes todavía no resueltas bloquean duplicados y la finalización de la idea. Si no llega confirmación suficiente, el EA conserva el bloqueo y requiere diagnóstico manual; no deduce fracaso por el mero paso del tiempo. Si no llegan ticks, no puede enviar nuevos reintentos. Si E2 se ejecuta durante la limpieza, también se cierra su exposición propia, salvo protección por mezcla netting.

### Corrección de reintentos tras «Market closed»

El usuario reportó un backtest finalizado con 1,028 solicitudes fallidas, concentradas en `2026.10.05 01:00:00–01:00:59` y `2026.10.27 01:00:00–01:00:59`. El diagnóstico del fuente encontró que `SyncTP()` y `CloseStep()` podían volver a solicitar la misma acción en cada tick; además, una transición a cierre dentro del mismo ciclo podía solicitar otra acción sobre un objeto ya atendido. El Diario original no se ha inspeccionado aquí ni se ha reproducido ese backtest.

La corrección incorpora un registro por ticket y tipo de objeto (posición/orden):

- Después de un rechazo se esperan **5 segundos de tiempo del servidor/probador** antes de volver a solicitar una acción sobre ese objeto. No se usa `Sleep()` ni tiempo real de ejecución del ordenador. El plazo no crece y no existe un máximo de intentos.
- `TRADE_RETCODE_MARKET_CLOSED` también establece esa espera para las solicitudes de gestión de los demás tickets del símbolo. Así no se repite el mismo rechazo por cada posición o pendiente en el mismo tick.
- Modificar TP y cerrar una posición comparten el registro de su ticket; modificar TP y cancelar una pendiente también. Se permite como máximo una solicitud de gestión por objeto y ciclo `OnTick`, incluso si una ruta vuelve a llamar a la gestión durante ese ciclo.
- El resultado de establecer el SL inicial también se registra para que un aborto no provoque inmediatamente otra solicitud sobre esa posición en el mismo ciclo. Se conserva el fallback preexistente de `INVALID_STOPS`: probar SL sin TP es una solicitud diferente para instalar protección, no una repetición idéntica.
- Un resultado correcto, sin cambios o con cierre parcial no impone la espera de rechazo. Un cierre parcial puede continuar en el siguiente tick. Se eliminan registros de objetos desaparecidos.
- La espera afecta únicamente al envío de solicitudes de gestión. Se siguen evaluando el riesgo, el SL y el TP lógico por tick; alcanzar una condición de salida mantiene o activa `CLOSING_IDEA`, aunque el envío deba esperar. Continúan la reconciliación y las comprobaciones de propiedad. Las solicitudes inciertas siguen sujetas a su bloqueo por confirmación, que la espera no sustituye.
- Solo se inicia el enfriamiento tras confirmar que no quedan posiciones, órdenes ni solicitudes propias pendientes. La protección de posiciones netting mezcladas sigue vigente.

No se añaden filtros horarios, parámetros de estrategia ni cambios en señales, presupuesto, niveles o enfriamiento. Tras un rechazo puede haber hasta 5 segundos adicionales antes del siguiente intento elegible, o más si no llegan ticks o sigue pendiente una confirmación. Reabrir el mercado no elimina retroactivamente el plazo: se prueba otra vez cuando vence y llega un tick.

**Verificaciones de esta corrección:**

- Revisión estática y comparación del fuente: sin cambios en las funciones de señal, riesgo, niveles, TP, enfriamiento, apertura, propiedad y reconciliación. `OnTick()` solo añade el contador de ciclo y la limpieza de registros antes de su supervisión original. Revisadas las cuatro rutas recurrentes: modificar posición, modificar pendiente, cerrar posición y cancelar pendiente.
- Ejecutado un arnés temporal C++ fuera del repositorio que extrae las funciones nuevas y las funciones reales `SyncTP()` y `CloseStep()` del fuente, adaptando tipos/arrays y simulando respuestas de MT5. En 60,000 ticks durante un minuto simulado, con dos llamadas a cierre por tick y varios objetos, produjo **12 solicitudes «Market closed» en total**, conservó `CLOSING_IDEA` y ejecutó 120,000 reconciliaciones simuladas. Al aceptar solicitudes de nuevo, completó la limpieza y entró en enfriamiento.
- Pasaron casos simulados de rechazo distinto con espera de 5 segundos, transición TP → cierre/cancelación sin duplicados, objetivo lógico alcanzado durante la espera, protección netting, E2 ejecutada durante la limpieza, solicitud incierta todavía bloqueada, registro del resultado del SL inicial, continuación de cierre parcial y eliminación de registros caducados.
- Estas pruebas ejecutan lógica extraída con respuestas simuladas; **no son compilación MQL5 ni backtesting MT5**. El nuevo intento de invocar MetaEditor falló con el mismo error de interoperabilidad Windows/WSL. No se ha recompilado ni repetido el backtest de esta versión desde este entorno.

Para verificar en MT5, recompilar esta versión y repetir el backtest con la misma configuración y fechas. Revisar especialmente ambas ventanas reportadas: espaciamiento mínimo de 5 segundos entre rechazos `Market closed` de gestión, ausencia de duplicados por objeto en el ciclo, continuidad del objetivo lógico y del estado de cierre, limpieza posterior cuando el servidor vuelva a aceptar y enfriamiento únicamente tras finalizar. No se espera eliminar todo rechazo: los reintentos periódicos permanecen activos. El usuario ya reportó compilación y backtesting de una versión anterior; esa evidencia no valida automáticamente esta corrección.

### Resumen EXIT y reconciliación de deals de cierre

El caso reportado de la idea `1790566264` abrió E1 el `2026.09.28 03:31:04` (compra 0.03 a 4246.68); E2 compró 0.03 a 4239.73 y ambas cerraron a 4234.89 el `03:31:05`. Para un contrato de 100 onzas y sin otros costes, las pérdidas son `-35.37` y `-14.52`, total **-49.89 USD**. El Diario original no se ha inspeccionado aquí; la reproducción descrita abajo usa los datos facilitados y respuestas simuladas.

La revisión encontró dos problemas de registro: E2 podía abrirse y cerrarse entre ticks sin que se conservara su identificador de posición; y la desaparición de posiciones/órdenes podía preceder a la disponibilidad de todos los deals en el historial. Publicar `realized` inmediatamente y después reutilizar la identidad para otra idea podía producir un `EXIT` definitivo incompleto.

La corrección funciona así:

- Aprende los identificadores desde las transacciones y desde las órdenes/deals de E1 y E2; primero descubre identidades y después suma cierres. Relaciona los deals por `DEAL_POSITION_ID`, aunque sus órdenes de salida sean distintas. No usa el segundo como identificador ni como cursor que descarte otros deals del mismo segundo.
- Al confirmar ausencia de posiciones, pendientes y solicitudes por resolver, copia la identidad, las órdenes, las posiciones conocidas, el motivo y la hora de finalización a un resumen pendiente independiente. **El enfriamiento comienza en el mismo punto operativo de antes**: no espera la publicación del resultado contable.
- Antes de publicar `EXIT`, exige el estado terminal de las órdenes conocidas, sus volúmenes ejecutados reflejados en los deals de entrada y el equilibrio de volumen de entrada/salida para cada posición. Se cuentan órdenes de entrada distintas, no transacciones individuales. Un beneficio cero es válido si los volúmenes están reconciliados.
- Mientras falten datos, emite una sola advertencia `EXIT_PENDING` por resumen, sin publicar un PnL definitivo. Reintenta la lectura en ticks y transacciones posteriores y una última vez durante `OnDeinit`. No envía operaciones desde el código de resumen.
- El resumen conserva su propia identidad aunque termine el enfriamiento y comience otra idea. Cuando está completo, emite una sola línea `EXIT` con el ID original, `cierre=` (hora de finalización operativa) y el PnL de beneficio, swap, comisión y fee disponibles en sus deals. La fecha al principio de la línea es la fecha de publicación, que puede ser posterior.
- El campo `motivo` conserva la causa operativa conocida. `Sin posiciones propias; cancelar residuales` indica detección de ausencia de posiciones; no permite inferir por sí solo SL, TP o límite monetario. La corrección no inventa una causa a partir de los precios de cierre.

Se usan únicamente las identidades del símbolo/Magic del EA. Un resumen de una posición netting mezclada no se presenta como un resultado propio separable. La cola de resúmenes vive en memoria durante la instancia del EA; descargarlo con historial todavía incompleto puede dejar `EXIT_PENDING` sin un `EXIT` posterior. En ese caso se debe contrastar el informe de MT5, no interpretar el dato ausente como cero.

**Verificaciones de esta corrección:**

- Ejecutado un arnés temporal C++ fuera del repositorio con las funciones reales de descubrimiento de identidades, inspección de historial y cola/publicación de resúmenes, adaptando arrays/tipos y simulando las consultas de MT5. Pasaron las **24 permutaciones** de los dos deals de entrada y los dos deals de salida, incluidos E2 y ambos cierres del mismo segundo: resultado `-49.89` y `entradas=2`, sin `EXIT` duplicado.
- Pasaron las **15 combinaciones incompletas** de esos cuatro deals: todas mantuvieron `EXIT_PENDING` sin resultado definitivo. Al completar el historial después de sustituir la identidad activa por la de una nueva idea, publicaron el resultado de la idea original.
- Pasaron casos de historial de órdenes ausente, fallo temporal de lectura, netting con E1/E2 en una posición, PnL cero legítimo, costes/swap, múltiples resúmenes independientes, E2 cancelada o parcialmente ejecutada, cierres parciales y limpieza de una posición de una instancia anterior.
- Comparación estática: funciones de estrategia, riesgo, niveles, TP, reintentos y cálculo del enfriamiento conservadas. `CloseStep()` sustituye la publicación inmediata por el resumen independiente; las operaciones y la transición al enfriamiento permanecen en el mismo lugar. Se repitió la regresión simulada de reintentos: 60,000 ticks, 12 rechazos `Market closed` por minuto, recuperación, protección netting y E2 durante limpieza.
- No es una compilación MQL5 ni una repetición del backtest. El intento de ejecutar MetaEditor volvió a fallar por interoperabilidad Windows/WSL. Para validar en MT5, recompilar y repetir el intervalo del `2026.09.28`, comprobando que el resumen incluya ambas salidas antes de publicar el total, sin cambiar el momento del enfriamiento.

**Final del periodo del Probador:** el Probador puede liquidar posiciones al terminar el intervalo sin que el EA reciba otra oportunidad de ejecutar su ciclo normal de cierre y generar el resumen `EXIT` habitual. Esa liquidación puede aparecer en el informe/historial de MT5 sin una línea `EXIT` del EA. `OnDeinit` solo intenta completar resúmenes que ya estaban en cola y libera indicadores; no fuerza operaciones ni fabrica un cierre de estrategia. Al comparar resultados hay que revisar también las liquidaciones del final del test y los posibles `EXIT_PENDING`, además de los resúmenes del Diario.

## Ejemplo de riesgo

Con referencia de USD 25,000, el 0.25% equivale a USD 62.50. Para un contrato de 100 onzas/lote y ATR = 2:

`lote = 62.50 / (500 × 2) = 0.0625 → 0.06` con paso de 0.01.

Si E1 compra a 2500, E2 se coloca a 2498 y SL a 2494. El riesgo teórico es `0.06 × 100 × (6 + 4) = USD 60`. El EA usa las especificaciones reales mediante `OrderCalcProfit()`, no asume siempre ese contrato.

Con USD 10,000 y ATR = 6, el presupuesto es USD 25 y el lote mínimo de 0.01 arriesgaría USD 30: la idea se rechaza aunque ATR no supere 8.

Comisiones y deslizamiento no se presupuestan al calcular el lote inicial. Spread, gaps, deslizamiento y fallos de ejecución pueden producir pérdidas superiores al presupuesto. No se garantiza un límite monetario exacto.

## Backtesting en MT5

1. Compilar primero y abrir el Probador de Estrategias con Ctrl+R.
2. Seleccionar `MeanReversionEA`, el símbolo XAUUSD del bróker y periodo **M5**.
3. Elegir **Cada tick basado en ticks reales**, un intervalo con histórico suficiente y moneda de depósito **USD**. Configurar depósito, apalancamiento y especificaciones reales del símbolo; `InpRiskBaseUSD` continúa siendo la referencia de riesgo, independientemente del depósito.
4. Mantener los parámetros predeterminados (`InpSignalMode=INTRABAR`) para la primera ejecución; repetir con `CLOSED_BAR` para comparar la variante al cierre. Desactivar optimización; usar modo visual para inspeccionar entradas, niveles y enfriamiento.
5. Ejecutar y conservar informe, operaciones y Diario. Comprobar `SIGNAL`, `ENTRY`, `TP_UPDATE`, `EXIT_REQUEST`, `EXIT`, `REJECTED`, `REQUEST_PENDING`, `EXIT_PENDING`, `ERROR` y `MANUAL_REQUIRED`.
6. Contrastar los eventos con los 25 escenarios de la sección 12 de `SPEC_MVP.md`. Repetir en entornos de prueba hedging y netting; un backtest individual no demuestra ambas modalidades.
7. Registrar fechas, modelo de ticks, fuente de datos, moneda, configuración del símbolo, modo de cuenta y valores de entrada para reproducibilidad.

Los casos de posiciones mezcladas, reinicio con residuos, ejecución parcial y fallos del servidor requieren un entorno de prueba controlado o simulación de transacciones; un histórico que no produzca esos eventos no los valida. No usar cuentas reales para probarlos.

## Suite local de pruebas reproducibles

Las comprobaciones auxiliares realizadas durante el desarrollo están ahora conservadas en [`test/`](test/README.md). El EA continúa siendo exclusivamente MQL5; Python y C++ solo se usan para las pruebas offline.

Desde la raíz del proyecto, con Python 3.10+ y `g++` con C++17 en Linux/WSL:

```bash
python3 -m unittest discover -s test -t . -v
```

No hay dependencias Python que instalar ni se necesita un entorno virtual. Para usar `uv` con el Python ya instalado:

```bash
uv run --no-project --no-managed-python --offline python3 -m unittest discover -s test -t . -v
```

La suite usa `unittest`: 5 tests de comportamiento con múltiples escenarios internos, 4 comprobaciones del extractor/adaptador y 3 contratos estáticos. Cubre riesgo/lotaje, señales y modos, TP, enfriamiento, reintentos, identidad/PnL de cierres y trazabilidad tras pausas. Extrae funciones del fuente actual y usa respuestas MT5 simuladas; no depende de snapshots o scripts temporales anteriores. Sin compilador C++17, los tests de comportamiento se marcan como omitidos, no como verificados.

Los detalles y límites están en [`test/README.md`](test/README.md). Estas pruebas no sustituyen compilación MQL5 ni backtesting MT5. `.gitignore` excluye los artefactos locales; los fixtures fuente de la suite sí se conservan.

## Verificaciones y estado de aceptación

**Revisión estática realizada:** se revisaron los 25 escenarios de la especificación contra el fuente y las ocho aclaraciones. La cobertura que sigue indica rutas revisadas, no ejecuciones en MT5.

| Escenarios de SPEC_MVP.md | Ruta revisada | Estado en MT5 |
| --- | --- | --- |
| 1–5: señales, intrabar, deduplicación e idea única | `SignalSide`, `OnTick`, estados y señales consumidas | Pendiente |
| 6–10: E1, E2, lote común, SL fijo, ausencia de E3 | `OpenIdea`, `Levels`, `SetInitialSL` | Pendiente |
| 11–15: ATR, lote mínimo, riesgo previsto y límite flotante | `ATRAllowed`, `Size`, `Risk`, `OnTick` | Pendiente |
| 16–20: TP inicial, actualizaciones y cierre por objetivo | `Target`, `SyncTP`, `HitTarget`, `OnTick` | Pendiente |
| 21–25: cancelar E2, cerrar remanentes, enfriamiento y residuos | `CloseStep`, `InspectIdeaHistory`, `Cooldown`, `OnInit` | Pendiente |
| Aclaraciones 1–8 | Inicialización USD, propiedad netting, historial, riesgo real, solicitudes y parciales | Pendiente |

**Comprobaciones auxiliares ejecutadas:** arnés temporal fuera del repositorio que extrajo funciones del propio fuente y las ejecutó en C++ con adaptadores de tipos y funciones MQL5. `OrderCalcProfit` se simuló con contrato lineal de 100 onzas; las respuestas de trading se simularon. No compiló el EA completo ni ejercitó el motor de MT5.

- Pasaron 12,570 combinaciones ejecutables de lote/riesgo, variando dirección, capital, ATR y tick size; se comprobó presupuesto y redondeo hacia abajo.
- Pasaron 86,400 instantes de enfriamiento, más límites de señales, ATR, objetivos Bid/Ask y fallo del cálculo de riesgo.
- Pasó la función real `CloseStep` con respuestas simuladas: fallos repetidos, conservación de objetos ajenos, protección de posición mezclada, ejecución de E2 durante limpieza, bloqueo por solicitud pendiente y rechazo de E1 sin enfriamiento.
- Pasaron comprobaciones estructurales de indicadores, shifts, handlers y ausencia de dependencias externas.

**Compilación MQL5:** no ejecutada; el intento de iniciar MetaEditor falló en la interoperabilidad Windows/WSL. **Backtesting MT5:** no ejecutado. No se afirma que el EA compile, opere correctamente en el motor de MT5 o sea rentable. La aceptación del MVP queda pendiente de compilación y validación en el probador.

## Limitaciones pendientes de validar

- Los errores, advertencias y el comportamiento real de MT5 solo pueden confirmarse con MetaEditor y el probador.
- Stops/freeze pueden impedir asignar o retirar un TP anterior. Mientras el servidor rechace la modificación, ese TP anterior puede seguir ejecutándose; el EA registra el problema y supervisa el objetivo lógico en cada tick. No puede anular restricciones del servidor.
- E1 abre antes de conocer su precio definitivo: existe un intervalo entre ejecución y establecimiento del SL. Si no se confirma un SL válido se inicia cierre, que también puede fallar y requerir reintentos.
- La protección netting prioriza no tocar posiciones mezcladas. Esas posiciones requieren intervención manual incluso si su pérdida alcanza el presupuesto.
- La gestión por tick y los reintentos requieren ejecución activa y ticks. El SL/TP ya aceptado por el servidor puede actuar sin nuevos ticks del EA; el objetivo lógico y límite monetario necesitan supervisión del programa.
- Finalizar el probador o descargar el EA detiene su gestión. El Probador puede liquidar posiciones al final del intervalo sin el resumen `EXIT` habitual. `OnDeinit` intenta reconciliar resúmenes ya pendientes y libera los indicadores; no intenta garantizar cierres durante la descarga. La siguiente inicialización limpia los residuos propios que existan.
- No se ha medido rendimiento ni rentabilidad. El historial se consulta para reconciliar propiedad y ciclo de vida; no se introducen filtros de señal ni infraestructura adicional.

Referencias técnicas consultadas: [CTrade](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade), [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [HistorySelectByPosition](https://www.mql5.com/en/docs/trading/historyselectbyposition), [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction), [códigos de respuesta](https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes), [órdenes y modos de llenado](https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties) y [particularidades del probador](https://www.mql5.com/en/docs/runtime/testing).
