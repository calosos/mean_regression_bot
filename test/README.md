# Pruebas locales de MeanReversionEA

Suite offline con Python `unittest` (biblioteca estándar). No necesita paquetes Python, entorno virtual, conexión de red, cuentas de trading ni archivos de `/tmp` de sesiones anteriores. Requiere Python 3.10+; las cinco pruebas de comportamiento necesitan además un compilador C++17 (`g++`, verificado en Linux/WSL). Se puede seleccionar otro compilador mediante `CXX=clang++`.

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

Si no hay compilador C++17, las cinco pruebas de comportamiento aparecen explícitamente como **skipped**; siguen ejecutándose las comprobaciones Python. Un resultado con skips no acredita esas regresiones de comportamiento.

## Qué se comprueba

| Prueba | Cobertura |
| --- | --- |
| `test_behavior.py`: riesgo | 12,570 combinaciones ejecutables de lote/riesgo, presupuesto, paso de volumen, ATR, fallo de cálculo, señales, objetivos Bid/Ask y 86,400 instantes de enfriamiento |
| `test_behavior.py`: gestión | 60,000 ticks; espera de 5 segundos, 12 rechazos Market closed por minuto simulado, ausencia de duplicados, recuperación, órdenes ajenas, posición netting mezclada y E2 durante limpieza |
| `test_behavior.py`: cierres | E2 y dos cierres del mismo segundo: 24 permutaciones, 15 historiales incompletos, PnL -49.89, identidad preservada tras nueva idea, cierres parciales, costes, cancelación y parciales de E2 |
| `test_behavior.py`: modos | `OnTick` real con datos simulados: INTRABAR/CLOSED_BAR, ambas direcciones, límites de Close/%K, ATR[1], TP inicial[0], ausencia de duplicados, históricos al iniciar y entradas tardías por datos faltantes, actividad o enfriamiento |
| `test_behavior.py`: logs | Función real `SignalLog`: OHLC/indicadores, retrasos 190802/3600/3600 segundos, cotización separada, referencia compra/venta, cotización ausente y logs detallados |
| `test_harness.py` | Extracción correcta del fuente frente a llaves en comentarios/literales, errores por funciones inexistentes, estructuras y adaptación de arrays agrupados |
| `test_contracts.py` | Defaults exigidos, bibliotecas/dependencias permitidas y guardas de inicialización para Probador/USD; revisión estática |

Los contadores de combinaciones son escenarios internos de los tests, no miles de casos separados de `unittest`. Los ejemplos de OHLC del test de logs son sintéticos; no representan una repetición del histórico del bróker. La comprobación de los Diarios reales de pausas está documentada por separado en el README principal y no depende de su disponibilidad para ejecutar la suite.

## Cómo funciona el arnés

`harness.py` lee el **MeanReversionEA.mq5 actual**, extrae los cuerpos de las funciones seleccionadas, las estructuras y las declaraciones necesarias y compila un programa auxiliar con los adaptadores de `fixtures/*_mock.hpp` y los escenarios de `fixtures/*_cases.cpp`. Los fixtures no guardan copias de las funciones del EA. Los programas generados y sus ejecutables viven en directorios temporales distintos por ejecución y se eliminan al terminar. No se modifica el EA, el terminal MT5 ni las bibliotecas estándar.

La adaptación cambia declaraciones de arrays dinámicos MQL5 por `std::vector`; el resto de la lógica seleccionada se conserva. Las respuestas de indicadores, historial, transacciones y `CTrade` son simuladas. Por ejemplo, `OrderCalcProfit()` del test de riesgo simula un contrato lineal de 100 onzas. Algunos colaboradores se sustituyen por mocks para aislar la ruta; por ello la cobertura conjunta no equivale a una prueba integrada del EA completo.

Esta suite **no compila MQL5, no genera un EX5 y no ejecuta un backtest MT5**. No valida las particularidades del compilador MQL5, el orden real de eventos del terminal, los datos de un bróker o su ejecución. Esas verificaciones siguen requiriendo MetaEditor y el Probador de Estrategias. Los errores del compilador C++ auxiliar se identifican como tales en la salida.

## Mantenimiento

Cuando cambien funciones o colaboradores del EA, actualizar los adaptadores y escenarios correspondientes. Si una función desaparece o deja de compilar con el adaptador, el test falla; no usa una copia antigua ni descarga dependencias. No reemplazar estos tests por una traducción independiente de la estrategia a Python: se perdería el vínculo con el código que se pretende revisar.

El `.gitignore` raíz excluye cachés de Python, entornos, cobertura local, EX5 y Diarios/reportes generados. Los archivos fuente de esta carpeta deben versionarse. No se requiere modificar reglas de trading ni instalar infraestructura externa para ejecutar las pruebas.
