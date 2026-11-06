# Mean Reversion EA — MVP para MetaTrader 5

EA monolítico en `MeanReversionEA.mq5`, exclusivamente MQL5 y biblioteca estándar `Trade/Trade.mqh`. Implementa `SPEC_MVP.md`, incluidas las aclaraciones de su sección 16 y las variantes experimentales de sus secciones 17–30. `AGENTS.md` contiene las instrucciones del proyecto.

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
| `InpStrategy` | ORIGINAL | ORIGINAL=0, BB_REENTRY=1, BB_WICK_REJECTION=2 o ATR_DEVIATION_REENTRY=3 |
| `InpATRDeviationThreshold` | 1.5 | Umbral T finito y positivo, solo ATR_DEVIATION_REENTRY |
| `InpWickMinRatio` | 0.40 | Mínima proporción mecha/rango; solo V6, 0 < ratio <= 1 |
| `InpReentryBBWFilter` | false | Interruptor general BBW, solo BB_REENTRY |
| `InpReentryBBWMode` | BBW_NON_INCREASING | V5A o BBW_BELOW_P70 (V5C), solo con filtro habilitado |
| `InpReentryADXMode` | ADX_OFF | Enum ADX experimental exclusivo de BB_REENTRY, periodo fijo 14 |
| `InpReentryMACDConfirm` | false | Confirmación MACD opcional exclusiva de BB_REENTRY |
| `InpMACDFast` | 12 | Periodo rápido MACD, positivo y menor que Slow |
| `InpMACDSlow` | 26 | Periodo lento MACD, positivo |
| `InpMACDSignal` | 9 | Periodo de señal MACD, positivo |
| `InpReentryWeekendGuard` | false | Protección semanal experimental exclusiva de BB_REENTRY |
| `InpWeekendEntryBlockMinutes` | 60 | Bloquear entradas desde este margen antes del cierre semanal |
| `InpWeekendCloseMinutes` | 30 | Solicitar WEEKEND_GUARD desde este margen |
| `InpReentryExitMode` | EXIT_SMA20_DYNAMIC | Solo BB_REENTRY: modos de salida definidos, incluido parcial SMA20 + trailing ATR |
| `InpReentrySLATR` | 3.0 | Multiplicador SL de las tres estrategias de una entrada; finito y >0, ignorado en ORIGINAL |
| `InpOscillator` | STOCHASTIC | Enum: STOCHASTIC original o RSI experimental |
| `InpRSIPeriod` | 14 | Periodo RSI M5, PRICE_CLOSE; solo al seleccionar RSI |
| `InpRSIBuyLevel` | 30 | Compra si RSI es estrictamente menor |
| `InpRSISellLevel` | 70 | Venta si RSI es estrictamente mayor |
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

En ORIGINAL, las distancias E2 = 1 ATR y SL = 3 ATR no son configurables. En BB_REENTRY solo existe E1, con SL = `InpReentrySLATR × ATR` (3 ATR predeterminado). El ATR se congela desde la última vela cerrada. El presupuesto no depende del balance o equity actuales.

## ATR_DEVIATION_REENTRY: regreso en unidades ATR

Nueva hipótesis experimental sin ventaja demostrada, valor3 del selector. Los valores anteriores0/1/2 y el predeterminado ORIGINAL permanecen. Usa **solo iMA SMA20 sobre Close y iATR14, ambos M5**, sin crear Bollinger ni osciladores/ADX/MACD. Ignora sus filtros, BBW, mechas e InpSignalMode. No intervienen en señal ni TP.

`D=(Close−SMA20)/ATR14`, con datos de la misma vela cerrada shift1 y sin redondeo. `InpATRDeviationThreshold=1.5` define T y debe ser finito y positivo. D<−T prepara compra; D>T prepara venta. No entra todavía. Compra confirma en una vela posterior si −T<D<0; venta si0<D<T.

Exteriores sucesivos del mismo lado mantienen la primera fecha y snapshot. El extremo opuesto sustituye preparación. Esperando compra, alcanzar/cruzar D0 descarta salvo que corresponda preparar venta exterior; análogo para venta. Igualdad con ±T no prepara ni confirma y conserva la preparación si no llegó a la media; D0 descarta. No hay vencimiento por velas ni condiciones sobre color/dirección de Close o movimiento del precio: un ATR mayor puede confirmar con Close sin cambio. Los cambios de Close/SMA/ATR se registran solo como diagnóstico.

Consume al confirmar aunque riesgo/ejecución rechacen. No acumula durante actividad, cierres, enfriamiento, solicitudes o bloqueos. Al iniciar espera nueva vela; datos ausentes/invalidos y discontinuidades limpian y omiten, sin entrada tardía. Se verifica continuidad por aperturas M5, permitiendo primer tick unos segundos tarde. Si se saltan oportunidades M5, también omite la evaluación que encuentra el salto. Las señales tienen marcas ATRDEV propias.

Reutiliza entrada única sin E2, ATR[1] congelado y SL desde ejecución real. **InpReentrySLATR aplica ahora a BB_REENTRY, BB_WICK_REJECTION y ATR_DEVIATION_REENTRY**, sin cambiar los comportamientos anteriores. La nueva estrategia usa InpATRMax configurable, predeterminado8. Volumen para una entrada con OrderCalcProfit, normalización, riesgo verificado antes/después y SL obligatorio. TP inicial y actualizaciones SMA20[1] del iMA propio, sin factor0.90; SL fijo. Conserva TP lógico/Bid/Ask, restricciones, cierre monetario, reintentos, propiedad/netting, reconciliación/EXIT_PENDING, enfriamiento, MFE/MAE y residuos.

La protección semanal también aplica y limpia preparación. Configuración de investigación manual, sin optimización:

```text
InpStrategy=ATR_DEVIATION_REENTRY
InpATRDeviationThreshold=1.5
InpReentrySLATR=2.0
InpATRMax=8
InpRiskBaseUSD=25000
InpRiskPercent=0.25
InpReentryWeekendGuard=true
InpWeekendEntryBlockMinutes=60
InpWeekendCloseMinutes=30
```

Repetir por separado T=2.0,2.5,3.0 manteniendo lo demás. INIT registra parámetros efectivos y guard. PREPARATION registra dirección, fecha y primer Close/SMA/ATR/D; las sustituciones/limpiezas indican motivo. SIGNAL incluye evaluación, fechas y snapshots de preparación/confirmación, diferencias de Close/SMA/ATR y referencia de mercado separada; no filtra esas diferencias. Se conservan ENTRY/TP_UPDATE/EXIT.

**Verificaciones ejecutadas:** pasan **19 tests auxiliares**, incluido nuevo escenario ATR de transiciones de ambos lados, igualdades, media/opuesto, primera preparación preservada, ATR creciente con Close inmóvil, shifts1, limpieza por datos/pausas/bloqueos y TP SMA sin Bollinger. Se ampliaron inicialización (solo iMA/ATR y umbrales), entrada real adaptada/riesgo/SL, guard semanal y formato de logs diagnósticos. Regresiones anteriores de señales, riesgo, PnL, propiedad y MFE/MAE pasan. Revisión estática realizada; **compilación MQL5 y backtesting pendientes**. Las pruebas extraen funciones MQL5 actuales con adaptadores C++, no ejecutan el compilador ni motor MT5. No se ha medido rentabilidad ni optimizado parámetros.

## V6: BB_WICK_REJECTION

Estrategia experimental de rechazo mediante mechas, sin ventaja demostrada. Se añade con valor **2**; ORIGINAL=0 y BB_REENTRY=1 conservan valores, comportamiento y predeterminado ORIGINAL. No necesita preparación exterior previa ni usa osciladores, ADX, MACD o BBW. Ignora esos parámetros e InpSignalMode. Solo crea Bollinger estándar M5 20/2.5 PRICE_CLOSE y ATR estándar M5 14.

Evalúa una vez por nueva vela, exclusivamente OHLC/Bollinger de la recién cerrada [1]. Rango=High−Low; mecha inferior=min(Open,Close)−Low; superior=High−max(Open,Close). Compra si Low <= Lower, mecha inferior/rango >= InpWickMinRatio y cierre estrictamente entre ambas bandas; venta con High >= Upper y mecha superior/rango >= ratio, con el mismo cierre interior. Ratio predeterminado0.40, finito y positivo hasta1. Igualdad de ratio permite; igualdad del Close con una banda rechaza. No redondea proporciones.

No exige color, Open dentro de bandas, tamaño de cuerpo, distancia mínima de cierre ni señal exterior anterior. Si cumple ambas direcciones, registra AMBIGUOUS_SIGNAL y descarta ambas. Rango cero u OHLC/Bollinger inválidos no operan. No imprime ausencia de señal cada vela.

Reutiliza gestión de una entrada: ATR[1] congelado, lote/riesgo para esa entrada, SL configurable desde la ejecución real y TP inicial/dinámico SMA20[1]. **InpReentrySLATR ahora aplica a ambas estrategias de una entrada**; ORIGINAL conserva SL3ATR. V6 usa **InpATRMax configurable**, predeterminado8; BB_REENTRY conserva su límite8 anterior. Se mantiene verificación de riesgo normalizado/ejecutado, SL obligatorio, cierre monetario, TP lógico y reintentos.

Señales identificadas por vela/dirección, consumidas aunque falle riesgo o ejecución. No acumula durante actividad, cierre, enfriamiento o bloqueos. Al iniciar espera nueva vela; exige continuidad de horas de apertura, permitiendo ticks unos segundos tarde. Descarta barras antiguas y datos faltantes sin ejecución retrospectiva. Las marcas WICK se separan de las otras estrategias. Mantiene propiedad/netting, solicitudes inciertas, reconciliación/EXIT_PENDING, MFE/MAE y limpieza de residuos.

La protección semanal existente también aplica a V6 cuando se habilita; conserva sesiones, márgenes, bloqueo/cierre y limitaciones anteriores. Para probar, sin optimización:

```text
InpStrategy=BB_WICK_REJECTION
InpWickMinRatio=0.40
InpReentrySLATR=2.0
InpATRMax=8
InpRiskBaseUSD=25000
InpRiskPercent=0.25
InpReentryWeekendGuard=true
InpWeekendEntryBlockMinutes=60
InpWeekendCloseMinutes=30
```

INIT registra estrategia, ratio, SL y guard semanal. SIGNAL incluye hora de evaluación/vela, dirección, OHLC, bandas, SMA, ATR, rango, cuerpo, ambas mechas y sus proporciones, cuerpo/rango y distancia de Close desde la banda tocada dividida por ATR. Estas dos últimas métricas son **solo diagnóstico**. Cotización Bid/Ask y referencia E1 se registran aparte del Close, sin presentarlas como ejecución real. ENTRY/TP_UPDATE/EXIT y MFE/MAE se conservan.

**Verificaciones ejecutadas:** 18 tests offline pasan, incluido un nuevo test guardado de V6 con ratio40%, igualdad de Close, Open exterior, ambos colores/doji, señal doble, rango/valores inválidos, shifts, no preparación, no duplicados/señales antiguas/tardías, bloqueo por actividad/enfriamiento. Se ampliaron ejecución real adaptada, inicialización y guard semanal para V6. Las regresiones de ORIGINAL/BB_REENTRY, propiedad, riesgo, reintentos, PnL y MFE/MAE siguen pasando. Son funciones extraídas con respuestas MT5 simuladas, no ejecución de bróker. Revisión estática realizada; **compilación MQL5 y backtesting pendientes** en MetaEditor/MT5. El entorno WSL previamente no pudo arrancar MetaEditor; se conserva la indicación de compilar por parte del usuario.

## BB_REENTRY: una entrada y reingreso a Bollinger

Seleccionar **`InpStrategy=BB_REENTRY`**. Es una hipótesis experimental sin rentabilidad demostrada. `ORIGINAL` sigue siendo el valor predeterminado y conserva sus combinaciones Stochastic/RSI e INTRABAR/CLOSED_BAR.

| Aspecto | ORIGINAL | BB_REENTRY |
| --- | --- | --- |
| Señal | Extremo del oscilador + Bollinger según modo | Cierre exterior seguido de otro cierre estrictamente interior |
| Evaluación | INTRABAR o CLOSED_BAR | Solo una vez por nueva vela, shift=1 |
| Oscilador | Stochastic o RSI | Ninguno; no se crea su handle |
| Entradas | E1 + E2 pendiente del mismo lote | Solo E1, sin pendientes E2 |
| Riesgo teórico | Dos entradas, 5 ATR | Una entrada, InpReentrySLATR × ATR |
| TP inicial | Factor desde banda exterior, datos [0] | SMA20[1] de confirmación |
| TP posterior | Factor desde banda exterior, datos [1] | SMA20[1] de última vela cerrada |

BB_REENTRY usa valores fijos: **Bollinger 20/2.5, PRICE_CLOSE; ATR 14 y máximo 8; M5**. La SMA20 es el buffer central de iBands, sin indicador adicional. No intervienen ni se validan `InpSignalMode`, `InpOscillator`, parámetros RSI/Stochastic, `InpBollingerPeriod`, `InpBollingerDeviation`, `InpATRPeriod`, `InpATRMax` ni `InpTPFactor`. Estas entradas siguen aplicando a ORIGINAL. Sí aplican capital/riesgo, Magic Number, desviación de ejecución y logs.

Un cierre por debajo de la banda inferior prepara compra; por encima de la superior prepara venta. No entra en esa vela. El primer cierre posterior estrictamente entre ambas bandas confirma la dirección preparada, sin exigir nuevo toque. Una mecha exterior con cierre interior no prepara. Cierres exteriores del mismo lado mantienen la preparación y su vela inicial; un cierre exterior opuesto la sustituye. La igualdad con cualquier banda conserva la preparación sin confirmar. No hay vencimiento por número de velas.

La preparación se consume al confirmar aunque se rechace riesgo/ejecución; se limpia al iniciar idea y enfriamiento. No se acumula durante actividad, cierre, solicitudes inciertas o bloqueos. Al iniciar/reiniciar está vacía y espera una nueva vela. Cada cierre debe ser contiguo a la nueva vela por sus horas de apertura (300 segundos); el primer tick puede llegar unos segundos tarde. Ante una barra antigua tras una pausa se limpia y omite esa evaluación. Si se saltan oportunidades M5, se limpia la secuencia anterior; solo la última barra contigua puede preparar una secuencia nueva. Datos ausentes limpian y descartan sin entrada retrospectiva.

Congela ATR[1] de confirmación. El lote se calcula con OrderCalcProfit para una entrada hasta SL a `InpReentrySLATR × ATR`, con precios normalizados y volumen hacia abajo; vuelve a verificarse después de ejecutar E1. Por ejemplo, USD 25,000 al 0.25% son USD 62.50; con contrato de 100 onzas, ATR 2 y paso 0.01, con multiplicador 3.0 el lote de referencia es **0.10**, riesgo USD 60; con 2.0 es **0.15**, también USD 60. No usa el presupuesto de 5 ATR de ORIGINAL. Un fallo de riesgo o SL tras E1 inicia cierre persistente; no ajusta volumen ni desplaza SL.

El objetivo inicial es SMA20[1] de confirmación, normalizado al tick, y se actualiza con SMA20[1] cada nueva vela en ambos sentidos. Compra comprueba Bid >= objetivo; venta Ask <= objetivo. Un objetivo ya alcanzado inicia cierre a mercado. El SL permanece fijo. Stops/freeze que impidan TP de servidor dejan un objetivo lógico por tick y los reintentos controlados comunes. Las lecturas pendientes de TP durante una idea pueden reintentarse; las evaluaciones de señal descartadas no se recuperan.

Se conservan cierre monetario, criterio de costes, propiedad/netting, solicitudes inciertas, reconciliación/EXIT_PENDING, enfriamiento y MFE/MAE. El presupuesto no garantiza pérdida máxima frente a gaps o deslizamiento. Las explicaciones posteriores sobre E2, factor TP y osciladores corresponden a ORIGINAL; las protecciones y limitaciones compartidas aplican a ambas estrategias.

Logs: `INIT estrategia=BB_REENTRY`; `PREPARATION` con dirección, vela, cierre y bandas; `PREPARATION_CLEAR` con motivo; `SIGNAL` con vela exterior inicial y de confirmación, cierre, bandas, SMA20, ATR y shift; `ENTRY` con ejecución real, lote, SL, TP, riesgo y multiplicador efectivo `SL_ATR`; INIT también incluye `SL_ATR`. Se conservan actualizaciones, rechazos y cierres con MFE/MAE.

**Verificación:** suite offline de **22 tests**, incluidos escenarios del OnTick y OnInit reales extraídos del fuente y ejecución auxiliar de OpenIdea/SL/TP con respuestas MT5 simuladas. Cubre las 14 verificaciones de BB_REENTRY, validación solo de entradas pertinentes, ausencia de osciladores, una entrada sin E2, riesgo para multiplicadores 3.0/2.0 y su revisión tras ejecución, SL fijo, TP lógico/servidor, fallos y regresiones ORIGINAL/MFE/MAE/reconciliación. La revisión estática se distingue de estas simulaciones: no son compilación MQL5 ni backtesting.

**Pendiente:** compilar esta versión con F7 en MetaEditor y validar en el Probador. Se mantiene la indicación del usuario de compilar por su cuenta; la invocación local anterior falló por interoperabilidad WSL y no hay resultado de compilación para esta versión. No se ejecutó backtesting ni optimización.

Para comparar SL, ejecutar dos backtests con idénticos datos y parámetros, cambiando únicamente `InpReentrySLATR=3.0` por `2.0`. El multiplicador debe ser finito y positivo, se valida solo en BB_REENTRY y se utiliza tanto para calcular el volumen previo como para establecer el SL desde el precio real. El volumen se redondea hacia abajo y se verifica el riesgo tras normalizar y ejecutar; si falla, se aborta y gestiona el cierre. Se mantiene `InpRiskPercent=0.25`, sin modificar señal, ATR congelado, entrada única, TP, enfriamiento ni protecciones. Las regresiones auxiliares para ambos multiplicadores pasan; compilación MQL5 y backtesting de esta versión siguen pendientes.

Para probar: `InpStrategy=BB_REENTRY`, `InpRiskBaseUSD=25000`, `InpRiskPercent=0.25`; M5, ticks reales, cuenta USD y optimización desactivada. Inspeccionar preparación, confirmación, una sola entrada, ausencia de E2, SL fijo y cambios del objetivo SMA20 en el Diario y modo visual. Repetir con ORIGINAL y su configuración anterior para contrastar la regresión operativa.

### EXIT_HALF_SMA20_TRAIL_ATR: 50% en SMA20 y trailing del remanente

Nueva opción experimental **4** de `InpReentryExitMode`, exclusiva de BB_REENTRY. Valores0..3 y predeterminado0 no cambian. El nombre HALF se refiere al **volumen**, no a media distancia a SMA20.

Antes del parcial, el objetivo lógico es **SMA20[1]**, actualizado cada nueva vela M5. No se instala TP de posición que liquide todo el volumen. Compra activa cuando Bid>=SMA y venta cuando Ask<=SMA. Mantiene la entrada única, SL inicial, ATR congelado, riesgo y filtros anteriores.

Al alcanzar, cierra50% del volumen inicial en pasos enteros, hacia abajo:0.15 con paso0.01 implica cerrar0.07 y dejar0.08. Ambos deben cumplir mínimo/paso; si no, registra PARTIAL_NOT_POSSIBLE y cierra toda la idea mediante la gestión común. No espera que el precio vuelva al objetivo tras un rechazo: conserva la solicitud activada para reintentar cuando proceda.

El parcial usa un deal contrario dirigido al ticket (`MqlTradeRequest.position`), compatible con [hedging y netting](https://www.mql5.com/en/docs/constants/structures/mqltraderequest), con controles de símbolo/Magic/identificador/volumen. No abre una segunda entrada ni añade pendientes. La [herencia de SL/TP de MT5](https://www.metatrader5.com/en/terminal/help/trading/general_concept) conserva las protecciones durante un parcial; además el EA exige SL válido y TP0. Siguen aplicando exclusividad netting y protección de posición mezclada.

**No activa trailing solo por un código de éxito o cambio de volumen:** exige orden terminal, todos sus deals y volumen reconciliado. Identifica cada intento por comentario único y recuerda sus órdenes. Duplicados y eventos atrasados no repiten el parcial. Ante ejecución IOC incompleta solicita solo la diferencia tras reconciliar; si no es negociable, cierra todo. Un resultado incierto conserva bloqueo, sin liberarlo por tiempo. Si no aparece identidad/historial suficiente, puede requerir intervención; se mantiene la protección y no se inventa una ejecución fallida para reenviar.

Tras confirmar el parcial, inicia el seguimiento con Bid/Ask vigente entonces, sin precios previos ni MFE. Compra: SL candidato=máximo Bid observado−1 ATR de entrada; venta: mínimo Ask observado+1 ATR de entrada. Observa por tick, normaliza al tick y solo mejora SL, respetando stops/freeze. No aplica breakeven independiente. Mantiene SL vigente durante rechazos y acredita cambios solo al confirmarlos en la posición. El remanente queda sin TP y no vuelve a actualizar SMA ni enviar otro parcial.

La idea continúa activa y MFE/MAE no se reinician. El PnL definitivo suma parcial y remanente con los costes ya reconciliados. Cierre monetario/semanal conserva prioridad; si hay solicitud parcial incierta o volumen sin conciliar, se espera su resolución antes de solapar otro cierre de la misma posición. EXIT/EXIT_PENDING y enfriamiento solo concluyen al completar toda la exposición y solicitudes. Reiniciar mantiene la limpieza de residuos anterior, sin reconstruir un trailing histórico.

Logs: INIT/ENTRY con modo; TP_UPDATE para objetivo previo; PARTIAL_TARGET, PARTIAL_REQUEST, PARTIAL_PENDING, PARTIAL_REJECTED, PARTIAL_CONFIRMED con restante; TRAIL_UPDATE para SL confirmado; PARTIAL_NOT_POSSIBLE para cierre completo. Las esperas no generan solicitudes duplicadas ni logs idénticos por tick.

Para probar: BB_REENTRY y `InpReentryExitMode=EXIT_HALF_SMA20_TRAIL_ATR`, manteniendo los demás parámetros y datos. Es una hipótesis sin ventaja demostrada; no se optimizó.

**Verificaciones ejecutadas:** pasan **22 tests auxiliares**, con dos escenarios nuevos guardados. Se prueban funciones reales de división/envío/reconciliación/trailing con respuestas simuladas: compra/venta, payload dirigido a posición para ambos modelos, división impar o inválida, TP servidor0, rechazo con control de reintentos, resultado incierto recuperado por comentario, deals/volumen atrasados, callbacks duplicados, IOC parcial, orden no terminal, SL concurrente, identidad/propiedad, extremo desde confirmación, ATR congelado, SL sin aflojar, errores y confirmación tardía de SL y PnL parcial+remanente. OnTick real con colaboradores simulados verifica encaminamiento al parcial y prioridad monetaria. Las regresiones anteriores de cierre/netting/reintentos/PnL/MFE/MAE siguen pasando.

**Pendiente:** compilación MQL5 en MetaEditor y backtesting MT5 con cuenta de prueba hedging/netting. Las pruebas compilan fragmentos en C++, sin terminal ni servidor real, y no acreditan esas verificaciones. La interoperabilidad WSL previamente impidió arrancar MetaEditor. No se hicieron operaciones reales, commit ni push.

### Salida EXIT_OPPOSITE_BAND_DYNAMIC

Seleccionar `InpStrategy=BB_REENTRY` y `InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC`. La nueva opción vale **3**; se conservan 0=SMA20 dinámica (predeterminado), 1=ATR fijo2 y 2=media distancia SMA20 dinámica. Las otras estrategias ignoran el selector.

Compra fija el objetivo en **UpperBand[1]**; venta en **LowerBand[1]**, usando el iBands existente y sus parámetros actuales. El TP inicial utiliza el snapshot cerrado de la señal y se establece **después de confirmar la ejecución real de E1**. Cada nueva vela M5 se recalcula con shift1, normalizado al tick, permitiendo cambios en ambos sentidos. No usa la vela en formación ni InpTPFactor.

Compra cierra si Bid >= objetivo y venta si Ask <= objetivo. Si ya está alcanzado al asignar o actualizar, inicia cierre a mercado. Mantiene TP lógico y reintentos si stops/freeze o rechazos del servidor impiden asignarlo, con SL obligatorio e inmóvil. INIT/ENTRY identifican el modo y se conserva TP_UPDATE.

Entrada, riesgo/volumen, ATR congelado, SL, filtros, guard semanal, enfriamiento, propiedad/netting, reconciliación y MFE/MAE no cambian. Hipótesis experimental sin ventaja demostrada; comparar cambiando solo el selector, sin optimización.

**Verificaciones ejecutadas:** pasan los **20 tests auxiliares ampliados**, con TP inicial superior/inferior, normalización, objetivo ya alcanzado al abrir, fallback/reintento conservando SL, actualizaciones de shift1 en ambos sentidos y cierre al alcanzar el nuevo objetivo. Se mantienen regresiones de las tres salidas anteriores y de otras estrategias. Revisión estática realizada. **Compilación MQL5 y backtesting de esta versión pendientes** en MetaEditor/MT5; los tests C++ con respuestas simuladas no equivalen a esas verificaciones.

### Salida EXIT_HALF_SMA20_DYNAMIC

Nueva opción exclusiva de BB_REENTRY: `EXIT_HALF_SMA20_DYNAMIC=2`. Los valores anteriores permanecen `EXIT_SMA20_DYNAMIC=0` (predeterminado) y `EXIT_ATR_FIXED_2=1`; sus comportamientos no cambian.

Para compras y ventas: **TP = E1 ejecutada + 0.50 × (SMA20[1] − E1 ejecutada)**, normalizado al tick. El TP inicial se calcula después de conocer el precio real de E1. En cada nueva vela se recalcula con SMA20[1], conservando E1 fija durante toda la idea. No se calcula desde Bid/Ask actuales ni se aplica InpTPFactor.

Compra cierra si Bid >= objetivo; venta si Ask <= objetivo. Si el objetivo recalculado ya está alcanzado, inicia cierre a mercado. Mantiene objetivo lógico y reintentos de sincronización ante restricciones del bróker, sin tocar SL. INIT/ENTRY registran el modo y se conserva TP_UPDATE. Señal, entrada única, lotaje/riesgo, ATR congelado, SL, cierre monetario/semanal, propiedad, enfriamiento, reconciliación y MFE/MAE permanecen iguales. Las otras estrategias ignoran el selector.

Para comparar con las salidas anteriores, mantener BB_REENTRY y todos los demás parámetros/datos y cambiar solo `InpReentryExitMode=EXIT_HALF_SMA20_DYNAMIC`. Hipótesis experimental sin ventaja demostrada; sin optimización.

**Verificación ejecutada:** pasan **20 tests auxiliares**, con nuevo escenario de OnTick/Target reales para actualización desde shift1, E1 fija distinta de cotización actual, ambas direcciones, SL intacto y cierre al alcanzar el nuevo objetivo. También se amplía OpenIdea real adaptado para usar el fill, recuperación de TP rechazado, TP_UPDATE y aislamiento de otras estrategias. Se conservan las regresiones SMA completa/ATR fijo, guard semanal, PnL y MFE/MAE. Revisión estática realizada; **compilación MQL5 y backtesting pendientes** en MetaEditor/MT5. Las compilaciones C++ auxiliares no acreditan compilación MQL5 ni ejecución real del EA.

### S3: TP fijo a 2 ATR desde la ejecución real

`InpReentryExitMode` es exclusivo de BB_REENTRY. `EXIT_SMA20_DYNAMIC` sigue predeterminado y conserva la salida anterior; **`EXIT_ATR_FIXED_2`** selecciona S3 experimental. Las otras estrategias ignoran el selector.

S3 mantiene exactamente señales y validaciones de entrada. Tras ejecutar E1, fija el TP normalizado al tick: compra **E1 real + 2 × ATR congelado**, venta **E1 real − 2 × ATR congelado**. Usa el ATR de confirmación ya congelado, sin cotización solicitada, ATR posterior, SMA ni factor0.90. No cambia con velas nuevas. No añade trailing, breakeven, cierres parciales ni otras salidas.

Con SL de 2 ATR, las distancias nominales son 1:1 antes de redondeos/ejecución; **no es garantía de relación monetaria exacta**. El lote continúa calculándose desde SL y presupuesto de riesgo, sin intervención del TP. El SL válido sigue siendo obligatorio.

Reutiliza objetivo lógico por Bid/Ask, stops/freeze y reintentos: si el servidor rechaza TP, conserva supervisión y puede sincronizarlo después, sin mover SL ni enviar modificaciones redundantes. Las ventanas monetarias y semanales siguen activas, así como propiedad/netting, enfriamiento, reconciliación, EXIT_PENDING y MFE/MAE. La supervisión durante WEEKEND_GUARD tampoco recalcula un objetivo fijo.

INIT incluye salida efectiva. ENTRY incluye modo, E1 real, ATR congelado, lote, SL/TP normalizados y riesgo. S3 usa `TP_SYNC` para sincronización con servidor; no registra cambios de objetivo por nuevas velas. Las explicaciones de SMA20 dinámica en BB_REENTRY corresponden al modo predeterminado; V6 y ATR_DEVIATION_REENTRY conservan sus salidas SMA.

Configuración de prueba, sin optimización:

```text
InpStrategy=BB_REENTRY
InpReentryExitMode=EXIT_ATR_FIXED_2
InpReentrySLATR=2.0
InpRiskBaseUSD=25000
InpRiskPercent=0.25
InpReentryADXMode=ADX_OFF
InpReentryMACDConfirm=false
InpReentryBBWFilter=false
InpReentryWeekendGuard=true
InpWeekendEntryBlockMinutes=60
InpWeekendCloseMinutes=30
```

**Verificaciones ejecutadas:** pasan **19 tests auxiliares ampliados**: TP compra/venta desde fill distinto de Bid/Ask inicial, tick de 0.05, ATR congelado, ausencia de lecturas/recalculo del objetivo cuando cambian SMA/ATR, fallback y sincronización sin alterar SL, ausencia de modificaciones redundantes, logs TP_SYNC, cierres monetario y semanal, salida dinámica y estrategias ajenas al selector. Los tests de gestión/reconciliación/MFE/MAE siguen pasando. Revisión estática realizada. **Compilación MQL5 y backtesting pendientes** en MetaEditor/MT5; la ejecución C++ con adaptadores no los sustituye. No hay ventaja estadística demostrada.

### V5A: filtro experimental BBW

`InpReentryBBWFilter=true` exige **BBW[1] <= BBW[2]** en el primer cierre de reingreso estrictamente interior. `BBW[i]=(Upper[i]-Lower[i])/SMA[i]`, usando el iBands existente y la SMA de cada vela, exclusivamente las dos últimas cerradas. Igualdad permite; aumento rechaza. No se redondea antes de comparar. La variante V5C, descrita a continuación, es una alternativa. No se implementa V5B.

Valida lecturas completas, números finitos, SMA positiva, bandas ordenadas y cocientes finitos. Rechazo o datos incompletos/invalidos consumen la preparación y exigen otra exterior, sin entrada tardía. No afecta posiciones ya abiertas ni ORIGINAL. Con false conserva la operativa anterior sin leer BBW[2]. ADX y MACD permanecen disponibles; si se combinan, todos deben permitir el mismo reingreso mediante AND. Las combinaciones quedan fuera de esta prueba.

Configuración de prueba, sin optimización:

```text
InpStrategy=BB_REENTRY
InpReentryBBWFilter=true
InpReentryADXMode=ADX_OFF
InpReentryMACDConfirm=false
InpReentrySLATR=2.0
InpReentryWeekendGuard=true
InpWeekendEntryBlockMinutes=60
InpWeekendCloseMinutes=30
InpRiskBaseUSD=25000
InpRiskPercent=0.25
```

INIT registra activación. BBW_FILTER registra dirección, fechas de ambas velas, sus bandas y SMA, BBW1/BBW2 con 17 dígitos significativos, resultado y motivo; datos ausentes se indican n/a. Sin repetición por tick. Esta hipótesis experimental no tiene ventaja demostrada; el resto de la gestión se mantiene.

**Verificaciones ejecutadas:** pasan los 17 tests auxiliares guardados y ampliados: disminución/igualdad/aumento en ambas direcciones, SMA distinta por vela, shifts cerrados, aumento diminuto sin redondeo, datos incompletos/invalidos sin ejecución tardía, filtro apagado y aislamiento de la gestión. Revisión estática realizada. Compilación MQL5 y backtesting siguen pendientes en MetaEditor/MT5; el entorno WSL previamente no pudo arrancar MetaEditor. No se han optimizado parámetros ni probado rentabilidad.

### BBW V5C: referencia P70

El interruptor sigue siendo `InpReentryBBWFilter=false`. Para comparar, mantener iguales datos y demás parámetros y ejecutar:

| Variante | Configuración | Regla |
| --- | --- | --- |
| Sin filtro | InpReentryBBWFilter=false | Modo ignorado |
| V5A | true y BBW_NON_INCREASING | BBW[1] <= BBW[2] |
| V5C | true y BBW_BELOW_P70 | BBW[1] < P70 |

`InpReentryBBWMode=BBW_NON_INCREASING` sigue predeterminado. Los modos son alternativos, no se acumulan. V5C calcula la referencia con **exactamente BBW[2..101]**, 100 velas anteriores a la señal. Cada cociente usa su propia SMA y bandas. Ordena ascendentemente una copia y toma **índice 69**, el elemento 70; sin interpolación ni redondeo. BBW[1] es solo el valor de señal, nunca se incluye en la referencia. Igualdad con P70 rechaza.

Valida los 101 cocientes, disponibilidad y fechas, finitud, SMA positiva y Upper >= Lower. No utiliza shift0/futuro ni añade continuidad obligatoria al histórico de referencia. Rechazos o datos insuficientes consumen la preparación sin entrada tardía. Los filtros MACD/ADX activos siguen combinándose mediante AND, sin modificar su configuración. ORIGINAL, gestión y filtro desactivado permanecen iguales.

INIT registra el modo efectivo; apagado indica OFF. V5C registra vela de señal, BBW1, fechas de inicio (shift101) y fin (shift2) de la referencia, valores=100, P70, resultado y motivo. Si faltan datos, informa el número obtenido, los 100 requeridos y n/a para el percentil no calculado. No repite por tick.

Para la prueba anterior, cambiar solo el modo BBW a `BBW_BELOW_P70`; conservar ADX_OFF, MACD false, SL2, guard60/30 y riesgo 0.25% de USD25000. Hipótesis experimental sin ventaja demostrada. No se añade V5B ni otro umbral y no se ejecuta optimización automática.

**Verificación ejecutada:** pasan los 17 tests auxiliares guardados y ampliados: referencia desordenada con distinción entre puestos69/70, igualdad, exclusión de señal, lectura exacta2..101, SMA distinta por vela, alternativas no acumulativas, datos insuficientes/invalidos en shifts2/51/101 sin entrada tardía, V5A y filtro apagado. Revisión estática realizada; compilación MQL5 y backtesting de esta versión pendientes en MetaEditor/MT5.

### Filtro ADX experimental

`InpReentryADXMode` permite comparar cuatro modos predefinidos. Es una hipótesis experimental sin ventaja demostrada; **ADX bajo no garantiza lateralidad**.

| Modo | Condición en el primer reingreso interior |
| --- | --- |
| ADX_OFF | Predeterminado, conserva comportamiento anterior |
| ADX_BELOW_25 | ADX[1] < 25 |
| ADX_BELOW_20 | ADX[1] < 20 |
| ADX_BELOW_25_FALLING | ADX[1] < 25 y ADX[1] < ADX[2] |

Usa [iADX estándar](https://www.mql5.com/en/docs/indicators/iadx), periodo fijo 14, símbolo del EA y M5, exclusivamente MAIN_LINE (buffer 0), sin DI ni iADXWilder. Solo crea/libera el handle con BB_REENTRY y ADX activo. Comparaciones estrictas, iguales para compras/ventas: igualdad con el umbral o entre ADX[1]/ADX[2] en FALLING rechaza. No usa shift=0. ADX[2] solo se lee en FALLING.

El filtro se evalúa únicamente en el primer cierre posterior estrictamente interior, consumiendo la preparación incluso si rechaza o faltan datos; se exige otra preparación exterior, sin esperar ni ejecutar retrospectivamente. No cierra ni modifica posiciones por cambios posteriores del ADX. ORIGINAL y el resto de la gestión permanecen iguales. MACD conserva su selector: si ambos están activos, ambos deben permitir el mismo reingreso mediante AND, combinación fuera de esta prueba.

Configuración para las cuatro ejecuciones, sin optimización automática:

```text
InpStrategy=BB_REENTRY
InpReentryMACDConfirm=false
InpReentrySLATR=2.0
InpReentryWeekendGuard=true
InpWeekendEntryBlockMinutes=60
InpWeekendCloseMinutes=30
InpRiskBaseUSD=25000
InpRiskPercent=0.25
```

Cambiar solo `InpReentryADXMode` entre los cuatro valores y conservar los demás parámetros/datos. Los valores predeterminados globales de SL y protección semanal no cambian.

INIT incluye modo ADX, periodo 14 y estado MACD. ADX_FILTER registra dirección, vela de reingreso, modo, ADX1, ADX2 cuando corresponde, resultado y motivo; datos no disponibles se marcan n/a. Con OFF no se consultan ni registran valores ADX ficticios. Sin repetición por tick.

**Verificación:** los 17 tests auxiliares guardados se ampliaron para todos los modos, ambas direcciones, igualdades, descenso simultáneo al umbral, shifts/buffer, consumo de rechazo/datos incompletos sin ejecución tardía, creación condicional, OFF/ORIGINAL, aislamiento de la gestión y AND con MACD. Revisión estática realizada. Compilación MQL5 y backtesting pendientes en MetaEditor/MT5; no se acredita ventaja estadística.

### Confirmación MACD experimental opcional

Para probar: `InpStrategy=BB_REENTRY`, `InpReentryMACDConfirm=true`, periodos `12/26/9` y `InpReentrySLATR=2.0`. Mantener iguales el riesgo, TP y parámetros de protección semanal para comparar; no optimizar. Es una hipótesis experimental sin rentabilidad demostrada.

Se utiliza [iMACD estándar](https://www.mql5.com/en/docs/indicators/imacd), M5 y PRICE_CLOSE. El handle se crea/libera solo cuando la confirmación está habilitada en BB_REENTRY. Solo entonces se validan periodos positivos y Fast < Slow. ORIGINAL ignora el filtro y sus periodos.

**H = MAIN_LINE − SIGNAL_LINE** (buffers 0 y 1); H no son las barras MAIN_LINE que muestra MT5. En el primer cierre posterior estrictamente dentro de Bollinger, compra exige `H[1] < 0 && H[1] > H[2]`; venta exige `H[1] > 0 && H[1] < H[2]`. Solo velas cerradas, sin cruces, divergencias ni otra condición. Se consume la preparación tanto al confirmar como al rechazar; datos MACD ausentes también la descartan, sin reintentos tardíos. Después se exige una nueva preparación exterior.

INIT registra configuración efectiva. `MACD_CONFIRM` incluye dirección, velas exterior/reingreso, MAIN1, SIGNAL1, H1, H2 y resultado; si el snapshot no está completo aparecen n/a y el motivo, sin inventar valores. No se repite por tick. Con false no se lee MACD ni cambia la señal anterior. Las referencias anteriores a ausencia de indicadores adicionales admiten este MACD y el filtro ADX opcionales.

Los tests están guardados en test/: ambas direcciones, igualdades estrictas, buffers/shifts, consumo de rechazo y datos incompletos, ausencia de entradas tardías, periodos/handle condicionales y regresión desactivada. Pasan los **17 tests auxiliares** existentes ampliados. Revisión estática realizada; compilación MQL5 y backtesting de esta versión pendientes en MetaEditor/MT5. No cambian la entrada única, gestión, protección semanal ni métricas.

### Protección experimental de cierre semanal

Para probarla, seleccionar `InpStrategy=BB_REENTRY` y **`InpReentryWeekendGuard=true`**, con `InpWeekendEntryBlockMinutes=60` e `InpWeekendCloseMinutes=30`. Se valida `bloqueo >= cierre > 0` únicamente cuando la protección está habilitada en BB_REENTRY. El valor predeterminado false conserva el comportamiento anterior; ORIGINAL ignora estos parámetros.

El EA lee las sesiones semanales del símbolo con [SymbolInfoSessionTrade](https://www.mql5.com/en/docs/marketinformation/symbolinfosessiontrade), en hora del servidor. Une sesiones solapadas o contiguas, admite múltiples sesiones, cruces de medianoche y final 00:00. Trata una sesión válida 00:00–00:00 como un día completo y rechaza iguales no nulos por duración ambigua. No utiliza hora local ni una hora de viernes fija.

Solo considera identificable el descanso si existe **una única interrupción superior a 24 horas** en el patrón semanal unido. Las pausas diarias no bloquean entradas. Horarios 24/7, varias interrupciones extensas, datos ausentes o errores de lectura producen `WEEKEND_SCHEDULE_ERROR`: se limpian preparaciones y se bloquean entradas, conservando la gestión normal de posiciones existentes. No se inventa un cierre ni se fuerza la salida por un horario desconocido. Esta identificación es deliberadamente conservadora: horarios que no cumplan el criterio requieren revisión, no una suposición automática.

Desde el margen de bloqueo (inclusive) descarta nuevas señales y limpia la preparación; desde el de cierre inicia `CLOSING_IDEA` con motivo `WEEKEND_GUARD`. Usa CloseStep, sus reintentos y protección de propiedad/netting. Mientras quede exposición continúa supervisando riesgo, SL y objetivo SMA20, dando prioridad a los intentos de cierre. Conserva reconciliación, EXIT_PENDING, PnL, MFE/MAE y enfriamiento. No agrega pendientes ni cambia el lotaje o el SL.

El bloqueo dura hasta la siguiente sesión semanal. Al liberar, deja preparación NONE y omite la vela anterior al primer evento de desbloqueo; además conserva la continuidad M5. Una salida pendiente sigue en CLOSING_IDEA. Si no hubo eventos antes del cierre y una idea sobrevive hasta la reapertura, registra el incumplimiento del cierre conocido y continúa con el cierre WEEKEND_GUARD.

Logs esenciales, sin repetición por tick: `INIT` con activación/márgenes; `WEEKEND_SCHEDULE` con fechas de cierre/reapertura y cambios; `WEEKEND_SCHEDULE_ERROR`; `WEEKEND_BLOCK_START/END`; `EXIT_REQUEST ... WEEKEND_GUARD`; errores de cierre y `WEEKEND_EXPOSURE` si llega el cierre previsto con exposición. Se aplica durante la inicialización, sin reconstruir señales históricas.

**Limitaciones:** las sesiones son un patrón semanal del bróker, no un calendario completo de festivos ni garantía de horarios históricos o cierres extraordinarios. No se puede acreditar desde esta API que el patrón esté completo o vaya a respetarse. Un cierre adelantado, rechazos o ausencia de ticks pueden impedir quedar sin exposición. La consulta se renueva al iniciar y como máximo cada minuto del servidor; los límites conocidos se comprueban en cada tick. No hay temporizador que sustituya eventos ausentes ni otros filtros horarios.

**Verificación:** pasan **17 tests offline**, incluida la lectura y unión de sesiones simuladas, pausas diarias, límites exactos, bloqueo/limpieza, reapertura, exposición residual, horarios cambiantes, sesiones múltiples/nocturnas y medianoche, semanas, fallos y aislamiento de ORIGINAL/desactivada. La ruta WEEKEND_GUARD se prueba con OnTick y supervisión reales y respuestas simuladas; los reintentos/protección, PnL y MFE/MAE mantienen sus regresiones propias. CloseStep, reconciliación, medición, señal, riesgo, lotaje, SL y TP comunes permanecen sin cambios. **No son compilación MQL5 ni backtesting MT5**. Quedan pendientes compilar en MetaEditor (el entorno WSL previamente no pudo arrancarlo) y probar con las sesiones reales del símbolo, guardando Diario e informe; sin optimización ni operaciones reales.

## ORIGINAL: variantes experimentales de señal

`InpSignalMode` selecciona la oportunidad de evaluación, independientemente de `InpOscillator`. `INTRABAR` conserva la variante original y continúa siendo el valor predeterminado. `CLOSED_BAR` es una variante de confirmación al cierre para comparar mediante backtesting; ninguna variante supone rentabilidad ni uso en producción.

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

### Selección experimental de RSI

`InpOscillator=STOCHASTIC` conserva las señales originales %K <10 / >90 y sus parámetros 14,3,3. `InpOscillator=RSI` usa el indicador estándar [iRSI](https://www.mql5.com/en/docs/indicators/irsi) del símbolo del EA, M5 y PRICE_CLOSE. RSI es una hipótesis experimental sin rentabilidad demostrada.

Para probar **RSI 14, 30/70 con CLOSED_BAR**, configurar:

```text
InpOscillator=RSI
InpRSIPeriod=14
InpRSIBuyLevel=30
InpRSISellLevel=70
InpSignalMode=CLOSED_BAR
```

Compra si RSI <30; venta si RSI >70. RSI igual a 30 o 70 no cumple el extremo correspondiente. No se exigen cruces, pendientes ni divergencias. En INTRABAR se usa RSI[0]; en CLOSED_BAR, RSI[1], manteniendo toque Bollinger y cierre estrictamente dentro de ambas bandas en la misma vela. La tabla anterior describe STOCHASTIC; para RSI se sustituye únicamente su condición %K por estos umbrales.

Solo se crea el handle seleccionado y solo se validan sus parámetros. RSI exige periodo >0 y niveles finitos con `0 < compra < venta < 100`. Los parámetros Stochastic no afectan RSI ni sus señales. El lector comprueba CopyBuffer, números válidos y EMPTY_VALUE. Se conserva el descarte/relectura de datos faltantes según el modo, las pausas, ATR[1], TP inicial[0], TP posterior[1] y toda la gestión y medición MFE/MAE. Las marcas persistidas RSI se separan de Stochastic y por modo; las claves Stochastic anteriores se conservan.

`INIT` registra el oscilador y sus parámetros efectivos. `SIGNAL` incluye `oscilador=RSI RSI=... shift=0|1 umbral_compra=... umbral_venta=...`; con Stochastic utiliza `oscilador=STOCHASTIC K=...`. Se conservan modo, vela y los campos OHLC/Bollinger/ATR/mercado existentes; no se registra RSI como K ni valores del indicador no utilizado. Las referencias a %K de la explicación de pausas se entienden como RSI cuando está seleccionado. No se añade interfaz gráfica.

Para comparar osciladores, repetir el backtest con idénticos datos, modo, riesgo y gestión, cambiando únicamente `InpOscillator`; mantener los parámetros predeterminados de cada oscilador. No optimizar parámetros.

**Verificación de RSI:** revisión estática de sintaxis y lógica y suite offline ejecutada con fragmentos actuales del EA y respuestas MT5 simuladas. Se comprobaron ambos extremos y sus igualdades, umbrales configurables, shifts 0/1 con valores opuestos, independencia de Stochastic, deduplicación, ATR[1], datos faltantes y etiquetas de logs. Las regresiones existentes de Stochastic, gestión, riesgo, reintentos, reconciliación y MFE/MAE siguen pasando. No se modificaron las funciones de gestión ni medición.

**Compilación de esta versión:** pendiente de ejecutar por el usuario en MetaEditor; el intento local no arrancó por el error de interoperabilidad WSL indicado arriba. **Backtesting MT5:** no ejecutado. Las pruebas C++ auxiliares no acreditan compilación MQL5 ni ejecución en MT5.

### Trazabilidad de CLOSED_BAR y evaluación después de pausas

El registro ampliado conserva una sola línea `SIGNAL` por señal aceptada para su evaluación de ejecución; no añade un registro por tick ni vuelve a consultar indicadores. Usa el mismo `MqlRates` de `CopyRates(...,1,1,...)`, bandas/SMA20[1], %K[1] y ATR[1] que se pasaron a la decisión. Las bandas de shift=0 para el TP inicial no se mezclan con los campos de la señal. Ambos formatos incluyen ahora oscilador, valor, shift y umbrales efectivos.

Formato de la nueva línea, mostrado dividido únicamente para facilitar la lectura (los puntos suspensivos son campos pendientes, no datos históricos):

```text
SIGNAL <fecha_publicacion> idea=<id_previo> modo=CLOSED_BAR
 evaluacion=<fecha_hora> vela=<apertura_vela_senal>
 cierre_nominal=<apertura_vela_senal+300s> segundos_desde_cierre=<segundos>
 direccion=<BUY|SELL> Open=... High=... Low=... Close=...
 LowerBand=... SMA20=... UpperBand=... oscilador=STOCHASTIC K=... shift=1 umbral_compra=10... umbral_venta=90... ATR=...
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

### MFE y MAE monetarios por idea (solo diagnóstico)

En cada tick con una idea activa o en cierre y después de reconciliar transacciones se intenta obtener una muestra coherente del resultado conjunto:

`PnL_idea = realizado_acumulado + flotante_actual_de_las_posiciones_de_la_idea`

- El realizado suma `DEAL_PROFIT + DEAL_SWAP + DEAL_COMMISSION + DEAL_FEE` de los deals de compra/venta vinculados a los identificadores de posición y órdenes de la idea. Mantiene el criterio del `PnL_realizado` de `EXIT`: incluye los costes ya registrados en esos deals, sin estimar comisiones futuras ni agregar cargos históricos independientes del tipo balance/comisión.
- El flotante suma `POSITION_PROFIT + POSITION_SWAP` de las posiciones abiertas de esa idea. Las pendientes, incluido E2 antes de ejecutarse, aportan cero exposición. El swap de un volumen ya cerrado pertenece a sus deals; el swap restante pertenece a las posiciones abiertas. No se suma además otro total de swap histórico.
- El disparador operativo de cierre monetario **no cambia**: sigue usando únicamente el flotante conjunto con swap, sin añadir realizado ni comisiones históricas. MFE/MAE no activan cierres ni modifican señales, entradas, volumen, SL, TP, reintentos o enfriamiento.

Desde la primera ejecución confirmada de E1, los extremos parten de cero: `MFE_USD=max(0, muestras)` y `MAE_USD=min(0, muestras)`. Se conservan al ejecutar E2 y se calculan a partir del resultado conjunto en cada instante; no se suman máximos o mínimos individuales de las entradas. La fecha inicial de ambos extremos es la de la primera ejecución de E1. Solo una mejora estricta cambia la fecha de un extremo; los empates conservan su primera fecha. Las fechas de muestras en curso son las de observación del tick/transacción. Si el resultado final reconciliado fija un extremo que todavía no se había observado, se usa la fecha efectiva del último deal de salida; si ya se había observado ese mismo extremo, se conserva su primera fecha.

**Reconciliación:** antes de actualizar los extremos se comprueba que el volumen ejecutado de las órdenes conocidas esté reflejado en los deals y que, por posición, `entradas - salidas = volumen_abierto`. Se comprueba también que la última actualización de volumen de cada posición esté representada en el historial y se vuelve a leer el portfolio para detectar desapariciones, cambios de volumen/identidad/versión, beneficio o swap durante la lectura. Esto evita sumar un cierre realizado con el flotante anterior de la misma exposición. En netting se comprueba el volumen consolidado; no se infieren dos posiciones por tener dos entradas. No se atribuye a la idea el resultado de posiciones netting mezcladas.

Si faltan datos o la fotografía no es coherente, se conservan los extremos anteriores y se vuelve a intentar en eventos posteriores. No se usa un resultado parcial como cero, no se acumulan dos veces los mismos deals y no se combinan retrospectivamente flotantes antiguos con resultados realizados nuevos. Una muestra que no puede reconciliarse no aporta un extremo estimado. El código de diagnóstico solo lee datos y actualiza sus propios registros; no cambia `history_ok` ni los estados operativos.

Cuando la idea queda sin exposición se copia también su estado MFE/MAE al resumen independiente en cola. El PnL realizado final se incorpora como una última muestra **antes de publicar `EXIT`**, por lo que puede fijar un nuevo MAE o MFE. La identidad, los extremos y el presupuesto de ese resumen no se sustituyen cuando comienza otra idea. El enfriamiento comienza en el mismo punto operativo de antes y no espera a que el resultado contable esté disponible.

El `EXIT` definitivo conserva sus campos anteriores y añade:

```text
MFE_MAE_disponible=<true|false>
MFE_USD=<maximo_no_negativo> MAE_USD=<minimo_no_positivo>
MFE_fecha=<fecha_hora> MAE_fecha=<fecha_hora>
riesgo_presupuestado_USD=<presupuesto_congelado_de_la_idea>
MFE_R=<MFE_USD/presupuesto> MAE_R=<MAE_USD/presupuesto>
duracion_segundos=<ultimo_deal_salida_msc-momento_E1_msc, dividido por 1000>
```

Se publica en la misma línea de `EXIT`, no una línea por tick. El presupuesto se congela con los parámetros de la idea antes del envío de E1; por ejemplo, USD 25,000 al 0.25% dan USD 62.50. `MAE_R` conserva el signo negativo. La duración usa las ejecuciones reales en milisegundos y se muestra en segundos con tres decimales: no incluye esperas posteriores por cancelaciones pendientes o por publicación del resumen. Si E1 fue rechazada y no hubo ejecución, se indica `MFE_MAE_disponible=false`, extremos/R/duración cero y fechas `n/a`; no representa una operación de equilibrio.

**Límites:** son extremos observados en las muestras coherentes de los eventos procesados por el EA. No garantizan capturar toda variación del mercado, el máximo/mínimo entre ticks, eventos no recibidos o muestras cuyo historial todavía era incompleto. El estado vive en memoria: una reinicialización no reconstruye las excursiones anteriores. Durante la limpieza de residuos al iniciar se pueden obtener la hora original de E1 y el resultado desde el historial, pero solo se observan excursiones desde esta instancia y se utiliza su presupuesto configurado; no debe interpretarse como recuperación de todo el recorrido previo ni de un presupuesto histórico desconocido.

El Probador puede liquidar posiciones al terminar el periodo sin dar al EA otra oportunidad de reconciliar y publicar su `EXIT` habitual. En ese caso tampoco se garantiza el resumen final MFE/MAE: revisar el informe/historial del Probador y los `EXIT_PENDING`. `OnDeinit` solo intenta completar resúmenes ya en cola; no fuerza operaciones ni inventa extremos retrospectivos.

**Verificación de este cambio:**

- Ejecutadas las pruebas de `test/`, incluida la nueva regresión de excursiones: MFE=0 en ideas siempre perdedoras; rebote positivo conservado con cierre negativo; E2 sin reinicio; medición conjunta frente a máximos individuales; cierres parciales y 24 permutaciones de cierres simultáneos; realizado final que establece un nuevo MAE; comisiones, fee/swap sin duplicación; datos incompletos y cambios de posiciones durante la lectura; presupuesto/R, fechas, duración y resumen atrasado después de iniciar otra idea. También se comprobó netting con entradas consolidadas y cambios de volumen compensados con historial atrasado.
- Revisión estática por comparación con la versión anterior: señales, riesgo, niveles, TP, enfriamiento, reintentos, protección de propiedad e inicialización conservados. El flujo de `OnTick`, `OpenIdea`, `CloseStep` y `OnTradeTransaction` es idéntico al retirar las llamadas de diagnóstico. Un contrato estático de la suite prohíbe solicitudes de trading, cambios de estado operativo y logs por tick desde las funciones nuevas de medición.
- La suite completa pasa **22 tests** (14 de comportamiento con múltiples escenarios, 4 del arnés y 4 contratos estáticos). Los tests de comportamiento compilan fragmentos actuales con C++ y adaptadores MT5: no son compilación MQL5 ni backtesting real. El intento de invocar MetaEditor volvió a fallar con `WSL ... UtilBindVsockAnyPort ... socket failed 1`. Quedan pendientes compilar esta versión en MetaEditor y comparar su operativa con la anterior en el Probador.

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
4. Mantener los parámetros predeterminados (`InpOscillator=STOCHASTIC`, `InpSignalMode=INTRABAR`) para la primera ejecución; repetir con `CLOSED_BAR` para comparar la variante al cierre. Desactivar optimización; usar modo visual para inspeccionar entradas, niveles y enfriamiento.
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

La suite usa `unittest`: 14 tests de comportamiento con múltiples escenarios internos, 4 comprobaciones del extractor/adaptador y 4 contratos estáticos. Cubre riesgo/lotaje, señales y modos, TP, enfriamiento, reintentos, identidad/PnL de cierres, MFE/MAE conjuntos y trazabilidad tras pausas. Extrae funciones del fuente actual y usa respuestas MT5 simuladas; no depende de snapshots o scripts temporales anteriores. Sin compilador C++17, los tests de comportamiento se marcan como omitidos, no como verificados.

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
