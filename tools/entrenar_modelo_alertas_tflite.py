from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

import numpy as np
import pandas as pd
import tensorflow as tf


REGRESSION_LABELS = [
    "label_demanda_bidones",
    "label_demanda_fundas",
    "label_demanda_total_unidades",
    "label_carga_recomendada_bidones",
    "label_carga_recomendada_fundas",
]

CLASSIFICATION_LABELS = [
    "label_alerta_stock_bajo",
    "label_venta_alta_inesperada",
]

LEAKAGE_COLUMNS = [
    "bidones_vendidos_total",
    "fundas_vendidas_total",
    "vacios_devueltos_total",
    "bidones_cargados_total",
    "fundas_cargadas_total",
    "viajes_total",
    "ingreso_total",
    "pedidos_grandes_fundas",
    "distribuidora",
    "externo",
    "vendedor",
]


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    tf.random.set_seed(seed)


def load_dataset(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    if "fecha" in df.columns:
        df["fecha"] = pd.to_datetime(df["fecha"])
    else:
        # The numeric CSV intentionally does not keep fecha; rebuild it from the known range.
        df.insert(0, "fecha", pd.date_range("2023-01-01", periods=len(df), freq="D"))
    return df.sort_values("fecha").reset_index(drop=True)


def feature_columns(df: pd.DataFrame) -> list[str]:
    excluded = set(REGRESSION_LABELS + CLASSIFICATION_LABELS + LEAKAGE_COLUMNS)
    excluded.update(["fecha", "dia_semana", "fuente_dato", "requiere_revision"])
    columns = [column for column in df.columns if column not in excluded]
    return [column for column in columns if pd.api.types.is_numeric_dtype(df[column])]


def split_chronologically(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    train = df[df["fecha"] < "2025-10-01"]
    validation = df[(df["fecha"] >= "2025-10-01") & (df["fecha"] < "2026-01-01")]
    test = df[df["fecha"] >= "2026-01-01"]
    return train, validation, test


def standardize(train: pd.DataFrame, validation: pd.DataFrame, test: pd.DataFrame, columns: list[str]):
    mean = train[columns].mean()
    std = train[columns].std().replace(0, 1)
    return (
        ((train[columns] - mean) / std).to_numpy(np.float32),
        ((validation[columns] - mean) / std).to_numpy(np.float32),
        ((test[columns] - mean) / std).to_numpy(np.float32),
        mean,
        std,
    )


def standardize_labels(train: pd.DataFrame, validation: pd.DataFrame, test: pd.DataFrame):
    mean = train[REGRESSION_LABELS].mean()
    std = train[REGRESSION_LABELS].std().replace(0, 1)
    return (
        ((train[REGRESSION_LABELS] - mean) / std).to_numpy(np.float32),
        ((validation[REGRESSION_LABELS] - mean) / std).to_numpy(np.float32),
        ((test[REGRESSION_LABELS] - mean) / std).to_numpy(np.float32),
        mean,
        std,
    )


def build_model(input_size: int) -> tf.keras.Model:
    inputs = tf.keras.Input(shape=(input_size,), name="features")
    x = tf.keras.layers.Dense(96, activation="relu")(inputs)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.Dropout(0.12)(x)
    x = tf.keras.layers.Dense(64, activation="relu")(x)
    x = tf.keras.layers.Dense(32, activation="relu")(x)

    regression = tf.keras.layers.Dense(
        len(REGRESSION_LABELS),
        activation="linear",
        name="regression_output",
    )(x)
    classification = tf.keras.layers.Dense(
        len(CLASSIFICATION_LABELS),
        activation="sigmoid",
        name="classification_output",
    )(x)

    model = tf.keras.Model(inputs=inputs, outputs=[regression, classification])
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss=["mse", "binary_crossentropy"],
        loss_weights=[1.0, 0.65],
        metrics=[
            [tf.keras.metrics.MeanAbsoluteError(name="mae")],
            [tf.keras.metrics.BinaryAccuracy(name="accuracy")],
        ],
    )
    return model


def denormalize_regression(values: np.ndarray, mean: pd.Series, std: pd.Series) -> np.ndarray:
    return values * std.to_numpy(np.float32) + mean.to_numpy(np.float32)


def evaluate_model(
    model: tf.keras.Model,
    x_test: np.ndarray,
    y_reg_test_scaled: np.ndarray,
    y_cls_test: np.ndarray,
    reg_mean: pd.Series,
    reg_std: pd.Series,
) -> dict:
    pred_reg_scaled, pred_cls = model.predict(x_test, verbose=0)
    y_reg = denormalize_regression(y_reg_test_scaled, reg_mean, reg_std)
    pred_reg = np.maximum(0, denormalize_regression(pred_reg_scaled, reg_mean, reg_std))
    pred_cls_binary = (pred_cls >= 0.5).astype(np.int32)

    metrics: dict[str, object] = {
        "regression_mae": {},
        "classification": {},
    }
    for index, label in enumerate(REGRESSION_LABELS):
        metrics["regression_mae"][label] = round(float(np.mean(np.abs(pred_reg[:, index] - y_reg[:, index]))), 4)

    for index, label in enumerate(CLASSIFICATION_LABELS):
        truth = y_cls_test[:, index].astype(np.int32)
        pred = pred_cls_binary[:, index]
        tp = int(((truth == 1) & (pred == 1)).sum())
        tn = int(((truth == 0) & (pred == 0)).sum())
        fp = int(((truth == 0) & (pred == 1)).sum())
        fn = int(((truth == 1) & (pred == 0)).sum())
        accuracy = (tp + tn) / max(len(truth), 1)
        precision = tp / max(tp + fp, 1)
        recall = tp / max(tp + fn, 1)
        metrics["classification"][label] = {
            "accuracy": round(float(accuracy), 4),
            "precision": round(float(precision), 4),
            "recall": round(float(recall), 4),
            "tp": tp,
            "tn": tn,
            "fp": fp,
            "fn": fn,
        }
    return metrics


def convert_to_tflite(model: tf.keras.Model, output_path: Path) -> None:
    input_size = int(model.inputs[0].shape[-1])

    @tf.function
    def inferir(features):
        return model(features, training=False)

    concrete_func = inferir.get_concrete_function(
        tf.TensorSpec([1, input_size], tf.float32, name="features")
    )
    converter = tf.lite.TFLiteConverter.from_concrete_functions(
        [concrete_func],
        model,
    )
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    output_path.write_bytes(tflite_model)


def tflite_output_order(model_path: Path) -> list[dict]:
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    details = []
    for index, output in enumerate(interpreter.get_output_details()):
        shape = [int(value) for value in output["shape"]]
        labels = REGRESSION_LABELS if shape[-1] == len(REGRESSION_LABELS) else CLASSIFICATION_LABELS
        kind = "regression_output" if shape[-1] == len(REGRESSION_LABELS) else "classification_output"
        details.append(
            {
                "index": index,
                "tensor_index": int(output["index"]),
                "name": output["name"],
                "shape": shape,
                "kind": kind,
                "labels": labels,
            }
        )
    return details


def write_metadata(
    path: Path,
    feature_names: list[str],
    feature_mean: pd.Series,
    feature_std: pd.Series,
    reg_mean: pd.Series,
    reg_std: pd.Series,
    metrics: dict,
    dataset_path: Path,
    output_order: list[dict],
) -> None:
    entrada = {
        "nombre": "caracteristicas",
        "forma": [1, len(feature_names)],
        "nombres_caracteristicas": feature_names,
        "normalizacion": {
            "media": [round(float(feature_mean[name]), 8) for name in feature_names],
            "desviacion": [round(float(feature_std[name]), 8) for name in feature_names],
            "formula": "(valor - media) / desviacion",
        },
    }
    salida_regresion = {
        "etiquetas": REGRESSION_LABELS,
        "desnormalizacion": {
            "media": [round(float(reg_mean[name]), 8) for name in REGRESSION_LABELS],
            "desviacion": [round(float(reg_std[name]), 8) for name in REGRESSION_LABELS],
            "formula": "prediccion * desviacion + media",
        },
    }
    salida_clasificacion = {
        "etiquetas": CLASSIFICATION_LABELS,
        "umbral": 0.5,
        "descripcion": "Probabilidades entre 0 y 1.",
    }
    orden_salidas = [
        {
            "indice": item["index"],
            "indice_tensor": item["tensor_index"],
            "nombre": item["name"],
            "forma": item["shape"],
            "tipo": "regresion" if item["kind"] == "regression_output" else "clasificacion",
            "etiquetas": item["labels"],
        }
        for item in output_order
    ]
    metadata = {
        "nombre_modelo": "modelo_alertas_agua_milena_v1",
        "dataset": str(dataset_path),
        "entrada": entrada,
        "salidas": {
            "orden_salidas_tflite": orden_salidas,
            "salida_regresion": salida_regresion,
            "salida_clasificacion": salida_clasificacion,
        },
        "input": {
            "name": "features",
            "shape": [1, len(feature_names)],
            "feature_names": feature_names,
            "normalization": {
                "mean": [round(float(feature_mean[name]), 8) for name in feature_names],
                "std": [round(float(feature_std[name]), 8) for name in feature_names],
                "formula": "(value - mean) / std",
            },
        },
        "outputs": {
            "tflite_output_order": output_order,
            "regression_output": {
                "labels": REGRESSION_LABELS,
                "denormalization": {
                    "mean": [round(float(reg_mean[name]), 8) for name in REGRESSION_LABELS],
                    "std": [round(float(reg_std[name]), 8) for name in REGRESSION_LABELS],
                    "formula": "prediction * std + mean",
                },
            },
            "classification_output": {
                "labels": CLASSIFICATION_LABELS,
                "threshold": 0.5,
                "description": "Probabilidades entre 0 y 1.",
            },
        },
        "metrics": metrics,
    }
    path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Entrena y exporta el modelo completo de alertas a TensorFlow Lite.")
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path("docs/datasets/alertas_tensorflow_entrenamiento.csv"),
    )
    parser.add_argument("--out-dir", type=Path, default=Path("modelos/alertas_agua_milena"))
    parser.add_argument("--asset-dir", type=Path, default=Path("assets/modelos"))
    parser.add_argument("--epochs", type=int, default=240)
    parser.add_argument("--seed", type=int, default=20260503)
    args = parser.parse_args()

    set_seed(args.seed)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    args.asset_dir.mkdir(parents=True, exist_ok=True)

    df = load_dataset(args.dataset)
    features = feature_columns(df)
    train, validation, test = split_chronologically(df)
    x_train, x_validation, x_test, feature_mean, feature_std = standardize(train, validation, test, features)
    y_reg_train, y_reg_validation, y_reg_test, reg_mean, reg_std = standardize_labels(train, validation, test)
    y_cls_train = train[CLASSIFICATION_LABELS].to_numpy(np.float32)
    y_cls_validation = validation[CLASSIFICATION_LABELS].to_numpy(np.float32)
    y_cls_test = test[CLASSIFICATION_LABELS].to_numpy(np.float32)

    model = build_model(len(features))
    callbacks = [
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=28, restore_best_weights=True),
        tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", patience=10, factor=0.5, min_lr=0.00005),
    ]
    history = model.fit(
        x_train,
        [y_reg_train, y_cls_train],
        validation_data=(
            x_validation,
            [y_reg_validation, y_cls_validation],
        ),
        epochs=args.epochs,
        batch_size=32,
        verbose=0,
        callbacks=callbacks,
    )

    metrics = evaluate_model(model, x_test, y_reg_test, y_cls_test, reg_mean, reg_std)
    metrics["rows"] = {
        "train": int(len(train)),
        "validation": int(len(validation)),
        "test": int(len(test)),
    }
    metrics["epochs_trained"] = len(history.history["loss"])
    metrics["feature_count"] = len(features)

    keras_path = args.out_dir / "modelo_alertas_agua_milena.keras"
    tflite_path = args.out_dir / "modelo_alertas_agua_milena.tflite"
    metadata_path = args.out_dir / "metadatos_alertas_agua_milena.json"
    metrics_path = args.out_dir / "metricas_entrenamiento.json"

    model.save(keras_path)
    convert_to_tflite(model, tflite_path)
    output_order = tflite_output_order(tflite_path)
    write_metadata(metadata_path, features, feature_mean, feature_std, reg_mean, reg_std, metrics, args.dataset, output_order)
    metrics_path.write_text(json.dumps(metrics, indent=2, ensure_ascii=False), encoding="utf-8")

    (args.asset_dir / tflite_path.name).write_bytes(tflite_path.read_bytes())
    (args.asset_dir / metadata_path.name).write_text(metadata_path.read_text(encoding="utf-8"), encoding="utf-8")

    print(f"Modelo Keras: {keras_path.resolve()}")
    print(f"Modelo TFLite: {tflite_path.resolve()}")
    print(f"Assets Flutter: {args.asset_dir.resolve()}")
    print(json.dumps(metrics, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
