from __future__ import annotations

import argparse
import difflib
import re
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

import pandas as pd
import pypdfium2 as pdfium
from PIL import ImageEnhance, ImageOps
from rapidocr_onnxruntime import RapidOCR


DAY_ALIASES = {
    "lunes": "lunes",
    "lones": "lunes",
    "lonesi": "lunes",
    "martes": "martes",
    "marte": "martes",
    "mante": "martes",
    "miercoles": "miercoles",
    "miereoks": "miercoles",
    "miercole": "miercoles",
    "miercolesl": "miercoles",
    "jueves": "jueves",
    "juebes": "jueves",
    "dueves": "jueves",
    "viernes": "viernes",
    "viennes": "viernes",
    "viennes": "viernes",
    "vienhe": "viernes",
    "sabado": "sabado",
    "sabedo": "sabado",
    "saba": "sabado",
    "domingo": "domingo",
}

DAY_NUM = {
    "lunes": 1,
    "martes": 2,
    "miercoles": 3,
    "jueves": 4,
    "viernes": 5,
    "sabado": 6,
    "domingo": 7,
}

PRODUCT_ALIASES = {
    "bidones": ["bidon", "bido", "biedon", "bidou", "bid0", "bicon"],
    "fundas": ["funda", "funda", "fndas", "fund", "fona", "frenda", "feenda"],
    "vacios": ["vacio", "vacios", "vaci", "uacio", "uauo", "uaco", "vace"],
}


@dataclass
class ParsedExpression:
    raw: str
    inicio: int | None
    entradas: int | None
    salidas: int | None
    final_estimado: int | None
    tokens: str


def strip_accents(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    return "".join(ch for ch in value if not unicodedata.combining(ch))


def normalize_text(value: str) -> str:
    value = strip_accents(value).lower()
    value = value.replace("=", " = ")
    value = re.sub(r"[^a-z0-9+\-.,= ]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def detect_day(text: str) -> str | None:
    normalized = normalize_text(text)
    words = re.findall(r"[a-z]+", normalized)
    for word in words[:4]:
        if word in DAY_ALIASES:
            return DAY_ALIASES[word]
        for alias, day in DAY_ALIASES.items():
            if len(word) >= 4 and (word.startswith(alias[:4]) or alias.startswith(word[:4])):
                return day
            if len(word) >= 5 and difflib.SequenceMatcher(None, word, alias).ratio() >= 0.72:
                return day
    return None


def detect_product(text: str) -> str | None:
    normalized = normalize_text(text)
    for product, aliases in PRODUCT_ALIASES.items():
        if any(alias in normalized for alias in aliases):
            return product
    return None


def parse_expression(text: str) -> ParsedExpression:
    raw = text.strip()
    cleaned = normalize_text(raw)
    if "=" in cleaned:
        cleaned = cleaned.split("=", 1)[1]
        if "=" in cleaned:
            cleaned = cleaned.split("=", 1)[0]
    cleaned = cleaned.replace(",", ".")
    cleaned = re.sub(r"\d+\.\d+", " ", cleaned)
    tokens = re.findall(r"([+\-]?)\s*(\d+)", cleaned)
    signed_values: list[int] = []
    for sign, digits in tokens:
        value = normalize_count_token(digits, signed=bool(sign))
        if value is None:
            continue
        if sign == "-":
            value *= -1
        signed_values.append(value)

    if not signed_values:
        return ParsedExpression(raw, None, None, None, None, "")

    inicio = abs(signed_values[0])
    entradas = 0
    salidas = 0
    for value in signed_values[1:]:
        if value >= 0:
            entradas += value
        else:
            salidas += abs(value)

    final_estimado = inicio + entradas - salidas
    return ParsedExpression(raw, inicio, entradas, salidas, final_estimado, " ".join(map(str, signed_values)))


def normalize_count_token(digits: str, signed: bool) -> int | None:
    digits = re.sub(r"\D+", "", digits)
    if not digits:
        return None
    value = int(digits)
    if value <= 60:
        return value

    # Handwritten OCR often glues a count to a note or an amount: -5177 means -5,
    # 31127478 means 31 + noise. Keep a plausible inventory/count prefix.
    candidates: list[int] = []
    for length in (2, 1):
        if len(digits) >= length:
            candidate = int(digits[:length])
            if 0 <= candidate <= 60:
                candidates.append(candidate)
    if not candidates:
        return None
    if signed and candidates[0] > 35 and len(candidates) > 1:
        return candidates[1]
    return candidates[0]


def money_values(text: str) -> list[str]:
    values = re.findall(r"\b\d{1,3}[,.]\d{1,2}\b", text)
    return [value.replace(".", ",") for value in values]


def status_from_text(text: str) -> str | None:
    normalized = normalize_text(text)
    if "pagad" in normalized or "paga" in normalized:
        return "pagado"
    if "abon" in normalized:
        return "abono"
    if "devol" in normalized:
        return "devuelto"
    if "falt" in normalized:
        return "faltante"
    return None


def render_pages(pdf_path: Path, image_dir: Path, scale: float) -> int:
    image_dir.mkdir(parents=True, exist_ok=True)
    pdf = pdfium.PdfDocument(str(pdf_path))
    for index in range(len(pdf)):
        page_number = index + 1
        target = image_dir / f"page_{page_number:03d}_enhanced.png"
        if target.exists():
            continue
        bitmap = pdf[index].render(scale=scale)
        image = bitmap.to_pil().convert("RGB")
        gray = ImageOps.grayscale(image)
        gray = ImageOps.autocontrast(gray, cutoff=1)
        gray = ImageEnhance.Contrast(gray).enhance(1.7)
        gray.save(target)
    return len(pdf)


def run_ocr(image_dir: Path, total_pages: int) -> tuple[list[dict], list[dict]]:
    ocr = RapidOCR()
    raw_rows: list[dict] = []
    line_rows: list[dict] = []

    for page_number in range(1, total_pages + 1):
        image = image_dir / f"page_{page_number:03d}_enhanced.png"
        result, _ = ocr(str(image))
        page_rows: list[dict] = []
        if result:
            for box, text, confidence in result:
                if not text:
                    continue
                xs = [point[0] for point in box]
                ys = [point[1] for point in box]
                row = {
                    "pagina": page_number,
                    "texto": text,
                    "confianza": round(float(confidence), 4),
                    "x1": round(min(xs), 2),
                    "y1": round(min(ys), 2),
                    "x2": round(max(xs), 2),
                    "y2": round(max(ys), 2),
                    "centro_y": round(sum(ys) / len(ys), 2),
                    "centro_x": round(sum(xs) / len(xs), 2),
                }
                if "CamScanner" in text or "Scanned" in text:
                    continue
                raw_rows.append(row)
                page_rows.append(row)

        page_rows.sort(key=lambda item: (item["centro_y"], item["centro_x"]))
        current_line: list[dict] = []
        current_y: float | None = None
        line_number = 0
        for row in page_rows:
            if current_y is None or abs(row["centro_y"] - current_y) <= 34:
                current_line.append(row)
                current_y = row["centro_y"] if current_y is None else (current_y + row["centro_y"]) / 2
            else:
                line_number += 1
                line_rows.append(build_line(page_number, line_number, current_line))
                current_line = [row]
                current_y = row["centro_y"]
        if current_line:
            line_number += 1
            line_rows.append(build_line(page_number, line_number, current_line))

    return raw_rows, line_rows


def build_line(page_number: int, line_number: int, rows: Iterable[dict]) -> dict:
    row_list = sorted(rows, key=lambda item: item["centro_x"])
    text = " ".join(item["texto"] for item in row_list)
    confidences = [item["confianza"] for item in row_list]
    return {
        "pagina": page_number,
        "linea": line_number,
        "texto_linea": text,
        "texto_normalizado": normalize_text(text),
        "confianza_media": round(sum(confidences) / max(len(confidences), 1), 4),
        "x1": min(item["x1"] for item in row_list),
        "y1": min(item["y1"] for item in row_list),
        "x2": max(item["x2"] for item in row_list),
        "y2": max(item["y2"] for item in row_list),
    }


def extract_blocks(line_rows: list[dict], source_pdf: Path) -> tuple[list[dict], list[dict]]:
    ventas: list[dict] = []
    movimientos: list[dict] = []
    current: dict | None = None

    def finish_current() -> None:
        nonlocal current
        if not current:
            return
        current["requiere_revision"] = review_flag(current)
        current["notas_revision"] = review_notes(current)
        ventas.append(current)
        current = None

    for line in sorted(line_rows, key=lambda item: (item["pagina"], item["linea"])):
        text = line["texto_linea"]
        day = detect_day(text)
        product = detect_product(text)
        status = status_from_text(text)
        amounts = money_values(text)

        if day:
            finish_current()
            current = {
                "fuente_pdf": str(source_pdf),
                "pagina": line["pagina"],
                "linea_inicio": line["linea"],
                "fecha": "",
                "dia_semana": day,
                "dia_semana_num": DAY_NUM.get(day),
                "es_fin_semana": 1 if day in {"sabado", "domingo"} else 0,
                "vendedor_detectado": "",
                "bidones_stock_inicio": None,
                "bidones_carga": None,
                "bidones_vendidos_o_salida": None,
                "bidones_final_estimado": None,
                "fundas_stock_inicio": None,
                "fundas_carga": None,
                "fundas_vendidas_o_salida": None,
                "fundas_final_estimado": None,
                "vacios_inicio": None,
                "vacios_recibidos": None,
                "vacios_salida": None,
                "vacios_final_estimado": None,
                "monto_total_raw": "",
                "estado_pago_raw": "",
                "formula_bidones_raw": "",
                "formula_fundas_raw": "",
                "formula_vacios_raw": "",
                "lineas_evidencia": text,
            }
        elif current:
            current["lineas_evidencia"] = f"{current['lineas_evidencia']} | {text}"

        if current and status:
            statuses = [value for value in current["estado_pago_raw"].split(";") if value]
            if status not in statuses:
                statuses.append(status)
            current["estado_pago_raw"] = ";".join(statuses)

        if current and amounts:
            existing = [value for value in current["monto_total_raw"].split(";") if value]
            current["monto_total_raw"] = ";".join(existing + amounts)

        if current and product:
            parsed = parse_expression(text)
            movimientos.append(
                {
                    "fuente_pdf": str(source_pdf),
                    "pagina": line["pagina"],
                    "linea": line["linea"],
                    "dia_semana": current["dia_semana"],
                    "producto": product,
                    "formula_raw": parsed.raw,
                    "tokens_detectados": parsed.tokens,
                    "stock_inicio_estimado": parsed.inicio,
                    "entradas_estimadas": parsed.entradas,
                    "salidas_estimadas": parsed.salidas,
                    "stock_final_estimado": parsed.final_estimado,
                    "confianza_linea": line["confianza_media"],
                    "requiere_revision": 1 if line["confianza_media"] < 0.72 or parsed.inicio is None else 0,
                }
            )
            prefix = product
            current[f"formula_{prefix}_raw"] = parsed.raw
            if product == "bidones":
                current["bidones_stock_inicio"] = parsed.inicio
                current["bidones_carga"] = parsed.entradas
                current["bidones_vendidos_o_salida"] = parsed.salidas
                current["bidones_final_estimado"] = parsed.final_estimado
            elif product == "fundas":
                current["fundas_stock_inicio"] = parsed.inicio
                current["fundas_carga"] = parsed.entradas
                current["fundas_vendidas_o_salida"] = parsed.salidas
                current["fundas_final_estimado"] = parsed.final_estimado
            elif product == "vacios":
                current["vacios_inicio"] = parsed.inicio
                current["vacios_recibidos"] = parsed.entradas
                current["vacios_salida"] = parsed.salidas
                current["vacios_final_estimado"] = parsed.final_estimado

    finish_current()
    return ventas, movimientos


def review_flag(row: dict) -> int:
    required = [
        "dia_semana",
        "bidones_stock_inicio",
        "bidones_vendidos_o_salida",
        "fundas_stock_inicio",
        "fundas_vendidas_o_salida",
    ]
    return 1 if any(row.get(key) in (None, "") for key in required) else 0


def review_notes(row: dict) -> str:
    notes: list[str] = []
    if not row.get("fecha"):
        notes.append("fecha_real_pendiente")
    if row.get("bidones_vendidos_o_salida") is None:
        notes.append("bidones_no_confiables")
    if row.get("fundas_vendidas_o_salida") is None:
        notes.append("fundas_no_confiables")
    if not row.get("monto_total_raw"):
        notes.append("monto_no_detectado")
    return ";".join(notes)


def alert_dataset(ventas: list[dict]) -> list[dict]:
    rows: list[dict] = []
    for row in ventas:
        bidones_salida = row.get("bidones_vendidos_o_salida")
        fundas_salida = row.get("fundas_vendidas_o_salida")
        demanda_total = (bidones_salida or 0) + (fundas_salida or 0)
        rows.append(
            {
                "fuente_pdf": row.get("fuente_pdf"),
                "pagina": row.get("pagina"),
                "fecha": row.get("fecha"),
                "dia_semana_num": row.get("dia_semana_num"),
                "es_fin_semana": row.get("es_fin_semana"),
                "bidones_stock_inicio": row.get("bidones_stock_inicio"),
                "bidones_carga": row.get("bidones_carga"),
                "fundas_stock_inicio": row.get("fundas_stock_inicio"),
                "fundas_carga": row.get("fundas_carga"),
                "vacios_recibidos": row.get("vacios_recibidos"),
                "label_bidones_vendidos": bidones_salida,
                "label_fundas_vendidas": fundas_salida,
                "label_demanda_total": demanda_total if demanda_total else None,
                "label_alerta_carga_alta_heuristica": 1 if (row.get("bidones_carga") or 0) >= 10 else 0,
                "label_alerta_stock_bajo_heuristica": 1
                if row.get("bidones_final_estimado") is not None and row["bidones_final_estimado"] <= 10
                else 0,
                "requiere_revision": row.get("requiere_revision"),
            }
        )
    return rows


def write_excel(
    output_path: Path,
    ventas: list[dict],
    movimientos: list[dict],
    line_rows: list[dict],
    raw_rows: list[dict],
    pdf_path: Path | str,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ventas_df = pd.DataFrame(ventas)
    alertas_df = pd.DataFrame(alert_dataset(ventas))
    movimientos_df = pd.DataFrame(movimientos)
    lineas_df = pd.DataFrame(line_rows)
    raw_df = pd.DataFrame(raw_rows)

    for df in (lineas_df, raw_df):
        if not df.empty and "fuente_pdf" not in df.columns:
            df.insert(0, "fuente_pdf", str(pdf_path))

    readme = pd.DataFrame(
        [
            {
                "campo": "origen",
                "descripcion": str(pdf_path),
            },
            {
                "campo": "advertencia",
                "descripcion": "El PDF es un escaneo manuscrito. Las filas con requiere_revision=1 deben corregirse antes de entrenar TensorFlow.",
            },
            {
                "campo": "recomendacion",
                "descripcion": "Usa ventas_diarias_tf para limpiar fechas y valores; usa alertas_tensorflow_base como tabla inicial de entrenamiento.",
            },
            {
                "campo": "generado_en",
                "descripcion": datetime.now().isoformat(timespec="seconds"),
            },
        ]
    )
    dictionary = pd.DataFrame(
        [
            {"columna": "bidones_stock_inicio", "uso": "feature", "descripcion": "Primer numero detectado en la formula de bidones."},
            {"columna": "bidones_carga", "uso": "feature", "descripcion": "Suma de numeros positivos posteriores al inicial."},
            {"columna": "label_bidones_vendidos", "uso": "label", "descripcion": "Suma de numeros negativos detectados como salida/venta."},
            {"columna": "label_demanda_total", "uso": "label", "descripcion": "Bidones vendidos + fundas vendidas, cuando ambos son confiables."},
            {"columna": "requiere_revision", "uso": "control_calidad", "descripcion": "1 indica que el OCR o el parseo necesita validacion humana."},
        ]
    )
    with pd.ExcelWriter(output_path, engine="openpyxl") as writer:
        readme.to_excel(writer, index=False, sheet_name="README")
        ventas_df.to_excel(writer, index=False, sheet_name="ventas_diarias_tf")
        alertas_df.to_excel(writer, index=False, sheet_name="alertas_tensorflow_base")
        movimientos_df.to_excel(writer, index=False, sheet_name="movimientos_productos")
        lineas_df.to_excel(writer, index=False, sheet_name="ocr_lineas")
        raw_df.to_excel(writer, index=False, sheet_name="ocr_raw")
        dictionary.to_excel(writer, index=False, sheet_name="diccionario")


def combine_workbooks(existing_path: Path, new_path: Path, output_path: Path) -> None:
    if not existing_path.exists():
        return

    previous = {
        sheet: pd.read_excel(existing_path, sheet_name=sheet)
        for sheet in ["README", "ventas_diarias_tf", "movimientos_productos", "ocr_lineas", "ocr_raw"]
    }
    previous_source = previous["README"].loc[
        previous["README"]["campo"].eq("origen"), "descripcion"
    ]
    fallback_source = previous_source.iloc[0] if not previous_source.empty else ""

    for sheet in ["ventas_diarias_tf", "movimientos_productos", "ocr_lineas", "ocr_raw"]:
        if "fuente_pdf" not in previous[sheet].columns:
            previous[sheet].insert(0, "fuente_pdf", fallback_source)

    new = {
        sheet: pd.read_excel(new_path, sheet_name=sheet)
        for sheet in ["ventas_diarias_tf", "movimientos_productos", "ocr_lineas", "ocr_raw"]
    }

    combined_ventas = pd.concat([previous["ventas_diarias_tf"], new["ventas_diarias_tf"]], ignore_index=True)
    combined_movimientos = pd.concat(
        [previous["movimientos_productos"], new["movimientos_productos"]], ignore_index=True
    )
    combined_lineas = pd.concat([previous["ocr_lineas"], new["ocr_lineas"]], ignore_index=True)
    combined_raw = pd.concat([previous["ocr_raw"], new["ocr_raw"]], ignore_index=True)

    ventas_records = combined_ventas.where(pd.notna(combined_ventas), None).to_dict("records")
    movimientos_records = combined_movimientos.where(pd.notna(combined_movimientos), None).to_dict("records")
    lineas_records = combined_lineas.where(pd.notna(combined_lineas), None).to_dict("records")
    raw_records = combined_raw.where(pd.notna(combined_raw), None).to_dict("records")
    sources = sorted(
        str(value)
        for value in combined_ventas.get("fuente_pdf", pd.Series(dtype=str)).dropna().unique()
        if str(value).strip()
    )
    source_label = " | ".join(sources) if sources else "dataset combinado"

    write_excel(output_path, ventas_records, movimientos_records, lineas_records, raw_records, source_label)


def main() -> None:
    parser = argparse.ArgumentParser(description="Genera datasets de ventas desde un PDF escaneado.")
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--out", type=Path, default=Path("docs/datasets/dataset_alertas_agua_milena.xlsx"))
    parser.add_argument("--image-dir", type=Path)
    parser.add_argument("--scale", type=float, default=2.8)
    parser.add_argument("--append", action="store_true", help="Anexa el nuevo PDF al workbook existente.")
    args = parser.parse_args()

    image_dir = args.image_dir
    if image_dir is None:
        safe_name = re.sub(r"[^a-zA-Z0-9_-]+", "_", args.pdf.stem).strip("_")
        image_dir = Path("tmp_ocr_pages") / safe_name

    existing_path = None
    if args.append and args.out.exists():
        existing_path = args.out.with_suffix(".previous.xlsx")
        existing_path.write_bytes(args.out.read_bytes())

    total_pages = render_pages(args.pdf, image_dir, args.scale)
    raw_rows, line_rows = run_ocr(image_dir, total_pages)
    ventas, movimientos = extract_blocks(line_rows, args.pdf)
    if existing_path is not None:
        generated_path = args.out.with_suffix(".new.xlsx")
        write_excel(generated_path, ventas, movimientos, line_rows, raw_rows, args.pdf)
        combine_workbooks(existing_path, generated_path, args.out)
        existing_path.unlink(missing_ok=True)
        generated_path.unlink(missing_ok=True)
    else:
        write_excel(args.out, ventas, movimientos, line_rows, raw_rows, args.pdf)

    print(f"Paginas procesadas: {total_pages}")
    print(f"Filas ventas_diarias_tf: {len(ventas)}")
    print(f"Filas movimientos_productos: {len(movimientos)}")
    print(f"Archivo generado: {args.out.resolve()}")


if __name__ == "__main__":
    main()
