# Mean Reversion EA — MVP para MetaTrader 5

EA monolítico en `MeanReversionEA.mq5`, exclusivamente MQL5 y biblioteca estándar `Trade/Trade.mqh`. Implementa `SPEC_MVP.md`, incluidas las aclaraciones de su sección 16. `AGENTS.md` contiene las instrucciones del proyecto.

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

## Comportamiento implementado

- Compra intrabar: `Low[0] <= LowerBand[0]` y `%K[0] < 10`. Venta: `High[0] >= UpperBand[0]` y `%K[0] > 90`. No se espera al cierre de vela ni a regresar dentro de las bandas.
- Una señal se identifica por vela M5 y dirección. Se consume al disponer de todos los datos, aunque falle riesgo o ejecución. La falta de datos permite volver a leerlos en ticks posteriores. Variables globales estándar del entorno MT5 guardan las señales consumidas, con clave por cuenta, símbolo y Magic, para conservarlas en una reinicialización. El probador emula estas variables separadamente del terminal.
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

Los fallos definitivos de cierre/cancelación se reintentan en ticks posteriores sin máximo de intentos. Las solicitudes todavía no resueltas bloquean duplicados y la finalización de la idea. Si no llega confirmación suficiente, el EA conserva el bloqueo y requiere diagnóstico manual; no deduce fracaso por el mero paso del tiempo. Si no llegan ticks, no puede enviar nuevos reintentos. Si E2 se ejecuta durante la limpieza, también se cierra su exposición propia, salvo protección por mezcla netting.

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
4. Mantener los parámetros predeterminados para la primera ejecución. Desactivar optimización; usar modo visual para inspeccionar entradas, niveles y enfriamiento.
5. Ejecutar y conservar informe, operaciones y Diario. Comprobar `SIGNAL`, `ENTRY`, `TP_UPDATE`, `EXIT_REQUEST`, `EXIT`, `REJECTED`, `REQUEST_PENDING`, `ERROR` y `MANUAL_REQUIRED`.
6. Contrastar los eventos con los 25 escenarios de la sección 12 de `SPEC_MVP.md`. Repetir en entornos de prueba hedging y netting; un backtest individual no demuestra ambas modalidades.
7. Registrar fechas, modelo de ticks, fuente de datos, moneda, configuración del símbolo, modo de cuenta y valores de entrada para reproducibilidad.

Los casos de posiciones mezcladas, reinicio con residuos, ejecución parcial y fallos del servidor requieren un entorno de prueba controlado o simulación de transacciones; un histórico que no produzca esos eventos no los valida. No usar cuentas reales para probarlos.

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
- Finalizar el probador o descargar el EA detiene su gestión. `OnDeinit` libera los indicadores; no intenta garantizar cierres durante la descarga. La siguiente inicialización limpia los residuos propios que existan.
- No se ha medido rendimiento ni rentabilidad. El historial se consulta para reconciliar propiedad y ciclo de vida; no se introducen filtros de señal ni infraestructura adicional.

Referencias técnicas consultadas: [CTrade](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade), [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [HistorySelectByPosition](https://www.mql5.com/en/docs/trading/historyselectbyposition), [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction), [códigos de respuesta](https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes), [órdenes y modos de llenado](https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties) y [particularidades del probador](https://www.mql5.com/en/docs/runtime/testing).
