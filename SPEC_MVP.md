# Proyecto: Mean Reversion EA V2 — XAUUSD M5

## 1. Objetivo

Desarrollar un Expert Advisor (EA) en **MQL5** con selector `InpStrategy`: `ORIGINAL` (predeterminado, Bollinger, oscilador seleccionable y ATR) y `BB_REENTRY` (experimental, reingreso a Bollinger sin oscilador, una entrada y SMA20 dinámica).

La estrategia `ATR_DEVIATION_REENTRY=3` amplía el selector sin alterar valores anteriores. La estrategia V6 `BB_WICK_REJECTION=2` se añade sin alterar `ORIGINAL=0` ni `BB_REENTRY=1`; ORIGINAL sigue predeterminada. Las secciones 2–18 describen ORIGINAL. Las secciones 19–24 definen las diferencias expresas de BB_REENTRY; la gestión común se conserva donde corresponda.

El objetivo es obtener un **MVP funcional que pueda ejecutarse en el Probador de Estrategias de MetaTrader 5**, utilizando el modo de ticks reales.

No estamos construyendo un sistema de producción. Queremos validar estadísticamente una estrategia mediante backtesting.

### Restricciones arquitectónicas

* Lenguaje exclusivamente MQL5.
* Arquitectura monolítica.
* Archivo principal: `MeanReversionEA.mq5`.
* Utilizar únicamente las bibliotecas estándar de MQL5.
* Sin Python, APIs, bases de datos ni servicios externos.
* Sin interfaces gráficas.
* Sin optimizaciones prematuras.
* Sin indicadores personalizados.
* Sin filtros adicionales que modifiquen las señales.
* No implementar características que no estén especificadas.

Priorizar simplicidad, exactitud de las reglas y facilidad de depuración.

---

# 2. Indicadores

El EA operará exclusivamente en M5.

### Bollinger Bands

* Periodo: 20.
* Desviaciones: 2.5.
* Shift: 0.
* Precio aplicado: Close.
* Línea central: SMA20.

Utilizar `iBands()`.

Buffers:

* 0: SMA20.
* 1: Banda superior.
* 2: Banda inferior.

### Stochastic

* K Period: 14.
* D Period: 3.
* Slowing: 3.
* Método: SMA.
* Price Field: Low/High.
* Utilizar exclusivamente la línea %K.

Utilizar `iStochastic()`.

Niveles:

* Compra: `%K < 10`.
* Venta: `%K > 90`.

### ATR

* Periodo: 14.
* Temporalidad: M5.

Utilizar `iATR()`.

El ATR utilizado para calcular los niveles de una idea debe permanecer congelado.

---

# 3. Detección de señales — modo INTRABAR predeterminado

Se admiten dos variantes experimentales seleccionadas por `InpSignalMode`: `INTRABAR` (predeterminada, reglas de esta sección) y `CLOSED_BAR` (confirmación al cierre, sección 17). No se presupone rentabilidad de ninguna variante.

En `INTRABAR`, las señales deben evaluarse durante la formación de la vela M5.

**No esperar al cierre para detectar o ejecutar una señal.**

Utilizar los indicadores de la vela actual (`shift = 0`).

## Compra

Se genera una señal de compra cuando:

1. El mínimo de la vela actual toca o supera la banda inferior de Bollinger.

   `Low[0] <= LowerBand[0]`

2. El Stochastic de esa misma vela cumple:

   `%K[0] < 10`

3. No existe ninguna idea activa.

4. No existe un periodo de enfriamiento activo.

5. No se ha procesado previamente esa señal.

Cuando se cumplen las condiciones, intentar ejecutar una idea de compra.

## Venta

Se genera una señal de venta cuando:

1. El máximo de la vela actual toca o supera la banda superior de Bollinger.

   `High[0] >= UpperBand[0]`

2. El Stochastic de esa misma vela cumple:

   `%K[0] > 90`

3. No existe ninguna idea activa.

4. No existe un periodo de enfriamiento activo.

5. No se ha procesado previamente esa señal.

Cuando se cumplen las condiciones, intentar ejecutar una idea de venta.

### Consideraciones

* Evaluar las condiciones en cada tick.
* El máximo/mínimo de la vela puede haberse registrado en un tick anterior.
* El Stochastic debe corresponder a la vela actualmente en formación.
* No exigir que el precio regrese al interior de las bandas.
* No aplicar filtros de tendencia.
* No utilizar ADX, EMA adicionales ni confirmaciones de otras temporalidades.
* No generar entradas duplicadas.

---

# 4. Ejecución de operaciones

Cada idea tendrá un máximo de **dos entradas del mismo lote**.

## E1: entrada inicial

Al detectar una señal válida:

1. Obtener el ATR de la última vela cerrada (`shift = 1`).
2. Congelar ese ATR.
3. Verificar las condiciones de riesgo.
4. Calcular el lote.
5. Ejecutar E1 inmediatamente a mercado.
6. Obtener el precio real de ejecución.

En `INTRABAR`, no esperar al inicio de una nueva vela. En `CLOSED_BAR`, ejecutar en el primer tick disponible de la nueva vela según la sección 17.

## E2: entrada pendiente

Después de ejecutar correctamente E1, colocar una orden pendiente.

| Dirección | E2         |
| --------- | ---------- |
| Compra    | E1 − 1 ATR |
| Venta     | E1 + 1 ATR |

Tipos de órdenes:

* Compra: `Buy Limit`.
* Venta: `Sell Limit`.

La orden E2 debe utilizar exactamente el mismo lote que E1.

No se permite E3.

No reponer E2 si se ejecuta, cancela o elimina.

## Stop Loss

El Stop Loss es común para ambas entradas.

| Dirección | SL         |
| --------- | ---------- |
| Compra    | E1 − 3 ATR |
| Venta     | E1 + 3 ATR |

Consideraciones:

* Utilizar el precio ejecutado de E1 como referencia.
* Congelar el SL para toda la idea.
* E1 y E2 comparten el mismo precio de SL.
* No implementar trailing stop.
* No mover el SL a breakeven.
* No modificar el SL durante la operación.

Si E1 se ejecuta, pero no es posible establecer un SL válido, cerrar la posición y abortar la idea.

Si falla la colocación de E2, cerrar E1, cancelar cualquier orden residual y registrar el error.

---

# 5. Gestión de riesgo

## Riesgo por idea

El riesgo máximo presupuestado será del **0.25% del capital de referencia**.

Permitir configurar el capital de referencia mediante un parámetro de entrada:

`InpRiskBaseUSD = 25000`

Valores habituales:

| Capital | Riesgo 0.25% |
| ------- | ------------ |
| $10,000 | $25.00       |
| $25,000 | $62.50       |
| $50,000 | $125.00      |

Para el MVP, el presupuesto se calcula respecto al capital de referencia configurado, no respecto al balance flotante.

## Cálculo del lote

Tenemos dos entradas:

* E1 arriesga 3 ATR.
* E2 arriesga 2 ATR.

Riesgo total teórico: 5 ATR.

Para XAUUSD, suponiendo un contrato de 100 onzas por lote:

`Lote = RiesgoUSD / (500 × ATR)`

Redondear siempre hacia abajo al paso de volumen permitido.

Ejemplo:

Capital: $25,000.

Riesgo: $62.50.

ATR: 2.00.

Resultado:

`62.50 / (500 × 2) = 0.0625`

Lote ejecutable: `0.06`.

Ambas entradas utilizarán 0.06 lotes.

### Implementación

La fórmula anterior es la referencia matemática.

Sin embargo, utilizar preferentemente `OrderCalcProfit()` y las especificaciones reales del símbolo para calcular el riesgo monetario conjunto de E1 y E2 hasta su SL.

Considerar:

* Volumen mínimo.
* Volumen máximo.
* Incremento de volumen.
* Tamaño del contrato.
* Tick size.
* Tick value.
* Moneda de la cuenta.

El volumen calculado nunca debe redondearse hacia arriba si con ello supera el presupuesto.

El riesgo previsto debe verificarse después de normalizar los precios al tick size.

No incluir comisiones ni deslizamiento en el cálculo inicial del lotaje.

## Filtro ATR

Reglas:

* Si `ATR > 8`: NO OPERAR.
* Si `ATR <= 0`: NO OPERAR.
* Si el lote mínimo supera el presupuesto: NO OPERAR.
* Si el cálculo de riesgo falla: NO OPERAR.

No utilizar una tabla estática de lotaje.

Calcular el volumen directamente a partir del ATR y del presupuesto.

### Referencia

Para una cuenta de 10k y riesgo del 0.25%, un ATR de 6 no permite utilizar 0.01 lotes sin superar el presupuesto.

En ese caso, la idea se descarta aunque ATR sea menor que 8.

---

# 6. Take Profit dinámico

El objetivo es capturar el 90% del recorrido desde la banda exterior hacia la SMA20.

## Compra

`TP = LowerBand + 0.90 × (SMA20 − LowerBand)`

## Venta

`TP = UpperBand − 0.90 × (UpperBand − SMA20)`

## Inicialización

Al abrir E1:

* Calcular el TP utilizando las bandas y SMA20 disponibles de la vela actual.
* Asignarlo a E1.
* Asignar el mismo TP a la pendiente E2.

## Actualización dinámica

Al inicio de cada nueva vela M5:

1. Obtener las bandas y SMA20 de la última vela cerrada.
2. Recalcular el TP.
3. Actualizar el TP de las posiciones abiertas.
4. Actualizar también el TP de E2 si continúa pendiente.

Utilizar `shift = 1` para las actualizaciones.

El TP puede moverse tanto a favor como en contra de la posición.

No implementar trailing TP ni restricciones adicionales sobre su movimiento.

### Consideraciones técnicas

* Normalizar el TP al tick size del símbolo.
* Verificar las restricciones de stops y freeze level del bróker.
* Si el precio ya alcanzó o superó el TP recalculado, cerrar la idea a mercado.
* Si no es posible modificar el TP por restricciones del bróker, registrar el problema y gestionar ese objetivo mediante comprobaciones en cada tick hasta poder actualizarlo o cerrar la idea.
* No modificar el SL al actualizar el TP.
* Evitar solicitudes de modificación cuando el TP calculado no cambió.

---

# 7. Cierre de una idea

Una idea termina cuando se cumple cualquiera de las siguientes condiciones:

### A. Take Profit

El precio alcanza el TP dinámico.

Cerrar las posiciones restantes y cancelar E2 si no se ha ejecutado.

### B. Stop Loss

El precio alcanza el SL común.

Cerrar cualquier posición restante y cancelar las órdenes pendientes.

### C. Límite monetario

La pérdida flotante conjunta de la idea alcanza el presupuesto de riesgo.

Ejemplo:

Capital de referencia: $25,000.

Presupuesto: $62.50.

Cuando:

`PnL_flotante_conjunto <= -62.50`

Cerrar todas las posiciones de la idea y cancelar las órdenes pendientes.

Para este MVP, utilizar el PnL flotante proporcionado por MT5, incluyendo swap cuando corresponda. No agregar un cálculo histórico adicional de comisiones.

### Reglas generales

* No dejar órdenes pendientes huérfanas.
* No dejar posiciones abiertas sin gestión.
* Si una posición se cierra por TP o SL, finalizar la idea completa.
* No cerrar posiciones ajenas al EA.
* No modificar órdenes pertenecientes a otros EAs.
* Utilizar un Magic Number configurable.

El resultado real puede superar la pérdida presupuestada debido a spread, deslizamiento o gaps.

El EA no debe prometer un límite monetario garantizado.

---

# 8. Control de ideas y enfriamiento

Solo se permite una idea activa por símbolo.

Una idea activa incluye:

* E1 abierta.
* E2 pendiente.
* E2 ejecutada.
* Operaciones de cierre o cancelación todavía pendientes de confirmación.

Mientras exista una idea activa, ignorar nuevas señales.

## Enfriamiento

Cuando termina completamente una idea:

1. Identificar la vela M5 durante la cual ocurrió el cierre.
2. Esperar a que termine esa vela.
3. Esperar una vela M5 adicional completa.
4. Habilitar la búsqueda de nuevas señales.

Ejemplo:

* Cierre de idea: 10:32.
* Vela del cierre: 10:30–10:35.
* Vela de enfriamiento: 10:35–10:40.
* Nuevas señales permitidas desde: 10:40.

No reutilizar señales anteriores al fin del enfriamiento.

No permitir que la misma idea se reinicie inmediatamente después de cerrarse.

---

# 9. Arquitectura del EA

Implementar todo en un único archivo MQL5.

Utilizar la clase estándar `CTrade`.

No crear clases, módulos ni abstracciones innecesarias.

Se permite utilizar funciones pequeñas para mantener el código legible.

### Ciclo de vida

`OnInit()`

* Validar los parámetros.
* Crear handles de indicadores.
* Verificar el símbolo y las condiciones del entorno.
* Inicializar el estado del EA.

`OnTick()`

* Detectar nuevas velas.
* Actualizar TP cuando corresponda.
* Supervisar riesgo y condiciones de cierre.
* Gestionar el enfriamiento.
* Evaluar nuevas señales.
* Ejecutar nuevas ideas.

`OnTradeTransaction()`

* Detectar ejecuciones y cierres.
* Identificar cuándo E2 se convierte en posición.
* Mantener coherente el estado de la idea.
* Evitar posiciones y órdenes huérfanas.

`OnDeinit()`

* Liberar los handles de indicadores.

### Estados sugeridos

Utilizar un enum sencillo:

* `WAITING_SIGNAL`
* `ACTIVE_IDEA`
* `CLOSING_IDEA`
* `COOLDOWN`

Evitar una máquina de estados excesivamente compleja.

### Compatibilidad de cuentas

Considerar los modelos de cuenta hedging y netting de MT5.

En hedging, E1 y E2 pueden existir como posiciones independientes.

En netting, las ejecuciones se consolidan en una posición del símbolo.

El EA debe preservar el SL común, el TP y el cálculo de riesgo de la idea en ambos casos.

No asumir que dos entradas equivalen siempre a dos posiciones independientes.

Evitar interferir con posiciones existentes ajenas al EA.

---

# 10. Parámetros configurables

Exponer únicamente los parámetros necesarios:

| Parámetro                      | Default      |
| ------------------------------ | ------------ |
| Estrategia (`InpStrategy`)      | ORIGINAL     |
| Modo de señal (`InpSignalMode`) | INTRABAR     |
| Magic Number                   | 20261104     |
| Capital de referencia          | 25000        |
| Riesgo por idea                | 0.25%        |
| Bollinger Period               | 20           |
| Bollinger Deviation            | 2.5          |
| Oscilador (`InpOscillator`)     | STOCHASTIC   |
| RSI Period (`InpRSIPeriod`)     | 14           |
| RSI Compra (`InpRSIBuyLevel`)   | 30           |
| RSI Venta (`InpRSISellLevel`)   | 70           |
| Stochastic K                   | 14           |
| Stochastic D                   | 3            |
| Stochastic Slowing             | 3            |
| ATR Period                     | 14           |
| ATR Máximo                     | 8            |
| TP Factor                      | 0.90         |
| Desviación máxima de ejecución | Configurable |
| Logs detallados                | true         |

Mantener fijas las reglas de dos entradas y sus distancias:

* E2: 1 ATR.
* SL: 3 ATR.

No agregar parámetros de optimización para características inexistentes.

---

# 11. Registros de depuración

Implementar registros claros mediante `Print()` o `PrintFormat()`.

Registrar los siguientes eventos:

**SIGNAL**

* Modo de señal (`INTRABAR` o `CLOSED_BAR`).
* Fecha/hora de apertura de la vela evaluada.
* Fecha/hora del evento.
* Dirección.
* Precio.
* Bollinger.
* Stochastic.
* ATR.

**ENTRY**

* ID de idea.
* E1 ejecutada.
* E2 pendiente.
* Lote.
* SL.
* TP.
* Riesgo monetario previsto.

**TP_UPDATE**

* TP anterior.
* TP nuevo.
* Fecha/hora.
* Resultado de la modificación.

**EXIT**

* Motivo del cierre.
* Fecha/hora.
* Beneficio/pérdida.
* Entradas ejecutadas.

**REJECTED**

* ATR superior al máximo.
* Lotaje insuficiente.
* Riesgo superior al presupuesto.
* Orden rechazada.
* Indicadores no disponibles.
* Stops inválidos.

Los logs deben permitir reconstruir el ciclo completo de una idea.

Evitar imprimir información repetitiva en cada tick.

---

# 12. Validación

Antes de considerar terminado el MVP, revisar los siguientes escenarios.

### Señales

1. Compra con Low <= banda inferior y %K < 10.
2. Venta con High >= banda superior y %K > 90.
3. Señal intrabar sin esperar el cierre.
4. No repetir entradas en una misma señal.
5. No iniciar ideas mientras exista otra activa.

### Ejecución

6. E1 abre correctamente.
7. E2 se coloca a 1 ATR.
8. Ambas entradas utilizan el mismo lote.
9. SL permanece fijo a 3 ATR desde E1.
10. No existe E3.

### Riesgo

11. ATR > 8 rechaza la idea.
12. ATR = 8 permite continuar con la validación del lotaje.
13. Lote mínimo demasiado grande rechaza la idea.
14. Riesgo conjunto previsto no supera el presupuesto.
15. Cierre monetario cuando se alcanza el límite.

### Take Profit

16. TP inicial calculado correctamente.
17. TP actualizado con cada nueva vela.
18. TP idéntico para las posiciones de la misma idea.
19. TP actualizado para E2 pendiente.
20. Cierre correcto cuando el objetivo ya fue alcanzado.

### Ciclo de vida

21. Cancelación de E2 al finalizar la idea.
22. Cierre de posiciones restantes.
23. Enfriamiento de una vela completa.
24. Nueva señal permitida únicamente después del enfriamiento.
25. Sin órdenes ni posiciones huérfanas.

---

# 13. Entregables

Generar:

### Archivo principal

`MeanReversionEA.mq5`

Debe contener la implementación completa del EA.

### Documentación

`README.md`

Incluir:

* Descripción del EA.
* Requisitos.
* Cómo abrirlo en MetaEditor.
* Cómo compilarlo.
* Cómo configurarlo.
* Cómo ejecutar un backtest en MT5.
* Parámetros disponibles.
* Ejemplo de cálculo de riesgo.
* Limitaciones conocidas.

### Pruebas

Realizar una revisión de los escenarios anteriores.

Si MetaEditor y el compilador MQL5 están disponibles:

* Compilar.
* Corregir errores.
* Reportar advertencias.
* Confirmar el resultado.

Si no están disponibles:

* Realizar revisión estática.
* No afirmar que compiló.
* Documentar los pasos necesarios para verificarlo en MetaEditor.

---

# 14. Criterios de aceptación

El MVP estará completo cuando:

1. El EA pueda compilarse en MetaTrader 5.
2. Detecte señales durante la formación de las velas en `INTRABAR`, y confirme señales de la vela cerrada una sola vez por nueva vela en `CLOSED_BAR`.
3. Abra E1 y coloque E2.
4. Calcule el lotaje según el riesgo del 0.25%.
5. Respete el filtro ATR > 8.
6. Establezca el SL común.
7. Actualice el TP dinámicamente.
8. Controle el presupuesto monetario por idea.
9. Cierre correctamente posiciones y pendientes.
10. Respete el enfriamiento entre ideas.
11. Permita ejecutar un backtest histórico sin dependencias externas.

**Importante:** no se exige que la estrategia sea rentable.

Buscamos comprobar que el sistema ejecuta fielmente las reglas del Playbook V2.

---

# 15. Instrucciones finales

Implementa el MVP completo.

No agregues nuevas estrategias, indicadores ni reglas de trading.

No utilices una arquitectura distribuida.

No introduzcas infraestructura externa.

No sustituyas reglas del Playbook por criterios subjetivos.

Si encuentras dificultades técnicas propias de MQL5, resuélvelas priorizando:

1. Seguridad de ejecución.
2. Respeto al riesgo presupuestado.
3. Fidelidad al Playbook.
4. Simplicidad del código.
5. Compatibilidad con el Probador de Estrategias.

Documenta cualquier desviación inevitable.

Al finalizar, entrega:

* Resumen de implementación.
* Archivos generados.
* Resultado de compilación, si se pudo ejecutar.
* Escenarios validados.
* Limitaciones identificadas.

No declares el proyecto terminado si existen errores conocidos que impidan ejecutar correctamente las operaciones.

---

# 16. Aclaraciones acordadas para el MVP

Estas decisiones complementan las reglas anteriores:

1. **Moneda:** admitir únicamente cuentas denominadas en USD. Rechazar la inicialización en otras monedas; no convertir `InpRiskBaseUSD`.
2. **Netting:** exigir uso exclusivo del símbolo por el EA. Bloquear nuevas ideas si hay posiciones u órdenes ajenas del símbolo. Detectar la mezcla mediante el historial de la posición, no solo su Magic actual. Ante intervención ajena que mezcle una posición, bloquear entradas, cancelar las pendientes propias y reconciliar/reintentar sus cancelaciones. No cerrar ni modificar automáticamente la posición mezclada. Registrar que requiere intervención manual y documentar esta limitación. No se puede garantizar exclusividad frente a operaciones externas concurrentes.
3. **Reinicios:** limitar toda limpieza y reconstrucción al símbolo y Magic Number correspondientes. Si hay residuos propios, entrar en cierre, cancelar pendientes y cerrar posiciones propias, respetando la protección de posiciones netting mezcladas. No reconstruir una idea activa. Aplicar enfriamiento después de confirmar la limpieza. Sin residuos, reconstruir el enfriamiento desde cierres/cancelaciones propios recientes del historial.
4. **Señales INTRABAR:** identificar cada señal por vela M5 y dirección. Consumirla cuando se evalúa con datos completos, incluso si falla riesgo o ejecución. No reintentar esa dirección en la misma vela. La falta de datos de indicadores no consume la señal. Reconciliar cualquier ejecución incierta antes de permitir otra idea.
5. **Riesgo real:** después de E1 y antes de E2, recalcular E2 y SL desde el precio real ejecutado, normalizar al tick size y verificar el riesgo conjunto con el volumen real. Si excede el presupuesto o falla el cálculo, cerrar E1 y abortar. No reducir parcialmente E1 ni desplazar el SL para acomodar riesgo.
6. **Fallos de cierre/cancelación:** conservar `CLOSING_IDEA`, reconciliar en ticks y transacciones y reintentar acciones necesarias sin duplicar solicitudes todavía pendientes de respuesta. No abandonar tras un máximo de intentos. Si E2 se ejecuta durante el cierre, cerrar también su exposición propia. Iniciar enfriamiento únicamente al confirmar ausencia de posiciones, órdenes y solicitudes propias pendientes. En posición mezclada solo cancelar pendientes propias y requerir intervención manual.
7. **Ejecución parcial:** preferir ejecución completa cuando esté disponible. Si E1 o E2 se ejecutan parcialmente, cancelar remanentes y cerrar la idea, sin completar entradas con órdenes adicionales.
8. **TP inicial:** aplicar desde E1 el mismo objetivo lógico y gestión por tick de las actualizaciones. Si ya se alcanzó, cerrar sin colocar E2. Si restricciones del bróker impiden asignarlo, supervisarlo por tick y reintentar su asignación, manteniendo obligatorio un SL válido.


---

# 17. Variantes experimentales de señal

El parámetro enum `InpSignalMode`, con valores `INTRABAR` (predeterminado) y `CLOSED_BAR`. Las diferencias de esta sección se limitan a la confirmación y oportunidad de evaluación de la señal. Las reglas originales intrabar se conservan en la sección 3. Las instrucciones anteriores de no esperar al cierre/no exigir regreso dentro de bandas corresponden a `INTRABAR`; en `CLOSED_BAR` aplican expresamente las condiciones siguientes.

## INTRABAR

- Evaluar en cada tick Low/High, Bollinger y %K de `shift=0`, como hasta ahora.
- No exigir Close dentro de bandas.
- Congelar ATR de `shift=1`; TP inicial de `shift=0` y actualizaciones posteriores de `shift=1`.
- Conservar la deduplicación por vela actual y dirección y la posibilidad de volver a leer indicadores faltantes en otro tick de esa vela si la señal no se consumió.

## CLOSED_BAR

Evaluar una sola vez al detectar una nueva vela M5. Todas las condiciones de señal deben proceder de la misma vela recién cerrada (`shift=1`):

**Compra:**

- `Low[1] <= LowerBand[1]`.
- `Close[1] > LowerBand[1]` y `Close[1] < UpperBand[1]`.
- `%K[1] < 10`.

**Venta:**

- `High[1] >= UpperBand[1]`.
- `Close[1] > LowerBand[1]` y `Close[1] < UpperBand[1]`.
- `%K[1] > 90`.

No conservar condiciones intrabar de Stochastic. Los límites de Close y %K son estrictos; el toque de banda admite igualdad.

### Ejecución y descarte

- Ejecutar E1 a mercado en el primer tick disponible de la nueva vela, tras validar señal y riesgo.
- Congelar `ATR[1]` de la vela de señal. El TP inicial sigue usando bandas y SMA20 de `shift=0`; sus actualizaciones posteriores siguen usando `shift=1`.
- Identificar la señal por fecha/hora de apertura de la vela cerrada y dirección. Mantener registros de deduplicación separados por modo.
- Registrar cada oportunidad de nueva vela antes de cualquier salida por idea activa, cierre en curso, enfriamiento o protección de exposición ajena. No recuperar una oportunidad omitida en ticks posteriores ni recorrer velas históricas pendientes.
- Al adjuntar/reiniciar, tomar la vela M5 actual como referencia sin procesar el cierre anterior. Esperar la siguiente nueva vela. Si no hubo ticks durante varias velas, evaluar únicamente `shift=1` de la nueva vela disponible.
- Si faltan datos al detectar la nueva vela, incluidas las bandas del TP inicial, registrar y descartar la oportunidad; no ejecutar esa señal tarde cuando los datos aparezcan.
- Si una nueva vela comienza cuando el enfriamiento ya venció, se puede evaluar su vela recién cerrada. Si la oportunidad ocurrió con enfriamiento todavía activo, descartarla aunque venza después dentro de esa misma vela.

### Reglas compartidas y logs

Conservar Stochastic 14,3,3 predeterminado, ambas direcciones, dos entradas del mismo lote, E2 a 1 ATR y SL común a 3 ATR desde E1 ejecutada, riesgo predeterminado del 0.25%, filtro ATR, cálculo del volumen, TP dinámico, cierre monetario, enfriamiento y protección de operaciones ajenas. Conservar las correcciones técnicas de reintentos y reconciliación del PnL, sin cambiar la arquitectura monolítica.

En cada log `SIGNAL` incluir `modo` y `vela` (fecha/hora de apertura de la vela evaluada), además de los datos existentes. En `CLOSED_BAR`, los valores Bollinger/%K del log corresponden a `shift=1`, aunque el TP inicial se calcule aparte con `shift=0`.

### Validación específica

Comprobar compras/ventas válidas, cierre dentro/fuera/en el límite de las bandas, igualdad y recuperación de los umbrales de Stochastic, rechazo si no existe toque de banda, ausencia de duplicados, ausencia de señales al iniciar/reiniciar y de entradas tardías tras datos faltantes, idea activa o enfriamiento. Verificar que se mantienen ATR[1], TP inicial[0] y actualizaciones TP[1]. Comparar `INTRABAR` con su comportamiento anterior, incluidos señales fuera de bandas y relectura de datos faltantes en la misma vela. Distinguir revisión estática, simulaciones auxiliares, compilación MQL5 y backtesting MT5.


---

# 18. Oscilador experimental RSI

`InpOscillator` selecciona `STOCHASTIC` (predeterminado, comportamiento anterior) o `RSI` en el mismo `MeanReversionEA.mq5`. RSI es una hipótesis experimental sin rentabilidad demostrada. Esta sección amplía las referencias a Stochastic/%K de las secciones anteriores: cuando se selecciona RSI, sustituir únicamente el extremo del oscilador; todas las condiciones Bollinger y la gestión permanecen iguales.

- `InpRSIPeriod=14`, entero mayor que cero.
- `InpRSIBuyLevel=30`, `InpRSISellLevel=70`; valores finitos con `0 < compra < venta < 100`.
- Crear únicamente el handle seleccionado: `iRSI(_Symbol, PERIOD_M5, InpRSIPeriod, PRICE_CLOSE)` o el `iStochastic` original. Validar solo los parámetros del oscilador seleccionado. Liberar el handle en `OnDeinit`.
- Compra RSI: valor estrictamente menor que `InpRSIBuyLevel`; venta RSI: estrictamente mayor que `InpRSISellLevel`. Igualdad no genera el extremo correspondiente. No exigir cruces, divergencias, pendientes ni confirmaciones adicionales.
- `INTRABAR`: RSI[0] sustituye a %K[0], con toque de banda y demás condiciones originales.
- `CLOSED_BAR`: RSI[1] sustituye a %K[1], con toque y cierre estrictamente dentro de ambas bandas en esa misma vela cerrada. Evaluar y ejecutar al detectar nueva vela; conservar deduplicación, descarte por datos faltantes, pausas y oportunidades omitidas.
- ATR congelado siempre [1]; TP inicial [0] y actualizaciones [1]. Mantener dos entradas del mismo lote, E2, SL, volumen/riesgo, cierre monetario, enfriamiento, propiedad/netting, reintentos, reconciliación, EXIT_PENDING y MFE/MAE.
- Comprobar el resultado de `CopyBuffer` y rechazar números inválidos/EMPTY_VALUE. Datos no disponibles no generan operaciones; INTRABAR permite relectura y CLOSED_BAR descarta la oportunidad.
- Conservar las claves de deduplicación de Stochastic; separar RSI con un sufijo adicional, manteniendo separación por modo y dirección.
- `INIT`: registrar oscilador y parámetros efectivos. `SIGNAL`: registrar `oscilador`, valor con etiqueta `K` o `RSI` según corresponda, `shift`, umbrales efectivos, modo y vela; conservar OHLC, Bollinger, ATR y mercado existentes. No inventar datos del oscilador no utilizado. No añadir interfaz ni gráficos auxiliares.

Para probar RSI 14, 30/70 al cierre: `InpOscillator=RSI`, `InpRSIPeriod=14`, `InpRSIBuyLevel=30`, `InpRSISellLevel=70`, `InpSignalMode=CLOSED_BAR`. Comparar con STOCHASTIC usando idénticos datos, modo y demás parámetros, sin optimización.

Validar compras <30, ventas >70, ausencia de extremo en igualdad, shifts por modo, independencia de Stochastic y ausencia de operaciones sin datos. Ejecutar las regresiones de gestión y MFE/MAE; distinguir pruebas auxiliares, revisión estática, compilación MQL5 y backtesting MT5.


---

# 19. Variante experimental BB_REENTRY

`InpStrategy=ORIGINAL` conserva íntegramente las variantes Stochastic/RSI e INTRABAR/CLOSED_BAR. `InpStrategy=BB_REENTRY` selecciona las siguientes reglas en el mismo archivo monolítico. Es una hipótesis experimental sin rentabilidad demostrada, sin criterios discrecionales ni optimización de parámetros.

## Indicadores y parámetros efectivos

- M5; `iBands` con periodo **20**, desviación **2.5**, shift 0 y **PRICE_CLOSE**. SMA20 procede exclusivamente de su buffer central 0; superior 1 e inferior 2.
- `iATR` con periodo **14**, y filtro **0 < ATR <= 8**.
- No crear Stochastic ni RSI. Crear/verificar/liberar Bollinger y ATR, además de MACD o ADX únicamente al habilitar sus filtros opcionales de las secciones 21–22; comprobar CopyBuffer y números válidos/EMPTY_VALUE.
- En BB_REENTRY no intervienen ni se validan `InpOscillator`, los parámetros RSI/Stochastic, `InpSignalMode`, `InpTPFactor`, `InpBollingerPeriod`, `InpBollingerDeviation`, `InpATRPeriod` o `InpATRMax`: se usan los valores fijos anteriores. ORIGINAL mantiene sus entradas y validaciones anteriores.
- `InpReentrySLATR=3.0`: multiplicador del SL exclusivo de BB_REENTRY, finito y estrictamente positivo. ORIGINAL lo ignora y conserva SL a 3 ATR. Comparar manualmente 3.0 contra 2.0 manteniendo el mismo riesgo.
- Siguen aplicando Magic Number, capital de referencia, riesgo porcentual, desviación de ejecución y logs.

## Preparación y confirmación

Estados: `NONE`, `WAIT_BUY_REENTRY`, `WAIT_SELL_REENTRY`. Evaluar una sola vez por nueva vela, exclusivamente la recién cerrada [1] y sus propias bandas [1].

- Close < banda inferior: preparar compra; Close > banda superior: preparar venta, sin entrar todavía.
- Cierres exteriores sucesivos del mismo lado conservan la preparación y la fecha de la primera vela exterior. Un exterior opuesto sustituye dirección y fecha.
- Una vela posterior que cierre estrictamente entre ambas bandas confirma la dirección preparada. No exigir nuevo toque de banda; las mechas por sí solas no preparan.
- Close exactamente sobre cualquiera de las bandas no prepara ni confirma; conserva la preparación. No hay vencimiento por número de velas.
- Al confirmar, consumir la preparación incluso si falla persistencia, riesgo o ejecución. Deduplicar por vela/dirección con claves separadas de ORIGINAL.
- Preparar/confirmar solamente sin idea activa, cierre o solicitud incierta y con enfriamiento terminado; conservar protección de exposición ajena. Limpiar al iniciar idea y al iniciar enfriamiento; no acumular preparaciones en esos estados ni bajo bloqueo de propiedad.
- Al iniciar/reiniciar: NONE, sin reconstrucción histórica; esperar una nueva vela.
- Exigir continuidad por horas de apertura: `vela_cerrada.time + 300 == nueva_vela.time`, con la nueva vela correspondiente al tiempo M5 actual. Permitir primer tick unos segundos tarde. Si no hay continuidad, limpiar y omitir esa evaluación; una barra antigua anterior a una pausa no puede preparar ni confirmar al reabrir.
- Si se saltaron oportunidades M5 entre ticks, limpiar la secuencia anterior. La última vela puede iniciar una preparación nueva solo si es contigua a la nueva vela actual; nunca recuperar las omitidas.
- Datos de serie/indicadores ausentes al detectar nueva vela: registrar, limpiar y descartar. No reintentar esa evaluación posteriormente.

## Ejecución, riesgo y salidas

- E1 a mercado en el primer tick disponible tras confirmar y validar. Una sola entrada; sin E2/E3, promedios ni reposiciones.
- Congelar ATR[1] de confirmación. SL fijo desde la ejecución real: compra E1 − InpReentrySLATR × ATR; venta E1 + InpReentrySLATR × ATR. Sin trailing ni breakeven.
- Calcular lote mediante OrderCalcProfit para **una entrada hasta SL a InpReentrySLATR × ATR**, normalizando precios al tick y volumen hacia abajo. Con USD 25,000 y 0.25%, presupuesto USD 62.50. Con contrato de 100 onzas y ATR 2: referencia `62.50 / (300 * 2) = 0.104166…`, lote 0.10 con paso 0.01 y riesgo USD 60. Con multiplicador 2.0 y los mismos datos, el lote de referencia es 0.15 y el riesgo USD 60. La implementación usa las especificaciones reales, no esta fórmula fija. El mismo multiplicador interviene en Levels tanto antes de abrir para calcular volumen como después para fijar SL desde la ejecución real.
- Rechazar ATR <=0 o >8, lote mínimo por encima del presupuesto o fallo de cálculo. Verificar riesgo normalizado y nuevamente con precio y volumen reales. Si excede presupuesto o falla, abortar y cerrar hasta confirmación. No reducir volumen ni desplazar SL. SL válido obligatorio; si no puede establecerse tras E1, cerrar con gestión persistente.
- TP inicial = SMA20[1] de confirmación normalizada al tick; no usar bandas [0] ni factor 0.90.
- En cada nueva vela actualizar a SMA20[1], permitiendo ambos sentidos, sin alterar SL. Compra cierra si Bid >= objetivo; venta si Ask <= objetivo. Si ya está alcanzado al entrar o actualizar, iniciar cierre a mercado.
- Usar objetivo lógico por tick si stops/freeze impiden TP de servidor. Conservar reintentos controlados y evitar modificaciones si el TP de servidor ya coincide con el normalizado; un TP pendiente de sincronizar puede reintentarse. Si faltan datos durante una actualización de gestión, conservar el objetivo anterior y reintentar su lectura, como en la gestión común; esto no recupera señales descartadas.
- Conservar cierre monetario con PnL flotante + swap, criterio actual de costes, enfriamiento (fin de vela de cierre + otra vela completa), propiedad/netting, limpieza de residuos, reconciliación de deals, EXIT_PENDING, solicitudes inciertas y MFE/MAE conjuntos. Las comisiones y el deslizamiento no se presupuestan al calcular el lote inicial; el resumen definitivo mantiene su reconciliación de costes. Gaps/deslizamiento pueden superar el presupuesto; no garantizar pérdida máxima.

## Logs y validación

INIT incluye estrategia y parámetros efectivos, incluido `SL_ATR` para BB_REENTRY. PREPARATION incluye dirección, vela exterior, cierre y bandas; PREPARATION_CLEAR incluye dirección, vela y motivo (confirmación, sustitución, pausas, datos o bloqueo). SIGNAL incluye vela exterior inicial, vela de reingreso, dirección, cierre, bandas, SMA20, ATR y shift=1. ENTRY registra ejecución real, lote, SL, TP, riesgo y `SL_ATR`; conservar TP_UPDATE, rechazos, cierres definitivos y MFE/MAE, sin repetición por tick.

Validar: mecha sin preparación; exterior sin entrada; primer cierre posterior interior; exteriores repetidos; sustitución opuesta; igualdad; pausas; bloqueo por actividad/enfriamiento; una sola entrada y ninguna E2; lote para multiplicadores 3.0/2.0 dentro del mismo presupuesto; TP inicial y posterior SMA20[1]; SL fijo; MFE/MAE y reconciliación; regresión de ORIGINAL. Distinguir revisión estática, arneses auxiliares, compilación MQL5 y backtesting MT5.


---

# 20. Protección experimental de cierre semanal de BB_REENTRY

Entradas nuevas:

| Parámetro | Predeterminado | Alcance |
| --- | --- | --- |
| `InpReentryWeekendGuard` | false | Activar solamente en BB_REENTRY |
| `InpWeekendEntryBlockMinutes` | 60 | Margen previo para bloquear entradas |
| `InpWeekendCloseMinutes` | 30 | Margen previo para solicitar cierre |

Validar `EntryBlockMinutes >= CloseMinutes > 0` solo con BB_REENTRY y protección habilitada. ORIGINAL ignora estas entradas. Desactivada conserva íntegramente el comportamiento anterior y no consulta sesiones. No modifica señal, lote, riesgo, SL configurable, ATR congelado, TP SMA20, enfriamiento ni propiedad.

## Horario del bróker

Consultar `SymbolInfoSessionTrade` para los siete días, usando el símbolo y hora del servidor (`TimeCurrent`), sin hora local, UTC fijo ni cierre de viernes inventado. Los valores devueltos se interpretan por su hora, ignorando su fecha. Unir sesiones solapadas/contiguas y repetir el patrón para resolver el límite entre semanas. Manejar sesiones múltiples/desordenadas, final 00:00 y cruce de medianoche; una sesión válida 00:00–00:00 representa el día completo. Extremos iguales fuera de medianoche son ambiguos y se rechazan.

Criterio conservador para identificar un descanso semanal: exigir **una única interrupción superior a 24 horas** entre sesiones unidas del patrón semanal. Las pausas de hasta 24 horas no activan esta protección. Cero interrupciones extensas (por ejemplo 24/7), más de una, ausencia de sesiones, horas ambiguas, error de consulta o enumeración incompleta implican horario no válido. No elegir la mayor interrupción entre varias ni sustituir por una hora fija. El final de la última sesión antes de esa interrupción es el cierre y el comienzo de la siguiente es la reapertura.

Consultar al iniciar y como máximo una vez por minuto de tiempo de servidor para detectar cambios; comprobar límites y estado en cada tick. `false` sin error o con ERR_MARKET_SESSION_INDEX termina la enumeración de un día; otros errores invalidan el horario. Un límite defensivo de 128 sesiones por día sin terminador se trata como información incompleta, sin operar con una lista truncada.

**Limitaciones:** la API describe un patrón semanal, no un calendario completo de festivos, horarios históricos o cierres extraordinarios. No permite acreditar que los datos recibidos del bróker estén completos o que se respeten en una fecha determinada. Si no satisface el criterio, registrar WEEKEND_SCHEDULE_ERROR y bloquear nuevas entradas, limpiar preparación y mantener la gestión normal de exposición existente, sin inventar un cierre ni forzar salidas con horario desconocido. Reintentar la lectura; al recuperarla aplicar los límites actuales. Para un horario excepcional que no cumpla el criterio, informar antes de proponer otro criterio.

## Bloqueo, cierre y reapertura

- A partir de `cierre - EntryBlockMinutes * 60`, inclusive, bloquear entradas, limpiar preparación y descartar todas las oportunidades durante el bloqueo. Mantenerlo durante todo el descanso semanal.
- A partir de `cierre - CloseMinutes * 60`, inclusive, iniciar CLOSING_IDEA de la idea activa con motivo **WEEKEND_GUARD**, conservar el estado y los reintentos existentes hasta confirmar ausencia de exposición/solicitudes. En inicialización dentro de esta ventana, la limpieza de residuos propios recibe ese motivo.
- Respetar posiciones ajenas, netting mezclado y solicitudes inciertas; no añadir pendientes. Mantener reconciliación de historial y transacciones, EXIT_PENDING, PnL definitivo y MFE/MAE. Cerrar por la ruta común y aplicar el enfriamiento habitual solo al confirmar finalización.
- Mientras persista exposición en un cierre WEEKEND_GUARD, dar prioridad al intento de cierre y después supervisar PnL flotante + swap, SL y TP lógico; conservar actualizaciones SMA20[1] y sincronización TP con las restricciones y reintentos comunes. No sustituir el motivo de cierre ya iniciado ni alterar SL. La gestión normal continúa aunque después falten sesiones.
- Al alcanzar el cierre previsto, registrar una vez WEEKEND_EXPOSURE si sigue habiendo posiciones propias o mezcladas. Si el primer evento posterior llega tras la reapertura, registrar el incumplimiento del cierre previamente conocido y solicitar WEEKEND_GUARD de cualquier idea aún activa.
- Liberar el bloqueo al comienzo de la siguiente sesión semanal, limpiar preparación y omitir la oportunidad de vela anterior al primer evento de desbloqueo. Conservar continuidad M5 y deduplicación; no recuperar señales anteriores al descanso. Un cierre pendiente conserva CLOSING_IDEA antes de admitir nuevas ideas.
- Aplicar el horario y los indicadores de bloqueo/cierre durante OnInit, sin reconstrucción histórica de señales. No se agrega otro filtro horario ni bloqueo por pausas diarias.

No garantiza quedar sin exposición si no llegan ticks/eventos, si se adelanta el cierre o si el servidor rechaza las solicitudes. No se agregan temporizadores que simulen ticks. La consulta de sesiones puede tardar hasta un minuto en detectar un cambio del patrón; los límites del horario ya conocido se aplican en el primer tick disponible, sin esperar el próximo refresco.

## Logs y verificación

INIT registra activación y márgenes. WEEKEND_SCHEDULE registra cierre y reapertura calculados en hora del servidor y sus cambios; WEEKEND_SCHEDULE_ERROR registra problemas y bloqueo conservador; WEEKEND_BLOCK_START/END registran transiciones y limpieza. EXIT_REQUEST WEEKEND_GUARD registra el comienzo del cierre y se conservan los errores controlados de CloseStep. WEEKEND_EXPOSURE registra el incumplimiento del cierre. Evitar logs idénticos por tick: publicar cambios/problemas nuevos y una advertencia por cierre con exposición.

Verificar protección desactivada y ORIGINAL sin cambios; pausas diarias; límites exactos de bloqueo/cierre; limpieza y ausencia de señales acumuladas; reintentos tras rechazo; reapertura sin señales antiguas; medianoche/sesiones múltiples/semanas; propiedad/netting; PnL, MFE/MAE y enfriamiento; horario ausente/ambiguo con bloqueo conservador y gestión normal existente. Distinguir revisión estática, pruebas offline con sesiones simuladas, compilación MQL5 y backtesting. Validar en MT5 con las sesiones reales del símbolo antes de interpretar resultados.


# 21. Confirmación MACD opcional de BB_REENTRY

Hipótesis experimental sin rentabilidad demostrada. `InpReentryMACDConfirm=false` conserva el comportamiento anterior. `InpMACDFast=12`, `InpMACDSlow=26`, `InpMACDSignal=9`. Solo validar estos periodos si BB_REENTRY y confirmación habilitada: todos positivos y Fast < Slow. ORIGINAL los ignora. Crear el handle únicamente en esa combinación con `iMACD(_Symbol, PERIOD_M5, Fast, Slow, Signal, PRICE_CLOSE)`, comprobar INVALID_HANDLE y liberarlo en OnDeinit.

Definir H[shift] = MAIN_LINE[shift] − SIGNAL_LINE[shift], buffers 0 y 1 respectivamente; H no equivale a las barras MAIN_LINE mostradas por MT5. Leer mediante el lector común Value/CopyBuffer, validando resultado, números y EMPTY_VALUE, exclusivamente shifts 1 y 2.

Conservar la preparación por cierre exterior. En el primer cierre posterior estrictamente interior, consumir la preparación y comprobar:

- Compra: H[1] < 0 y H[1] > H[2].
- Venta: H[1] > 0 y H[1] < H[2].

Todas las desigualdades son estrictas. No exigir cruces, divergencias ni otra pendiente de señal. Si confirma, seguir validaciones existentes y ejecutar en el primer tick disponible de la nueva vela. Si no confirma o faltan datos MACD, descartar definitivamente esa preparación, registrar y exigir un nuevo cierre exterior; no esperar otra vela interior ni recuperar datos tarde. La igualdad de Close con las bandas sigue conservando la preparación porque todavía no hubo reingreso estrictamente interior.

INIT registra activación y periodos efectivos (si está apagado, solo false). MACD_CONFIRM registra dirección, vela exterior, vela de reingreso, MAIN1, SIGNAL1, H1, H2 y resultado CONFIRMADA/DESCARTADA, una vez por oportunidad. Si no puede obtenerse el snapshot completo, marcar los cuatro campos n/a y datos no disponibles, sin valores ficticios. Conservar los logs de señal y gestión existentes.

Sin cambios de entrada única, ATR[1] de reingreso, SL configurable, TP SMA20, lotaje/riesgo/cierre monetario, protección semanal y márgenes, enfriamiento, continuidad, propiedad, reconciliación, reintentos y MFE/MAE. Probar con `InpReentrySLATR=2.0` sin alterar su valor predeterminado 3.0. No optimizar parámetros.

Validar ambas direcciones, H[1]=0, H[1]=H[2], rechazo y datos incompletos que consumen preparación sin ejecución tardía, buffers/shifts correctos, creación condicional y regresión desactivada/ORIGINAL. Las simulaciones auxiliares no equivalen a compilación ni backtesting MT5.


# 22. Filtro ADX experimental de BB_REENTRY

Hipótesis experimental sin ventaja demostrada: ADX bajo no garantiza lateralidad. Selector enum `InpReentryADXMode` de tipo `ReentryADXMode`, exclusivamente BB_REENTRY, sin parámetros de periodo/umbral optimizables adicionales:

| Modo | Condición |
| --- | --- |
| ADX_OFF (predeterminado) | Sin filtro ni lecturas ADX; comportamiento anterior |
| ADX_BELOW_25 | ADX[1] < 25 |
| ADX_BELOW_20 | ADX[1] < 20 |
| ADX_BELOW_25_FALLING | ADX[1] < 25 y ADX[1] < ADX[2] |

Crear `iADX(_Symbol, PERIOD_M5, 14)` únicamente con BB_REENTRY y modo activo; usar solo buffer 0 MAIN_LINE, sin +DI/-DI ni iADXWilder. Validar modo y handle, leer con Value/CopyBuffer comprobando cantidad, números válidos y EMPTY_VALUE; liberar en OnDeinit. ORIGINAL ignora el selector y no crea ADX.

Conservar preparación exterior. Evaluar únicamente en el primer cierre posterior estrictamente dentro de ambas bandas, después de consumir la preparación. Solo shift=1, y shift=2 únicamente en FALLING. Igualdad con 20/25 no cumple el umbral correspondiente; igualdad ADX[1]=ADX[2] no cumple descenso. Mismas reglas para compra/venta. Un rechazo o datos ADX ausentes descartan esa preparación y exigen otra exterior; nunca esperar una vela interior adicional ni ejecutar tarde. ADX no interviene en posiciones ya abiertas.

Mantener MACD sin cambiar su selector ni fórmula: si ambos filtros están activos, evaluarlos en el mismo reingreso y exigir AND. Esa combinación no forma parte de esta prueba. ADX_OFF no consulta ADX ni añade valores ficticios; conserva el comportamiento MACD anterior.

INIT registra nombre efectivo de modo ADX, periodo fijo 14 y estado MACD. ADX_FILTER registra una vez por reingreso dirección, vela, modo, ADX1, ADX2 solo en FALLING, resultado y motivo. Datos faltantes se marcan n/a, sin inventar valores. Con OFF solo se registra configuración, sin snapshot ADX por reingreso.

Configuración de comparación manual, sin optimización automática: BB_REENTRY; MACD false; SL 2 ATR; protección semanal true con bloqueo 60 y cierre 30 minutos; capital USD 25000 y riesgo 0.25%; resto sin cambios. Repetir únicamente cambiando entre los cuatro modos. No cambiar valor predeterminado del SL ni del guard por esta prueba.

Se conservan entrada única sin E2, ATR congelado de reingreso, SL/lotaje, SMA20 dinámica, presupuesto/cierre monetario, enfriamiento, guard semanal, continuidad, propiedad/netting, reintentos, reconciliación/EXIT_PENDING y MFE/MAE. Verificar OFF/ORIGINAL, umbrales y descenso estrictos, shifts cerrados, consumo de rechazo/datos faltantes sin entrada tardía, ausencia de dependencia de ADX en gestión y AND con MACD. Distinguir pruebas auxiliares, revisión estática, compilación y backtesting.


# 23. V5A: filtro experimental de ancho relativo Bollinger

`InpReentryBBWFilter=false`, exclusivo de BB_REENTRY. Activarlo permite el primer reingreso únicamente si `BBW[1] <= BBW[2]`. Igualdad permite. Definir `BBW[i]=(UpperBand[i]-LowerBand[i])/SMA20[i]`, usando los buffers 1, 2 y 0 del iBands existente de la propia vela i. Leer solo shifts 1 y 2, sin vela actual/futuro, redondeo previo ni indicador nuevo. Esta sección define V5A; la sección 24 incorpora V5C como alternativa. No implementar V5B ni otros umbrales.

Reutilizar el snapshot de señal [1] y leer bandas/SMA y fecha de la vela [2]. Validar datos disponibles, finitos, distintos de EMPTY_VALUE, SMA positiva, Upper >= Lower y cociente finito. Ante datos inválidos/ausentes o BBW creciente, consumir/descartar preparación; no buscar permiso en otra vela interior ni ejecutar retrospectivamente. La preparación por cierre exterior se conserva; datos Bollinger [1] inválidos limpian preparación sin procesar esa evaluación.

Solo filtra nuevas entradas: no interviene en gestión, cierres ni modificaciones por cambios posteriores de BBW. Con false no lee [2] ni añade restricciones o snapshots BBW; ORIGINAL lo ignora. MACD y ADX conservan selectores/reglas; cuando se combinan con BBW, exigir AND en el mismo reingreso, sin que esas combinaciones formen parte de esta prueba.

INIT registra activación BBW. BBW_FILTER registra una vez por reingreso dirección, fechas de las velas [1]/[2], Upper/Lower/SMA de cada una, ambos BBW con 17 dígitos significativos, resultado y motivo (aumento o datos inválidos/ausentes). Datos faltantes se marcan n/a. La comparación usa doubles sin redondeo, independientemente del formato de logs.

Configuración de prueba manual, sin optimización: BB_REENTRY; BBW true; ADX_OFF; MACD false; SL 2 ATR; guard semanal true, 60/30 minutos; USD 25000 al 0.25%. Mantener el resto y los valores predeterminados globales anteriores. Hipótesis experimental sin ventaja ni rentabilidad demostrada.

Conservar entrada única sin E2, ATR congelado, SL/volumen, TP SMA20, riesgo/cierre monetario, guard semanal, enfriamiento/continuidad, propiedad/netting, reintentos/reconciliación/EXIT_PENDING y MFE/MAE. Verificar disminución/igualdad permitidas, aumento que consume preparación, datos incompletos/invalidos sin entrada tardía, snapshot propio por vela, shifts cerrados, ausencia de redondeo, regresión desactivada y ausencia de cambios de gestión/ORIGINAL. Separar revisión estática, pruebas auxiliares y compilación/backtesting pendientes.


# 24. BBW V5C: percentil 70 de las 100 velas anteriores

Conservar `InpReentryBBWFilter=false` como interruptor general. Añadir enum `ReentryBBWMode` e input `InpReentryBBWMode` con `BBW_NON_INCREASING` (predeterminado, V5A anterior: BBW[1] <= BBW[2]) y `BBW_BELOW_P70` (V5C). El modo solo se valida y aplica si BB_REENTRY y filtro habilitado; ORIGINAL lo ignora. Sin filtro, ninguna lectura de referencia ni condición adicional.

En V5C, BBW[1] procede del snapshot de la vela cerrada de reingreso. Referencia: exactamente 100 cocientes BBW[2] hasta BBW[101], cada uno `(Upper[i]-Lower[i])/SMA[i]` con sus propios buffers 1/2/0 del iBands existente. Validar los 101 valores: datos presentes, finitos, no EMPTY_VALUE, SMA positiva, bandas ordenadas y cociente finito. Comprobar fechas de referencia disponibles y anteriores a la vela de señal, en orden temporal inverso; no exigir continuidad adicional dentro del histórico.

Guardar los 100 valores y ordenar ascendentemente una copia. P70 es `sorted[69]`, elemento 70 de 100. No interpolar, redondear ni incluir BBW[1], shift=0 o datos futuros. Permitir solo `BBW[1] < P70`; igualdad rechaza. V5A y V5C son alternativas, nunca acumulativas.

Evaluar solo en el primer reingreso, consumiendo preparación con permiso, rechazo o datos insuficientes/invalidos; exigir otra preparación exterior y no ejecutar tarde. Mantener AND con filtros MACD/ADX activos en ese mismo reingreso. No intervenir en gestión ni cambiar señales, entrada única, ATR, SL/volumen/riesgo, SMA20 dinámica, guard semanal, enfriamiento/continuidad, reconciliación/reintentos/propiedad o MFE/MAE.

INIT registra filtro y modo efectivo (OFF al desactivar). Para V5C, BBW_FILTER registra modo, dirección, vela de señal, BBW1, fecha inicial de referencia (shift101), fecha final (shift2), valores=100, P70, resultado y motivo. En fallo, informar valores realmente obtenidos/requeridos=100 y n/a donde no exista dato, sin fabricar un percentil. Mantener precisión de 17 dígitos en logs, sin alterar el cálculo.

Comparar manualmente sin filtro, V5A y V5C manteniendo idénticos datos y demás parámetros de la prueba BBW (BB_REENTRY, ADX_OFF, MACD false, SL2, guard60/30, USD25000 al0.25%). Hipótesis experimental sin ventaja demostrada; sin V5B ni umbrales adicionales ni optimización automática.

Verificar índice69 con referencias desordenadas, exclusión de señal y lectura exacta2..101, igualdad rechazada, datos insuficientes/invalidos en extremos y centro, consumo sin entrada tardía, SMA propia de cada vela, independencia de V5A, modo inerte al desactivar y regresiones de gestión/ORIGINAL. Separar revisión estática y pruebas auxiliares de compilación/backtesting.


# 25. V6: BB_WICK_REJECTION

Estrategia experimental sin ventaja demostrada, añadida al enum Strategy con valor 2. Mantener ORIGINAL=0, BB_REENTRY=1 y predeterminado ORIGINAL. No sobrescribir reglas anteriores. Todo permanece en MeanReversionEA.mq5 con biblioteca estándar.

## Indicadores y parámetros

Solo Bollinger estándar M5 20/2.5 PRICE_CLOSE y ATR estándar M5 14, reutilizando la configuración fija de la gestión de una entrada. No crear ni validar Stochastic/RSI, MACD o ADX; no evaluar BBW ni preparación de reingreso. Ignorar InpSignalMode y parámetros de esos filtros/indicadores, incluidos modos inválidos que no aplican. InpWickMinRatio=0.40, finito con `0 < ratio <= 1`, validado solo para V6.

Reutilizar InpReentrySLATR en **BB_REENTRY y BB_WICK_REJECTION**, finito y positivo, sin cambiar el predeterminado 3.0 ni su aplicación anterior. V6 usa InpATRMax configurable, finito y positivo (predeterminado8); BB_REENTRY conserva su máximo fijo8. Mantener capital/riesgo, Magic Number, desviación y logs comunes. InpReentryWeekendGuard y márgenes se aplican a ambas estrategias de una entrada; ORIGINAL conserva su comportamiento.

## Señal cerrada

Evaluar una vez por nueva vela M5. OHLC, bandas, SMA y ATR provienen de la misma vela recién cerrada shift1. Definir rango=High−Low, cuerpo=abs(Close−Open), inferior=min(Open,Close)−Low y superior=High−max(Open,Close). Descartar rango no positivo o no finito, OHLC no finitos/EMPTY_VALUE o incoherentes (Open/Close fuera de Low..High), precios OHLC no positivos o Bollinger inválido.

Compra: Low <= Lower, inferior/rango >= InpWickMinRatio y Lower < Close < Upper.
Venta: High >= Upper, superior/rango >= InpWickMinRatio y Lower < Close < Upper.

Toque y ratio admiten igualdad; cierre interior es estricto. Comparar proporciones sin redondear. No filtrar color, Open dentro, tamaño de cuerpo, distancia de Close a banda ni vela exterior previa. Si ambas direcciones cumplen, descartar ambas y registrar AMBIGUOUS_SIGNAL. No registrar rechazos por simple ausencia de señal.

## Ejecución y gestión

Ejecutar E1 a mercado en el primer tick disponible de la nueva vela tras validar señal/riesgo. Una entrada sin E2/E3 ni pendientes. Consumir por fecha de vela y dirección antes de abrir, incluso si falla riesgo/ejecución; claves persistidas WICK separadas de BB_REENTRY y ORIGINAL. Sin nuevas ideas duplicadas; solicitudes inciertas se reconcilian mediante gestión común.

No evaluar durante actividad, cierre, solicitudes inciertas, bloqueo semanal o enfriamiento, ni recuperar oportunidades omitidas. En inicio/reinicio esperar nueva vela sin reconstruir señal histórica. Exigir `vela.time + 300 == nueva_vela.time`, sin rechazar primer tick unos segundos tarde; omitir barras antiguas tras pausa. Datos ausentes descartan oportunidad sin reintento tardío.

Congelar ATR1 de señal; rechazar <=0 o >InpATRMax. SL fijo desde ejecución real ±InpReentrySLATR×ATR. Calcular volumen para **una entrada**, con OrderCalcProfit y normalización al tick/volumen hacia abajo; verificar antes y tras ejecución real. Abortar/cerrar persistentemente si riesgo supera presupuesto o falla SL, sin reducir volumen ni desplazar SL. TP inicial SMA20[1] de señal, actualizaciones SMA20[1], sin factor0.90 ni cambios SL; Bid/Ask, objetivo lógico, restricciones y reintentos comunes. Sin trailing/breakeven.

Conservar una idea activa, moneda USD y guardas de probador/símbolo, propiedad ajena/netting, cierre monetario, reconciliación/EXIT_PENDING, reintentos, MFE/MAE, enfriamiento y limpieza de residuos. Guard semanal aplica a V6 con las mismas sesiones/reglas que antes. No prometer pérdidas ni cierre semanal garantizados.

## Diagnóstico y prueba

INIT: estrategia, ratio mínimo, SL_ATR, ATR máximo efectivo y configuración semanal. SIGNAL: evaluación/vela, dirección, OHLC, bandas/SMA/ATR, rango, cuerpo, mechas, proporciones inferior/superior/cuerpo sobre rango, distancia Close desde banda tocada normalizada por ATR, y cotización/referencia de mercado separada del Close. Si ATR no positivo, distancia n/a y riesgo rechaza después. Proporción de cuerpo y distancia son solo diagnóstico. Mantener ENTRY, TP_UPDATE y EXIT con MFE/MAE.

Configuración inicial: BB_WICK_REJECTION, InpWickMinRatio0.40, InpReentrySLATR2.0, riesgo0.25% sobre25000USD, guard semanaltrue con60/30. Resto sin cambios. No optimizar.

Verificar ratio40% y menor, cierre en banda, Open exterior, independencia del color, ausencia de preparación previa, doble señal, rango0/datos inválidos, solo shift1, continuidad/deduplicación/datos ausentes, entrada/riesgo únicos, guard semanal y regresiones ORIGINAL/BB_REENTRY/PnL/MFE/MAE. Distinguir pruebas auxiliares, revisión estática y compilación/backtesting pendientes.


# 26. ATR_DEVIATION_REENTRY: desviación normalizada por ATR

Hipótesis experimental sin ventaja demostrada. Añadir `ATR_DEVIATION_REENTRY=3` al selector conservando ORIGINAL=0 (predeterminado), BB_REENTRY=1 y BB_WICK_REJECTION=2 y sus reglas. Sin optimización automática.

## Indicadores y configuración efectiva

Crear únicamente `iMA(_Symbol, PERIOD_M5, 20, 0, MODE_SMA, PRICE_CLOSE)` y `iATR(_Symbol, PERIOD_M5, 14)`; verificar handles y liberar al descargar. No crear Bollinger ni osciladores, MACD o ADX; no usar BBW ni mechas. Ignorar sus parámetros/selectores y `InpSignalMode`, incluso si valores no pertinentes son inválidos. El TP también procede del iMA propio, nunca del buffer Bollinger.

`InpATRDeviationThreshold=1.5`, finito y >0, solo validado para esta estrategia. Investigar por separado 1.5, 2.0, 2.5 y 3.0. `InpReentrySLATR` se extiende a las tres estrategias de una entrada; predeterminado3.0 sin cambio anterior y prueba2.0. Usar InpATRMax configurable (predeterminado8), positivo y finito; conservar el límite fijo8 de BB_REENTRY y la configuración anterior de las otras estrategias. Capital/riesgo, Magic, desviación, logs y guard semanal comunes.

## Desviación, estados y transiciones

En cada nueva vela M5 evaluar una única vez la vela cerrada shift1. `D[i]=(Close[i]-SMA20[i])/ATR14[i]` con cada dato de la misma vela. Verificar CopyRates/CopyBuffer, números finitos y no EMPTY_VALUE, Close/SMA positivos, ATR>0 y D finito. No redondear D.

Estados NONE, WAIT_BUY_REENTRY y WAIT_SELL_REENTRY. Para T configurado:

- D < −T prepara compra; D > T prepara venta, sin ejecutar.
- Exteriores repetidos del mismo lado conservan fecha y snapshot Close/SMA/ATR/D de la primera preparación.
- Exterior estrictamente opuesto sustituye la preparación y snapshot.
- En una vela posterior, compra confirma si −T < D < 0; venta si 0 < D < T.
- Esperando compra, D >=0 descarta salvo que D >T prepare venta. Esperando venta, D <=0 descarta salvo que D <−T prepare compra. Procesar extremos opuestos antes del descarte por media.
- D igual a −T/+T no prepara ni confirma; conserva la preparación solo si no alcanzó/cruzó la media correspondiente. D=0 descarta.
- No vencimiento por número de velas, color, dirección del Close ni desplazamiento del precio. Un ATR mayor puede reducir |D| y confirmar sin regreso de Close; registrar cambios, no rechazarlos.

Consumir preparación al confirmar, aunque se rechace persistencia, riesgo o ejecución. Exigir otro exterior; claves de deduplicación ATRDEV por vela/dirección separadas de las anteriores. E1 a mercado en primer tick disponible de la nueva vela tras validaciones, una entrada sin E2/E3 ni pendientes; conservar reconciliación de resultados inciertos.

## Oportunidades, inicio y datos

Solo preparar/confirmar sin idea activa, cierre, bloqueo o enfriamiento. Limpiar al iniciar idea y enfriamiento; no acumular durante esos estados o solicitudes/exposición que bloqueen. Al iniciar/reiniciar, NONE, sin reconstrucción y esperar nueva vela. Mantener primera apertura actual como referencia.

Exigir continuidad entre horas de apertura de la vela cerrada y nueva (`+300s`); unos segundos de demora del tick no son un salto de barras. Si se omiten oportunidades M5 entre eventos, limpiar y omitir esa evaluación para esta estrategia. Si shift1 es antiguo tras una pausa, limpiar y omitir. Datos ausentes o inválidos limpian preparación y descartan sin recuperación retrospectiva en otro tick.

## Riesgo, objetivo y ciclo de vida

Gestión de una entrada compartida: congelar ATR1 de confirmación, rechazar ATR<=0 o >InpATRMax, calcular lote con OrderCalcProfit para SL a InpReentrySLATR×ATR; normalizar al tick y volumen hacia abajo, verificar riesgo normalizado y nuevamente con ejecución real. SL fijo desde E1 ejecutada, compra por debajo/venta por encima; abortar/cerrar si riesgo excede presupuesto, cálculo falla, lote mínimo no cabe o SL no puede establecerse. No reducir parcialmente volumen ni mover SL para acomodar riesgo; sin trailing/breakeven.

TP inicial SMA20[1] de confirmación, normalizada; actualizar con SMA20[1] en cada nueva vela en ambos sentidos. Sin InpTPFactor ni modificar SL. Bid>=objetivo para compra/Ask<=objetivo para venta inicia cierre, también si ya se alcanzó después de E1 o al actualizar. Conservar objetivo lógico, stops/freeze y reintentos.

Extender guard semanal existente a ATR_DEVIATION_REENTRY con InpReentryWeekendGuard: bloqueo limpia preparación y cierre anticipado WEEKEND_GUARD usa la gestión común. Conservar propiedad ajena/netting, una idea activa, Magic, cierre monetario con criterio actual de costes, enfriamiento, reintentos, reconciliación/EXIT_PENDING, PnL definitivo, MFE/MAE y limpieza de residuos. No garantizar pérdida o cierre frente a gaps/ausencia de eventos.

## Logs, configuración y verificación

INIT registra estrategia, T, SMA20/ATR14/M5, SL efectivo, máximo ATR y guard semanal/márgenes. PREPARATION registra dirección, fecha, Close/SMA/ATR/D iniciales; repeticiones exteriores no generan otro log. PREPARATION_CLEAR informa dirección, fecha y motivo, incluida sustitución o media alcanzada.

SIGNAL incluye evaluación, dirección, fechas de preparación/confirmación, Close/SMA/ATR/D de ambas y sus diferencias de Close, SMA y ATR, además de cotización/referencia de mercado separada. Las diferencias son diagnóstico, no filtros. Conservar ENTRY, TP_UPDATE, EXIT y MFE/MAE. No imprimir ausencia de señal cada vela ni repetir por tick.

Prueba: ATR_DEVIATION_REENTRY, T1.5 (repetir separadamente2.0/2.5/3.0), SL2ATR, riesgo0.25% de USD25000 y guardtrue60/30. Sin otros filtros ni optimización. Verificar exterior sin entrada, posteriores de ambos lados, distinta vela, igualdades, media/opuesto, exteriores repetidos, shifts propios, ATR creciente sin movimiento de Close, limpieza por datos/pausas, actividad/enfriamiento, una entrada/riesgo/SL, TP SMA, guard y MFE/MAE y regresiones anteriores. Separar revisión estática, pruebas auxiliares y compilación/backtesting pendientes.


# 27. S3: salida ATR fija exclusiva de BB_REENTRY

Añadir enum `ReentryExitMode` e input `InpReentryExitMode`:

- `EXIT_SMA20_DYNAMIC` predeterminado: conservar exactamente la salida SMA20 dinámica de BB_REENTRY.
- `EXIT_ATR_FIXED_2`: S3 experimental, sin otras salidas ni multiplicadores TP configurables.

Validar el selector únicamente en BB_REENTRY. ORIGINAL, BB_WICK_REJECTION y ATR_DEVIATION_REENTRY lo ignoran, sin cambios en señales, validaciones, indicadores o gestión de esas estrategias. Esta sección sustituye únicamente las reglas de objetivo SMA de BB_REENTRY al seleccionar S3.

Mantener las señales/preparación/reingreso y filtros existentes. Tras ejecutar E1 y conocer su precio real, calcular `TP=Price(E1 + direction * 2.0 * frozen_atr)`, dirección +1 para compra y −1 para venta. Usar exclusivamente el ATR congelado de la vela de confirmación; no la cotización solicitada, SMA ni ATR posterior. TP normalizado al tick, fijo hasta terminar la idea. No recalcular en nuevas velas ni aplicar InpTPFactor, trailing, breakeven, cierres parciales ni otro objetivo ATR.

Con SL configurado en 2 ATR la relación nominal de distancias es 1:1 antes de redondeos y ejecución. No garantizar relación monetaria exacta: normalización, volumen y costes/ejecución pueden diferir.

Conservar SL válido obligatorio, normalizado e inmóvil; volumen calculado únicamente desde SL y presupuesto, con comprobaciones existentes antes/tras ejecución. La fijación del TP desde E1 ocurre antes de establecer protección inicial. Si TP no se puede asignar por stops/freeze, mantener objetivo lógico y sincronización/reintentos existentes; fallar el SL obliga a abortar/cerrar. No dejar posición sin supervisión por rechazo del TP.

Objetivo lógico: compra Bid>=TP y venta Ask<=TP; iniciar cierre si ya se alcanzó. Sin modificación si TP servidor coincide con el solicitado. No modificar SL al sincronizar TP. Mantener reintentos controlados, solicitudes inciertas, propiedad ajena/netting, cierre monetario, guard semanal incluso mientras cierra, enfriamiento, reconciliación/EXIT_PENDING, PnL y MFE/MAE. No crear E2 ni otras pendientes.

INIT registra estrategia y salida efectiva. ENTRY de BB_REENTRY registra salida, E1 real, ATR congelado, lote, SL/TP normalizados y riesgo previsto. En S3, no publicar cambios de objetivo por velas nuevas; `TP_SYNC` identifica sincronización con servidor, no un nuevo objetivo. EXIT y métricas se conservan. El selector predeterminado conserva la ruta operativa anterior y logs de actualización dinámica.

Prueba sin optimización: BB_REENTRY, EXIT_ATR_FIXED_2, SL2ATR, riesgo0.25% de USD25000, ADX_OFF, MACDfalse, BBWfalse, guardtrue60/30. Repetir comparación con EXIT_SMA20_DYNAMIC y resto idéntico. Hipótesis experimental sin ventaja demostrada.

Verificar TP compra/venta desde ejecución real distinta de cotización inicial; ATR congelado; independencia de SMA/ATR posteriores; normalización; objetivo lógico, fallback/reintentos cuando servidor rechaza TP; conservación SL y ausencia de modificaciones redundantes; cierre monetario/semanal; regresión dinámica y demás estrategias. Separar simulaciones auxiliares/revisión estática de compilación/backtesting pendientes.


# 28. EXIT_HALF_SMA20_DYNAMIC exclusivo de BB_REENTRY

Ampliar ReentryExitMode conservando `EXIT_SMA20_DYNAMIC=0` predeterminado y `EXIT_ATR_FIXED_2=1`, añadiendo `EXIT_HALF_SMA20_DYNAMIC=2`. Validación solo en BB_REENTRY; las demás estrategias ignoran el selector y conservan sus objetivos.

Para compra y venta, objetivo normalizado al tick: `TP=Price(E1_ejecutada + 0.50 * (SMA20[1] - E1_ejecutada))`. Inicialmente calcular **después** de conocer E1 ejecutada, usando SMA20[1] de la vela de confirmación ya disponible. Cada nueva vela M5 recalcular con SMA20[1] y la misma E1 fija de la idea; no usar el precio actual ni actualizar la referencia E1 con el mercado. No aplicar InpTPFactor ni otro factor configurable.

Si compra Bid>=objetivo o venta Ask<=objetivo, iniciar cierre a mercado, también cuando un objetivo recién actualizado ya esté alcanzado. Conservar objetivo lógico, stops/freeze, sincronización y reintentos controlados si servidor no admite TP. No modificar SL. Mantener ENTRY/TP_UPDATE/EXIT y MFE/MAE; INIT y ENTRY identifican EXIT_HALF_SMA20_DYNAMIC.

Sin cambios de señal, entrada única, riesgo/volumen, ATR congelado, SL, cierre monetario, protección semanal (la supervisión durante WEEKEND_GUARD usa la misma fórmula), enfriamiento, propiedad/netting, solicitudes inciertas y reconciliación/EXIT_PENDING. Conservar los otros modos sin cambio operativo.

Verificar ambos sentidos desde fill distinto de cotización, normalización, referencia E1 invariable en nuevas velas, lectura shift1, cierre al alcanzar objetivo actualizado, rechazo de TP con objetivo lógico y reintento sin tocar SL, y regresión de salida SMA20 completa, ATR fijo y estrategias ajenas al selector. Hipótesis experimental sin ventaja demostrada. Distinguir pruebas auxiliares/revisión estática de compilación y backtesting MT5 pendientes.


# 29. EXIT_OPPOSITE_BAND_DYNAMIC exclusivo de BB_REENTRY

Añadir `EXIT_OPPOSITE_BAND_DYNAMIC=3` a InpReentryExitMode, conservando EXIT_SMA20_DYNAMIC=0 predeterminado, EXIT_ATR_FIXED_2=1 y EXIT_HALF_SMA20_DYNAMIC=2 y sus comportamientos.

Compra: objetivo en UpperBand[1]. Venta: objetivo en LowerBand[1]. Usar el handle Bollinger existente y sus parámetros efectivos de BB_REENTRY, sin otro indicador ni cambio de configuración. Tomar el snapshot cerrado shift1 de la señal para el objetivo inicial, pero establecerlo solo después de confirmar ejecución real de E1. Normalizar al tick.

Cada nueva vela M5, recalcular con las bandas de la última cerrada shift1; se puede mover en ambos sentidos, sin limitarlo respecto al precio actual ni usar InpTPFactor. Compra cierra si Bid>=objetivo y venta si Ask<=objetivo, inclusive. Si ya se alcanzó al asignar o actualizar, iniciar cierre a mercado. Conservar objetivo lógico, stops/freeze, sincronización/reintentos y SL obligatorio sin modificarlo.

INIT y ENTRY registran modo efectivo; conservar TP_UPDATE, EXIT y métricas. Selector validado solo en BB_REENTRY; las demás estrategias lo ignoran. Mantener señales, entrada única/sin E2, filtros, ATR congelado, riesgo/volumen, SL, guard semanal y enfriamiento, propiedad/netting, reconciliación/EXIT_PENDING y MFE/MAE.

Verificar compra/superior y venta/inferior, normalización, inicialización tras E1, actualizaciones cerradas1 en ambos sentidos, cierre por objetivo alcanzado, fallback/reintento sin tocar SL y regresiones de salidas anteriores y estrategias ajenas. Hipótesis experimental sin ventaja demostrada; no optimizar. Distinguir revisión estática y pruebas auxiliares de compilación y backtesting realmente ejecutados.


# 30. EXIT_HALF_SMA20_TRAIL_ATR: parcial confirmado y remanente con trailing

Añadir `EXIT_HALF_SMA20_TRAIL_ATR=4`, exclusivamente BB_REENTRY; conservar los valores0..3, el predeterminado EXIT_SMA20_DYNAMIC y los comportamientos anteriores. No añadir parámetros nuevos. Es una hipótesis experimental sin ventaja demostrada. Las reglas siguientes sustituyen solo la salida de esta opción; no cambian entradas, filtros ni presupuesto/lotaje.

## Antes del parcial

Una entrada con SL inicial actual y ATR de confirmación congelado durante toda la idea. Objetivo **SMA20[1] completo**, no la mitad del recorrido pese al nombre HALF (HALF indica volumen). Actualizar lógico al comienzo de cada nueva vela M5, con normalización al tick. No instalar TP de posición: el TP del servidor permanece0. Compra activa parcial si Bid>=objetivo; venta si Ask<=objetivo, también si ya está alcanzado tras E1. Mantener SL obligatorio y cierre monetario/semanal.

## Solicitud y reconciliación

Calcular unidades enteras de volumen inicial respecto al paso: cerrar floor(unidades/2) pasos, conservando el resto. Ejemplo:0.15 con paso0.01 cierra0.07 y deja0.08. Tanto parcial como remanente deben respetar mínimo, máximo y paso. Si no hay división válida, registrar PARTIAL_NOT_POSSIBLE y entrar en cierre completo común, sin enviar parcial.

Enviar un deal contrario con `MqlTradeRequest.position` explícito y símbolo/Magic, verificando antes propiedad, identificador y volumen de la posición. Es la misma solicitud dirigida por ticket para hedging y netting, sin nuevas entradas ni órdenes pendientes. Preferir FOK, luego IOC y política RETURN cuando corresponda al símbolo. Mantener requisitos de exclusividad netting y protección de mezcla: no cerrar/modificar posición ajena/mezclada. No se puede garantizar exclusividad frente a operaciones externas concurrentes, como ya documentado.

Una vez activado, el parcial queda solicitado aunque el precio retroceda antes de un reintento. Dar a cada intento comentario único por idea/secuencia y recordar sus órdenes. Rechazos definitivos sin ejecución permiten reintento controlado; resultados inciertos o incompletos permanecen bloqueados sin desbloqueo por tiempo. Recuperar una orden de historial por símbolo/Magic/comentario si no llegó su ticket. No reenviar hasta que la orden sea terminal, todos sus deals estén presentes y el volumen observado coincida con el historial. Eventos duplicados no acumulan de nuevo el volumen ni reinician el trailing.

Si IOC solo ejecuta parte de la cantidad solicitada, reconciliarla y solicitar únicamente lo que falta para el parcial total previsto. Si esa diferencia no es negociable, cerrar toda la idea con PARTIAL_NOT_POSSIBLE. No hay reducciones adicionales tras completar ese parcial. Si nunca llega identidad o historial suficiente de una solicitud incierta, conservar el bloqueo y la protección vigente, registrar PARTIAL_PENDING/problemas y no inventar que falló; puede requerir resolver el historial o intervención externa. No se promete ejecución frente a ausencia de eventos/servidor.

Bloquear cierres/modificaciones solapados de la misma posición mientras haya parcial incierto o volumen por reconciliar, incluso si cambia el ticket pero se conserva el identificador. Un cierre monetario/semanal puede iniciar CLOSING_IDEA inmediatamente; completar la solicitud pendiente y su reconciliación antes de enviar otro cierre de esa exposición. No finalizar la idea mientras el parcial siga pendiente.

El historial distingue únicamente los deals reconocidos del parcial propio: no terminan la idea. Salidas por SL/TP u otra salida siguen las reglas de finalización comunes. Si coinciden un parcial y SL/cierre, reconciliar todas las salidas del identificador para no dejar un bloqueo permanente. Mantener reconciliación del PnL con comisiones/fee/swap y EXIT_PENDING: el resultado final suma parcial y remanente y solo se publica cuando esté completo.

## Trailing después de confirmar

Activar únicamente cuando orden/deals y volumen real confirmen el parcial total y remanente válido. El remanente queda sin TP. Iniciar el extremo con Bid para compra/Ask para venta **vigente en la confirmación**, sin usar MFE ni precios anteriores al parcial. Si no hay cotización, esperar la primera disponible sin inventar el extremo.

En cada tick observar máximo Bid desde ese inicio para compra o mínimo Ask para venta. SL candidato: máximoBid−ATR_congelado o mínimoAsk+ATR_congelado. Normalizar al tick; solo solicitar si mejora el SL existente y es válido respecto a precio/stops/freeze. Nunca aflojar SL, eliminarlo ni introducir breakeven independiente. Guardar extremos observados incluso durante una indisponibilidad temporal del historial; no enviar modificaciones hasta verificar propiedad/estado.

Mantener SL anterior durante rechazos/reintentos. Acreditar nuevo SL solo cuando el servidor lo confirme en la posición; un resultado incierto mantiene bloqueo de solicitudes y el candidato esperado. Evitar modificaciones idénticas. SL ausente/alterado por fuera de lo esperado inicia cierre protegido. Tras confirmar parcial, dejar de actualizar objetivo SMA y no generar otro parcial. La idea permanece activa hasta cerrar completamente el remanente.

La protección semanal conserva prioridad de cierre completo y no inicia parciales durante CLOSING_IDEA. Mantener cierre monetario, enfriamiento tras finalización completa, reintentos, propiedad/netting, reconciliación y MFE/MAE conjuntos. No reiniciar MFE/MAE ni presupuesto con el parcial; el diagnóstico continúa realizado+flotante según las reglas existentes. Al reiniciar EA no reconstruir el trailing: limpiar residuos según las reglas anteriores y aplicar enfriamiento tras confirmar la limpieza.

## Logs y verificación

INIT/ENTRY identifican modo. TP_UPDATE registra objetivo SMA antes del parcial; PARTIAL_TARGET registra activación; PARTIAL_REQUEST solicitud/volumen/comentario; PARTIAL_PENDING espera sin duplicar; PARTIAL_REJECTED error; PARTIAL_CONFIRMED volumen cerrado, restante, extremo inicial y ATR congelado; TRAIL_UPDATE cambios confirmados de SL. PARTIAL_NOT_POSSIBLE señala fallback de cierre completo. Errores usan limitación de repetición común; no publicar resúmenes EXIT prematuros.

Verificar compra/venta, división impar/min/step e inválida, TP servidor0, rechazo/reintento y resultado incierto, historial/volumen atrasados, callbacks duplicados, IOC ejecutado parcialmente, orden no terminal, SL concurrente, propiedad/mode netting/hedging, bloqueo por identificador, trailing desde confirmación/ATR fijo/sin aflojar, error/confirmación SL, PnL parcial+remanente y regresiones de modos anteriores. Separar payloads/simulaciones offline de compilación MQL5 y ejecución MT5 real.
