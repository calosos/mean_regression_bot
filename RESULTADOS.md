# Resultados de investigación — XAUUSD M5

Fecha de cierre de sesión: 6 de noviembre de 2026.
Estado: investigación en pausa; ninguna variante se considera validada para operar en real.

## Objetivo y alcance

Investigar entradas de regreso a la media y sus salidas mediante un EA monolítico MQL5. El objetivo de investigación del usuario es encontrar un rendimiento del orden de 4–6% mensual con consistencia; los resultados actuales no lo demuestran.

Las etiquetas V1–V8 identifican hipótesis de investigación, no versiones del playbook original. Este documento resume los informes y diarios revisados durante la sesión; no sustituye los archivos originales ni una auditoría del código.

## Hipótesis V1–V8

| Versión | Propuesta | Resultado observado y decisión |
| --- | --- | --- |
| V1 — RSI | Sustituir Stochastic por RSI14, niveles 30/70, manteniendo Bollinger. | No se identificó una mejora suficiente para elegirla como base. No se consolidan cifras aquí porque no quedaron disponibles en el resumen de esta sesión. |
| V2 — Sin oscilador | Cierre fuera de Bollinger, posterior cierre dentro y entrada en la siguiente vela. Una sola entrada; objetivo SMA20 dinámico. | Base BB_REENTRY de los experimentos posteriores. Resultados dependientes del período. |
| V3 — MACD | Confirmar recuperación del histograma MACD12/26/9, sin exigir cruce completo. | Julio–octubre +298.61 USD; abril–junio −165.07 USD. Redujo entradas sin sostener la mejora. Archivada. |
| V4 — ADX | ADX14 <25, <20, o <25 y descendiendo. | ADX <20 fue la variante más interesante: enero–octubre +586.15 USD, DD 0.89%, 78 operaciones; 2025 +243.71 USD, DD 2.44%, 80 operaciones. Rendimiento insuficiente para el objetivo planteado. |
| V5 — Ancho Bollinger | BBW no creciente, comienzo de contracción, o debajo del percentil70 de 100 velas anteriores. | Julio–octubre: no creciente +132.26 USD con 22 operaciones; percentil70 +508.76 USD con 308. Inicio de contracción omitido por decisión, no descartado mediante backtest. |
| V6 — Mechas | Toque de banda, cierre dentro y mecha mínima de 40%, 50% o 60% del rango. | Julio–octubre: −1,855.84 / −1,611.92 / −1,641.78 USD, respectivamente. Archivada. |
| V7 — Desviación ATR | D=(Close−SMA20)/ATR14; preparación por sobreextensión y entrada tras regreso confirmado. | Umbrales 1.5 / 2 / 2.5 / 3 ATR: −2,804.11 / −2,866.33 / −2,260.15 / −684.10 USD en julio–octubre. Todas negativas. |
| V8 — Referencia | Comparar SMA20, EMA20 y VWAP con reglas de entrada constantes. | Pendiente. No se ejecutó una comparación directa SMA/EMA/VWAP. Las pruebas de salida siguientes son un bloque separado. |

## Condiciones comunes de las pruebas de salida

- XAUUSD M5, Axi-US50-Demo, depósito inicial 25,000 USD.
- Modelado: cada tick basado en ticks reales; informes revisados de S1–S4 con calidad 100%.
- Estrategia BB_REENTRY, una sola entrada, riesgo 0.25% sobre base fija de 25,000 USD: presupuesto 62.50 USD por idea antes de redondeos y ejecución.
- SL inicial: 2 ATR; ATR14 congelado al entrar, tomado de la vela de confirmación cerrada.
- Bollinger: período20, desviación2.5.
- Filtros ADX, MACD y BBW apagados.
- Protección de fin de semana activada: bloquear nuevas entradas 60 minutos antes y solicitar cierre 30 minutos antes del cierre semanal según sesiones del símbolo.
- Apalancamiento1:30; ejecución ideal, sin optimización.
- Conservación de las reglas de reconciliación y enfriamiento.

El presupuesto calculado no garantiza una pérdida máxima exacta: hubo ejecuciones con pérdidas superiores por condiciones de mercado. El informe de banda opuesta julio–octubre contiene una pérdida de −178.84 USD cuya causa no quedó explicada con su diario.

## Experimentos de salida

- S0: cerrar todo en SMA20 de shift=1; objetivo actualizado con cada nueva vela.
- S1: objetivo dinámico E1 + 0.5 × (SMA20[1] − E1), usando E1 ejecutado fijo.
- S2: banda opuesta dinámica de shift=1: superior para compras, inferior para ventas.
- S3: TP fijo de 2 ATR congelados desde E1; SL también de 2 ATR.
- S4: cerrar 50% al alcanzar SMA20 dinámica; tras confirmar el parcial, gestionar el remanente con trailing de 1 ATR congelado desde el mejor Bid/Ask observado a partir de esa confirmación. SL solo puede ajustarse para reducir riesgo. Si el volumen no permite una división válida, cerrar todo en SMA20.

| Salida | Enero–marzo | Abril–junio | Julio–octubre | Suma de ejecuciones separadas | Rendimiento sobre 25,000 USD |
| --- | ---: | ---: | ---: | ---: | ---: |
| S0 — SMA20 | −838.11 | +584.60 | +727.94 | +474.43 USD | +1.90% |
| S1 — Mitad hacia SMA20 | Sin probar | Sin probar | −139.54 | No comparable | −0.56% en julio–octubre |
| S2 — Banda opuesta | −109.15 | +479.99 | +2,612.87 | +2,983.71 USD | +11.93% |
| S3 — TP fijo 2 ATR | +10.82 | −155.95 | +2,176.98 | +2,031.85 USD | +8.13% |
| S4 — Parcial y trailing | −647.23 | +638.40 | +1,369.68 | +1,360.85 USD | +5.44% |

Las fechas usadas fueron [2026.01.01, 2026.04.01), [2026.04.01, 2026.07.01) y [2026.07.01, 2026.11.01). La suma no sustituye un backtest continuo: reiniciar el EA puede afectar operaciones en los límites, estado y enfriamiento. No deben sumarse los drawdowns ni interpretarse estos rendimientos como tasas mensuales estables.

### Drawdown máximo de equidad por ejecución

| Salida | Enero–marzo | Abril–junio | Julio–octubre |
| --- | ---: | ---: | ---: |
| S0 — SMA20 | 3.82% | 2.72% | 5.02% |
| S1 — Mitad SMA20 | — | — | 3.55% |
| S2 — Banda opuesta | 3.44% | 4.83% | 5.75% |
| S3 — TP fijo 2 ATR | 3.09% | 4.47% | 3.53% |
| S4 — Parcial y trailing | 3.20% | 2.68% | 4.47% |

S2 enero–marzo se repitió a1:30 tras detectar una ejecución a1:400. Beneficio, operaciones y drawdown fueron idénticos: −109.15 USD, 227 operaciones, DD3.44%.

## Revisión del diario S4 julio–octubre

- INIT confirmó BB_REENTRY, señal CLOSED_BAR y salida EXIT_HALF_SMA20_TRAIL_ATR.
- 480 entradas/ideas y 480 registros EXIT, sin duplicación de esos registros por idea.
- 305 parciales confirmados, sin confirmaciones duplicadas por idea.
- 23,062 actualizaciones de trailing; no se encontraron actualizaciones antes de confirmar el parcial ni movimientos que aflojaran el SL.
- La distancia del trailing registrada fue compatible con 1 ATR congelado dentro de la tolerancia de normalización examinada.
- 10 rechazos de parcial por mercado cerrado en una idea, con reintentos y posterior confirmación.
- Suma de PnL realizado por idea: +1,369.68 USD, coincidente con el informe.
- Las 785 operaciones del informe incluyen los cierres parciales: no son 785 ideas independientes. Por la misma razón, la tasa de acierto del informe S4 no es directamente comparable con una tasa por idea de estrategias sin parciales.

Estos controles describen lo observado en una ejecución hedging. No prueban todos los escenarios de error ni el comportamiento en netting.

## Conclusiones y límites

1. Cambiar la salida afecta al rendimiento. S2 obtuvo la mayor suma y S3 fue mejor en beneficio/drawdown durante julio–octubre, sin demostrar superioridad estable en todos los períodos.
2. S4 mejoró frente a SMA20 durante abril–junio y julio–octubre, pero perdió en enero–marzo.
3. El beneficio de las variantes con mayor rendimiento se concentró en julio–octubre. No se demostró el objetivo mensual buscado.
4. Muchas variantes se probaron sobre los mismos períodos. Son resultados exploratorios; ninguno de esos períodos constituye ya una validación independiente para seleccionar variantes posteriores.
5. V8 sigue pendiente. No debe registrarse como probada ni fallida.
6. Los informes tienen las condiciones de costes de sus ejecuciones; no se ha completado una evaluación realista de costes y ejecución. Se decidió posponer ese bloque hasta observar una ventaja suficiente, sin confundir los resultados con rentabilidad en real.
7. Se conserva el EA y se pausa la búsqueda de nuevas combinaciones. No se justifica aumentar riesgo con esta evidencia.

## Próxima sesión: diagnóstico, sin cambiar reglas

Duración propuesta: máximo 2 horas.

### Base fija de diagnóstico

BB_REENTRY; una entrada; SL2 ATR; TP fijo2 ATR; riesgo0.25%; base25,000 USD; ADX/MACD/BBW apagados; protección semanal60/30; XAUUSD M5; ticks reales; apalancamiento1:30; logs detallados.

Se elige por simplicidad para estudiar las entradas; no se considera la variante ganadora ni validada.

### Material necesario

- Informe y diario de una ejecución continua del 1 de enero al 1 de noviembre de2026 con esa configuración.
- Si los registros no contienen suficientes campos, completar únicamente instrumentación, sin modificar decisiones de trading.

### Preguntas a responder

- MFE y MAE por idea, en USD y en R, con 1R igual al riesgo inicial calculado de esa idea tras normalizar precio y volumen.
- Cuántas ideas alcanzaron +0.5R o +1R y terminaron con resultado negativo.
- Distribución de resultados por mes, dirección y sesiones definidas antes de comparar. Para asignar sesiones, documentar hora del servidor y cambios de huso; no deducir hora de México solo desde el timestamp del log.
- Si se comparan órdenes de eventos (por ejemplo, alcanzar +1R antes de −1R), registrar los instantes: los máximos MFE/MAE por sí solos no prueban ese orden.

### Decisión de cierre

Proponer una sola hipótesis si aparece un patrón repetido y con una explicación concreta. Evaluarla después en un período reservado que no se haya utilizado para diseñarla. Si no aparece, archivar esta familia y estudiar otra estrategia sin seguir agregando filtros por ensayo y error.

## Estado operativo

Los informes provienen de backtesting; el diario citado fue revisado, no se ejecutó aquí una nueva compilación o simulación. No se efectuaron operaciones reales ni se solicitó commit o push durante este cierre.
