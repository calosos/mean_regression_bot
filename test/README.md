# Pruebas locales de MeanReversionEA

Suite offline con Python `unittest` (biblioteca estándar). No necesita paquetes Python, entorno virtual, conexión de red, cuentas de trading ni archivos de `/tmp` de sesiones anteriores. Requiere Python 3.10+; las catorce pruebas de comportamiento necesitan además un compilador C++17 (`g++`, verificado en Linux/WSL). Se puede seleccionar otro compilador mediante `CXX=clang++`.

Desde la raíz del repositorio:

```bash
python3 -m unittest discover -s test -t . -v
```

Con `uv`, sin instalar paquetes ni crear un proyecto o entorno:

```bash
uv run --no-project --no-managed-python --offline python3 -m unittest discover -s test -t . -v
```

También se puede ejecutar solo un módulo:

```bash
python3 -m unittest test.test_behavior -v
python3 -m unittest test.test_behavior.BehaviorTests.test_exit_reconciliation_and_delayed_identity -v
```

Si no hay compilador C++17, las catorce pruebas de comportamiento aparecen explícitamente como **skipped**; siguen ejecutándose las comprobaciones Python. Un resultado con skips no acredita esas regresiones de comportamiento.

## Qué se comprueba

| Prueba | Cobertura |
| --- | --- |
| `test_behavior.py`: riesgo | 12,570 combinaciones ejecutables de lote/riesgo, presupuesto, paso de volumen, ATR, fallo de cálculo, señales, objetivos Bid/Ask y 86,400 instantes de enfriamiento |
| `test_behavior.py`: gestión | 60,000 ticks; espera de 5 segundos, 12 rechazos Market closed por minuto simulado, ausencia de duplicados, recuperación, órdenes ajenas, posición netting mezclada y E2 durante limpieza |
| `test_behavior.py`: cierres | E2 y dos cierres del mismo segundo: 24 permutaciones, 15 historiales incompletos, PnL -49.89, identidad preservada tras nueva idea, cierres parciales, costes, cancelación y parciales de E2 |
| `test_behavior.py`: excursiones | MFE/MAE conjuntos, E2 sin reinicio, realizado + flotante/swap, parciales, cierres simultáneos, coherencia de volumen/tiempo, final MAE, presupuesto/R, fechas y duración |
| `test_behavior.py`: modos | `OnTick` real con datos simulados: INTRABAR/CLOSED_BAR, ambas direcciones, límites de Close/%K, ATR[1], TP inicial[0], RSI independiente con extremos/igualdades y umbrales configurables; BB_REENTRY con mechas, preparación/confirmación, igualdad, sustitución, continuidad y bloqueo, ausencia de duplicados, históricos al iniciar y entradas tardías por datos faltantes, actividad o enfriamiento |
| `test_behavior.py`: BB ejecución | OpenIdea/SL/TP reales: una entrada sin E2, riesgo para SL de 3/2 ATR con mismo presupuesto y verificación tras ejecución, SL fijo, objetivo SMA y fallback, parciales y solicitudes inciertas |
| `test_behavior.py`: inicialización | OnInit real: indicadores y parámetros pertinentes, BB fijos, ningún oscilador, preparación vacía, validación de multiplicador SL solo en BB_REENTRY, guardas Probador/USD |
| `test_behavior.py`: cierre semanal | SymbolInfoSessionTrade simulado y funciones reales de unión/proyección, bloqueo, cierre y OnTick; límites exactos, medianoche/nocturnas/sesiones múltiples, pausas diarias, reapertura, cambios, exposición residual, datos inválidos y logs sin repetición |
| `test_behavior.py`: logs | Función real `SignalLog`: OHLC/indicadores, retrasos 190802/3600/3600 segundos, cotización separada, referencia compra/venta, cotización ausente, etiquetas RSI/K, shifts, umbrales efectivos y logs detallados |
| `test_harness.py` | Extracción correcta del fuente frente a llaves en comentarios/literales, errores por funciones inexistentes, estructuras y adaptación de arrays agrupados |
| `test_contracts.py` | Defaults exigidos, bibliotecas/dependencias permitidas y guardas de inicialización para Probador/USD y diagnóstico sin efectos operativos; revisión estática |

Los contadores de combinaciones son escenarios internos de los tests, no miles de casos separados de `unittest`. Los ejemplos de OHLC del test de logs son sintéticos; no representan una repetición del histórico del bróker. La comprobación de los Diarios reales de pausas está documentada por separado en el README principal y no depende de su disponibilidad para ejecutar la suite.

## Cómo funciona el arnés

`harness.py` lee el **MeanReversionEA.mq5 actual**, extrae los cuerpos de las funciones seleccionadas, las estructuras y las declaraciones necesarias y compila un programa auxiliar con los adaptadores de `fixtures/*_mock.hpp` y los escenarios de `fixtures/*_cases.cpp`. Los fixtures no guardan copias de las funciones del EA. Los programas generados y sus ejecutables viven en directorios temporales distintos por ejecución y se eliminan al terminar. No se modifica el EA, el terminal MT5 ni las bibliotecas estándar.

La adaptación cambia declaraciones de arrays dinámicos MQL5 por `std::vector`; el resto de la lógica seleccionada se conserva. Las respuestas de indicadores, historial, transacciones y `CTrade` son simuladas. Por ejemplo, `OrderCalcProfit()` del test de riesgo simula un contrato lineal de 100 onzas. Algunos colaboradores se sustituyen por mocks para aislar la ruta; por ello la cobertura conjunta no equivale a una prueba integrada del EA completo.

Esta suite **no compila MQL5, no genera un EX5 y no ejecuta un backtest MT5**. No valida las particularidades del compilador MQL5, el orden real de eventos del terminal, los datos de un bróker o su ejecución. Esas verificaciones siguen requiriendo MetaEditor y el Probador de Estrategias. Los errores del compilador C++ auxiliar se identifican como tales en la salida.

La suite actual contiene 22 tests de `unittest` (14 de comportamiento, 4 del arnés y 4 contratos estáticos). El contrato MFE/MAE impide que las funciones de medición envíen operaciones, muten estados operativos o impriman logs por tick. La regresión de excursiones usa el mismo lector de PnL coherente que el resumen final.

## Mantenimiento

Cuando cambien funciones o colaboradores del EA, actualizar los adaptadores y escenarios correspondientes. Si una función desaparece o deja de compilar con el adaptador, el test falla; no usa una copia antigua ni descarga dependencias. No reemplazar estos tests por una traducción independiente de la estrategia a Python: se perdería el vínculo con el código que se pretende revisar.

El `.gitignore` raíz excluye cachés de Python, entornos, cobertura local, EX5 y Diarios/reportes generados. Los archivos fuente de esta carpeta deben versionarse. No se requiere modificar reglas de trading ni instalar infraestructura externa para ejecutar las pruebas.


La prueba semanal usa un reloj sintético de servidor y un patrón de sesiones en memoria. No consulta un bróker real. Los intentos repetidos desde la ruta semanal se comprueban con CloseStep simulado; las solicitudes/rechazos, control de reintentos, propiedad ajena y netting se cubren por separado con CloseStep real en la regresión de gestión. La composición con el servidor, las sesiones históricas y los festivos siguen pendientes de MT5. Se conservan las regresiones existentes de PnL, MFE/MAE y enfriamiento.

La regresión de señales incluye confirmación MACD BB_REENTRY con ambas direcciones, H=MAIN-SIGNAL en buffers 0/1 y shifts 1/2, igualdades, consumo de rechazos/datos faltantes y filtro desactivado. OnInit prueba periodos y creación condicional del handle. La suite sigue teniendo 17 tests; se ampliaron escenarios dentro de los existentes.

ADX: escenarios guardados en signal_modes_cases.cpp para cuatro modos, ambas direcciones, umbrales/descenso estrictos, shifts 1/2, consumo definitivo ante rechazo/datos faltantes, AND con MACD y ausencia de lecturas durante gestión. initialization_cases.cpp verifica creación condicional/selector. La suite mantiene 17 tests ampliados, no compilación MQL5 ni backtesting.

V5A BBW: signal_modes_cases.cpp amplía los 17 tests existentes con disminución/igualdad/aumento, ambos lados, SMA propia por vela, lecturas cerradas [1]/[2], incremento mínimo sin redondeo, datos ausentes/invalidos, consumo sin entrada tardía y regresión desactivada/gestión. No requiere indicadores nuevos ni backtest para ejecutar la suite offline.

V5C: la suite de 17 tests amplía signal_modes_cases.cpp con BBW[2..101] desordenados y SMA propia, puesto70/índice69, exclusión de señal, igualdad estricta y fallos en shifts2/51/101 sin entrada tardía; conserva escenarios V5A/desactivado. initialization_cases.cpp valida el modo únicamente con BB_REENTRY y filtro activo.

V6: nuevo escenario wick_cases.cpp/ wick_mock.hpp ejecuta las funciones reales WickSignalSide, EvaluateWickSignal y OnTick para mechas, cuerpo diagnóstico, límites, datos inválidos y oportunidades omitidas. Las regresiones single_entry, initialization y weekend también cubren BB_WICK_REJECTION. La suite completa tiene 18 tests, sin compilación MQL5 ni backtesting.

wick_trace_cases.cpp también comprueba el formateador real de SIGNAL V6: todos los campos geométricos/diagnósticos, distancia ATR, OHLC e indicadores y referencias Bid/Ask para ambas direcciones, sin duplicados.

ATR_DEVIATION_REENTRY: nuevo escenario atr_deviation_cases.cpp con OnTick real y SMA/ATR simulados; transiciones, igualdades, primera preparación, media/opuestos, ATR creciente sin regreso del precio, datos/discontinuidades/bloqueos y TP sin Bollinger. atr_deviation_trace_cases.cpp verifica snapshots/diferencias del log real. Inicialización, entrada y guard semanal también se amplían. Suite actual:19 tests,11 de comportamiento; no compilación MQL5 ni backtesting.

S3: single_entry_cases.cpp comprueba OpenIdea/SL/SyncTP reales con TP fijo compra/venta desde fill distinto, normalización, fallback, reintento y logs TP_SYNC. signal_modes_cases.cpp y weekend_cases.cpp prueban que OnTick/supervisión semanal no recalculan objetivo ni desactivan cierres. initialization_cases.cpp valida el selector solo en BB_REENTRY. La suite mantiene19 tests ampliados, con regresiones dinámicas y otras estrategias.

Salida de media distancia: nuevo half_exit_cases.cpp/half_exit_mock.hpp ejecuta Target y OnTick reales con E1 fija, SMA[1], ambos sentidos y cierre al alcanzar el objetivo actualizado. single_entry_cases.cpp cubre OpenIdea desde fill distinto, sincronización/fallback y SL intacto. La suite actual contiene20 tests (14 de comportamiento), conservando regresiones de los otros modos y estrategias. Compilación MQL5 y backtesting siguen pendientes.

Banda opuesta: se amplían single_entry_cases.cpp y half_exit_cases.cpp con EXIT_OPPOSITE_BAND_DYNAMIC: compra/superior, venta/inferior, TP inicial tras E1, tick, objetivos alcanzados, fallback, SL intacto y actualización cerrada1 en ambos sentidos con OnTick/Target reales. initialization_cases.cpp valida el nuevo modo. La suite mantiene20 tests y las regresiones de modos anteriores; no compila MQL5 ni ejecuta MT5.


Parcial + trailing: nuevos partial_trail_cases.cpp/partial_trail_mock.hpp y partial_route_cases.cpp/partial_route_mock.hpp. Se extraen las funciones actuales de solicitud, identificación, historial/volumen, inspección de deals y trailing; el segundo escenario comprueba OnTick con colaboradores simulados. Se cubren compra/venta, pasos/mínimos, payload de cierre por ticket (hedging/netting), rechazos, recuperación de resultados inciertos, callbacks duplicados, IOC, orden no terminal, eventos fuera de orden, SL concurrente, bloqueo por identificador, extremo desde confirmación, SL confirmado sin aflojar y PnL de ambas partes. Se conserva la regresión real de gestión/PnL/MFE/MAE anterior. El adaptador partial_legacy_mock.hpp mantiene inertes estos colaboradores en regresiones de modos anteriores; no sustituye las funciones de las nuevas pruebas. La suite actual contiene22 tests (14 de comportamiento). No equivale a compilación MQL5, validación de servidor ni backtesting MT5.
