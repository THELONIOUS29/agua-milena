# Modelo TensorFlow Lite de alertas

Modelo principal para Flutter:

- `assets/modelos/modelo_alertas_agua_milena.tflite`
- `assets/modelos/metadatos_alertas_agua_milena.json`

Script de entrenamiento:

- `tools/entrenar_modelo_alertas_tflite.py`

Dataset usado:

- `docs/datasets/alertas_tensorflow_entrenamiento.csv`

## Que predice

Salida de regresion:

- `label_demanda_bidones`
- `label_demanda_fundas`
- `label_demanda_total_unidades`
- `label_carga_recomendada_bidones`
- `label_carga_recomendada_fundas`

Salida de clasificacion:

- `label_alerta_stock_bajo`
- `label_venta_alta_inesperada`

## Entrada del modelo

El modelo recibe 28 features numericas. El orden exacto y la normalizacion estan en:

- `assets/modelos/metadatos_alertas_agua_milena.json`

Antes de invocar el modelo en Flutter, cada feature debe normalizarse asi:

```text
valor_normalizado = (valor - media) / desviacion
```

Despues de recibir la salida de regresion, cada prediccion debe desnormalizarse asi:

```text
valor_real = prediccion * desviacion + media
```

La salida de clasificacion ya viene como probabilidad de 0 a 1.

## Orden de salidas TFLite

No asumir el orden manualmente. Leer `salidas.orden_salidas_tflite` en el metadata. En la exportacion actual:

- salida `[1, 5]`: regresion
- salida `[1, 2]`: clasificacion

## Metricas actuales

El reporte de metricas se genera de forma local al reentrenar el modelo y no es necesario para que Flutter ejecute las alertas.

Resumen de prueba:

- MAE demanda bidones: ~16.80
- MAE demanda fundas: ~13.51
- MAE demanda total: ~26.61
- Accuracy stock bajo: ~0.87
- Accuracy venta alta inesperada: ~0.87

## Reentrenamiento con nuevas ventas

El modelo no se reentrena dentro de Flutter. La app debe guardar cada venta nueva en Supabase con fecha, vendedor, canal, bidones vendidos, fundas vendidas, vacios devueltos, cargas e ingreso. Periodicamente se exportan esas ventas reales, se anexan al dataset de entrenamiento y se ejecuta:

```powershell
python tools\entrenar_modelo_alertas_tflite.py --dataset docs\datasets\alertas_tensorflow_entrenamiento.csv --out-dir modelos\alertas_agua_milena --asset-dir assets\modelos
```

Luego se reemplazan estos assets:

- `assets/modelos/modelo_alertas_agua_milena.tflite`
- `assets/modelos/metadatos_alertas_agua_milena.json`

Asi la siguiente version de la app usa el modelo actualizado.
