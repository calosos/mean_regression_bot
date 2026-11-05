# Cierre del experimento de investigación — Mean Reversion EA

Fecha de cierre documental: 2026-11-05.

**No se demostró una ventaja suficiente. Esta versión no está validada para operar en real.** Se conserva como experimento de investigación, con su EA, especificación, documentación y pruebas auxiliares. Este cierre no declara completada la validación operativa ni introduce cambios en la lógica.

## Alcance y evidencia

El experimento implementa regreso a la media en XAUUSD M5 con Bollinger, Stochastic y ATR, dos entradas del mismo lote, riesgo configurado del 0.25%, SL común y TP dinámico. Se estudiaron señales intrabar y confirmación al cierre. Los parámetros predeterminados conservados en el EA son Stochastic 14,3,3 e `InpSignalMode=INTRABAR`.

Para este resumen se consultaron `README.md`, `SPEC_MVP.md`, el registro de verificaciones del proyecto y el Diario existente del agente:

```text
%APPDATA%/MetaQuotes/Tester/6FBEE76C719DC78AB2AE839B5A0C7442/
Agent-127.0.0.1-3001/logs/20261104.log
```

Los importes siguientes proceden de sus líneas `initial deposit`, parámetros de entrada, `INIT modelo=hedging` y `final balance`. Son ejecuciones históricas ya realizadas; no se lanzó otro backtest para este cierre. No se dispone de una correspondencia verificada mediante hash entre cada EX5 histórico y el fuente actual, que incorpora correcciones y diagnóstico añadidos posteriormente.

## Variantes y resultados históricos disponibles

Todas las ejecuciones de la tabla declaran depósito inicial de **25,000 USD**, apalancamiento **1:30** y modelo de cuenta **hedging**. Los parámetros registrados incluyen Bollinger 20/2.5, ATR 14 con máximo 8, TP factor 0.90 y referencia de riesgo 25,000 USD al 0.25%.

La variación de saldo es `saldo final − depósito inicial`. El porcentaje es esa variación dividida entre 25,000; no es una rentabilidad anualizada, un profit factor ni una medida ajustada al riesgo. Los periodos son los límites de inicio/fin mostrados por el probador.

| Variante histórica | Stochastic K,D,Slowing | Periodo registrado | Saldo final USD | Variación USD | Variación % |
| --- | --- | --- | ---: | ---: | ---: |
| Intrabar anterior al enum | 14,3,3 | 2026-07-01 → 2026-08-01 | 24,699.65 | -300.35 | -1.20% |
| Intrabar anterior al enum | 14,3,3 | 2026-08-01 → 2026-09-01 | 25,115.17 | +115.17 | +0.46% |
| Intrabar anterior al enum | 14,3,3 | 2026-09-01 → 2026-10-01 | 24,311.12 | -688.88 | -2.76% |
| Intrabar anterior al enum | 14,3,3 | 2026-08-01 → 2026-11-01 | 25,252.06 | +252.06 | +1.01% |
| Intrabar anterior al enum | 14,4,4 | 2026-07-01 → 2026-11-01 | 25,451.93 | +451.93 | +1.81% |
| Intrabar anterior al enum | 20,4,4 | 2026-07-01 → 2026-11-01 | 24,901.33 | -98.67 | -0.39% |
| CLOSED_BAR (`InpSignalMode=1`) | 14,3,3 | 2026-07-01 → 2026-11-01 | 24,617.43 | -382.57 | -1.53% |
| CLOSED_BAR, comprobación corta | 14,3,3 | 2026-07-01 → 2026-07-02 | 24,889.30 | -110.70 | -0.44% |

Las versiones anteriores no incluían `InpSignalMode` en sus entradas: su carácter intrabar se identifica por el comportamiento registrado y el desarrollo documentado. No se les atribuye retrospectivamente un valor enum que no aparece en el Diario.

Referencias de líneas del archivo del agente, en el orden de las primeras seis filas: inicio/entradas y saldo final **96638–96651 / 109010**, **12372–12385 / 24031**, **27–40 / 12346**, **24057–24070 / 59945**, **109037–109050 / 147537** y **147557–147570 / 183675**. Para CLOSED_BAR: **183710–183724 / 201606** y **219575–219589 / 219872**.

La ejecución intrabar de agosto–noviembre repitió saldo final de 25,252.06 en una ejecución posterior (entradas 60724–60737; saldo 96613). CLOSED_BAR de julio–noviembre también repitió 24,617.43 (entradas 201640–201654; saldo 219536). Estas repeticiones del mismo periodo no son muestras independientes ni evidencia fuera de muestra.

Existe además una ejecución intrabar corta de diagnóstico, 2026-09-27 → 2026-09-29, con Stochastic 14,3,3 y saldo final 25,001.46 USD, variación +1.46 USD (entradas 59980–59993; saldo 60690). No constituye una validación estadística de la estrategia.

## Interpretación y límites de los resultados

Los resultados disponibles tienen signos distintos según parámetros y periodo. El resultado positivo de 14,4,4 en julio–noviembre no demuestra robustez ni superioridad: no se conserva aquí un ensayo controlado de todas las variantes con el mismo binario, periodo y condiciones. Tampoco se deben sumar los resultados mensuales para reconstruir una prueba continua, pues cada ejecución inicia con su propio estado y depósito.

El Diario advierte de **8 minutos sin ticks reales** en agosto de 2026 y uso de generación de ticks para esos huecos en las ejecuciones que abarcan ese intervalo. Por tanto, esos resultados no deben describirse como procedentes exclusivamente de ticks reales completos.

No se han consolidado ni validado en este cierre drawdown, profit factor, tasa de acierto, distribución de R, sensibilidad completa a costes, pruebas fuera de muestra o significancia estadística. No se inventan estos indicadores a partir del saldo final. No se ha demostrado una ventaja suficiente para justificar uso real; esto tampoco equivale a demostrar que toda configuración posible sea necesariamente perdedora.

## Hallazgos técnicos y diagnóstico

- Se corrigieron los reintentos excesivos de gestión mediante esperas técnicas de 5 segundos y control de duplicados, sin añadir filtros horarios. La reducción a 12 rechazos por minuto corresponde a una prueba simulada de mercado cerrado, no a un resultado de rentabilidad ni a una nueva ejecución MT5.
- Se corrigió el resumen de PnL para esperar a reconciliar los deals y conservar la identidad de la idea. El caso de investigación con dos compras de 0.03 en 4246.68 y 4239.73, cerradas en 4234.89, equivale a -49.89 USD para contrato de 100 onzas y sin otros costes. Las pruebas auxiliares reproducen la suma y el cierre en el mismo segundo; no se trata de un resultado agregado de la estrategia.
- Se verificaron en el Diario las señales CLOSED_BAR evaluadas después de pausas: 2026-07-06 01:00:02 sobre la vela de 2026-07-03 19:55; 2026-07-22 01:00 sobre la de 2026-07-21 23:55; y 2026-10-27 01:00 sobre la de 2026-10-26 23:55. Los retrasos desde el cierre nominal fueron 190802, 3600 y 3600 segundos. Los tres envíos de E1 fueron rechazados por `Market closed`, con `entradas=0`. No se añadió filtro de antigüedad ni descarte por horario.
- MFE/MAE monetarios conjuntos se añadieron como diagnóstico, incluyendo realizado y flotante reconciliados. Su comportamiento está cubierto por pruebas auxiliares; no se dispone aquí de un análisis agregado de MFE/MAE de un backtest de la última versión.
- El Probador puede liquidar posiciones al finalizar el periodo sin generar el `EXIT` habitual del EA. El saldo final del probador y una suma incompleta de logs EXIT no son intercambiables; también hay que revisar las liquidaciones finales y los resúmenes pendientes.

## Estado de verificación

| Tipo de evidencia | Estado al cerrar |
| --- | --- |
| Revisión estática | Documentadas las reglas y la conservación de la operativa al añadir diagnóstico |
| Suite offline | Última ejecución registrada: 14 tests pasados; Python/unittest, fragmentos actuales compilados con C++ y respuestas MT5 simuladas |
| Compilación MQL5 | El usuario reportó compilación de una versión anterior; la última versión con MFE/MAE no se compiló desde este entorno por el bloqueo de interoperabilidad Windows/WSL |
| Backtests MT5 | Existen las ejecuciones históricas de la tabla; no validan automáticamente el fuente actual ni las correcciones posteriores |
| Operación en real | No realizada ni validada; el EA mantiene su restricción al Probador |

Las pruebas auxiliares verifican escenarios funcionales y regresiones. No constituyen compilación MQL5, un backtest completo ni demostración de rentabilidad.

## Pendientes explícitos

1. **Netting en MT5:** validar consolidación E1/E2, SL/TP comunes, riesgo y PnL; mezcla con intervenciones ajenas; cancelación de pendientes propias y protección de la posición mezclada. Los mocks no sustituyen esta validación.
2. **Reinicios en MT5:** validar limpieza limitada a símbolo/Magic, exposición residual, confirmaciones tardías, reconstrucción del enfriamiento y protección de operaciones ajenas. Los extremos MFE/MAE anteriores a una reinicialización no se reconstruyen.
3. Compilar el fuente final en MetaEditor y contrastar advertencias; comprobar en el probador las correcciones de reintentos, reconciliación y diagnóstico de la versión conservada.
4. Si se retoma la investigación, preparar comparaciones reproducibles y fuera de muestra, conservar binarios/entradas/informes y evaluar costes, calidad de datos y riesgo antes de extraer nuevas conclusiones.

El experimento queda cerrado documentalmente con estos pendientes abiertos. Se conservan sin cambios el EA y la documentación existente. No se realizó commit ni push.
