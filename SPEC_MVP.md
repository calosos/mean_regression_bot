# Proyecto: Mean Reversion EA V2 — XAUUSD M5

## 1. Objetivo

Desarrollar un Expert Advisor (EA) en **MQL5** que implemente una estrategia de regreso a la media utilizando Bollinger Bands, Stochastic y ATR.

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

# 3. Detección de señales

Las señales deben evaluarse durante la formación de la vela M5.

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

No esperar al inicio de una nueva vela.

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
| Magic Number                   | 20261104     |
| Capital de referencia          | 25000        |
| Riesgo por idea                | 0.25%        |
| Bollinger Period               | 20           |
| Bollinger Deviation            | 2.5          |
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

* Fecha/hora.
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
2. Detecte señales durante la formación de las velas.
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
4. **Señales:** identificar cada señal por vela M5 y dirección. Consumirla cuando se evalúa con datos completos, incluso si falla riesgo o ejecución. No reintentar esa dirección en la misma vela. La falta de datos de indicadores no consume la señal. Reconciliar cualquier ejecución incierta antes de permitir otra idea.
5. **Riesgo real:** después de E1 y antes de E2, recalcular E2 y SL desde el precio real ejecutado, normalizar al tick size y verificar el riesgo conjunto con el volumen real. Si excede el presupuesto o falla el cálculo, cerrar E1 y abortar. No reducir parcialmente E1 ni desplazar el SL para acomodar riesgo.
6. **Fallos de cierre/cancelación:** conservar `CLOSING_IDEA`, reconciliar en ticks y transacciones y reintentar acciones necesarias sin duplicar solicitudes todavía pendientes de respuesta. No abandonar tras un máximo de intentos. Si E2 se ejecuta durante el cierre, cerrar también su exposición propia. Iniciar enfriamiento únicamente al confirmar ausencia de posiciones, órdenes y solicitudes propias pendientes. En posición mezclada solo cancelar pendientes propias y requerir intervención manual.
7. **Ejecución parcial:** preferir ejecución completa cuando esté disponible. Si E1 o E2 se ejecutan parcialmente, cancelar remanentes y cerrar la idea, sin completar entradas con órdenes adicionales.
8. **TP inicial:** aplicar desde E1 el mismo objetivo lógico y gestión por tick de las actualizaciones. Si ya se alcanzó, cerrar sin colocar E2. Si restricciones del bróker impiden asignarlo, supervisarlo por tick y reintentar su asignación, manteniendo obligatorio un SL válido.
