from __future__ import annotations

import argparse
import calendar
import math
import random
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

import pandas as pd


START_DATE = date(2023, 1, 1)
END_DATE = date(2026, 3, 31)

PRICE_SELLER_BIDON = 0.55
PRICE_SELLER_FUNDA = 0.85
PRICE_DIRECT_BIDON = 1.00
PRICE_DIRECT_FUNDA = 1.00
PRICE_EXTERNAL_FUNDA = 0.90

TARGET_YEARLY_REVENUE = {
    2023: 33_500.0,
    2024: 34_500.0,
    2025: 35_000.0,
    2026: 8_650.0,  # enero-marzo
}

DAY_NAMES = {
    0: "lunes",
    1: "martes",
    2: "miercoles",
    3: "jueves",
    4: "viernes",
    5: "sabado",
    6: "domingo",
}


@dataclass(frozen=True)
class SeasonFlags:
    verano: int
    navidad: int
    inicio_clases: int
    fiesta_lago_agrio: int
    feriado_nacional: int
    fin_mes: int


def daterange(start: date, end: date) -> list[date]:
    days = []
    current = start
    while current <= end:
        days.append(current)
        current += timedelta(days=1)
    return days


def clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(maximum, value))


def rounded_normal(rng: random.Random, mean: float, sd: float, minimum: int, maximum: int) -> int:
    return clamp(round(rng.gauss(mean, sd)), minimum, maximum)


def bernoulli(rng: random.Random, probability: float) -> bool:
    return rng.random() < probability


def season_flags(day: date) -> SeasonFlags:
    # Lago Agrio celebra actividades por cantonizacion alrededor del 20 de junio.
    fiesta_lago_agrio = int(day.month == 6 and 14 <= day.day <= 20)
    navidad = int(day.month == 12 and 15 <= day.day <= 25)
    inicio_clases = int((day.month == 4 and day.day <= 15) or (day.month == 9 and day.day <= 15))
    verano = int(day.month in {6, 7, 8, 9})
    fin_mes = int(day.day >= calendar.monthrange(day.year, day.month)[1] - 3)
    feriado_nacional = int(
        (day.month, day.day)
        in {
            (1, 1),
            (5, 1),
            (5, 24),
            (8, 10),
            (10, 9),
            (11, 2),
            (11, 3),
            (12, 25),
        }
    )
    return SeasonFlags(verano, navidad, inicio_clases, fiesta_lago_agrio, feriado_nacional, fin_mes)


def seasonal_multiplier(day: date) -> float:
    flags = season_flags(day)
    multiplier = 1.0
    if flags.verano:
        multiplier *= 1.10
    if flags.navidad:
        multiplier *= 1.35
    if flags.inicio_clases:
        multiplier *= 1.14
    if flags.fiesta_lago_agrio:
        multiplier *= 1.16
    if flags.feriado_nacional:
        multiplier *= 0.94
    if flags.fin_mes:
        multiplier *= 1.04
    return multiplier


def day_multiplier(day: date) -> float:
    weekday = day.weekday()
    if weekday == 0:
        return 1.28
    if weekday == 2:
        return 1.30
    if weekday == 5:
        return 1.36
    if weekday == 6:
        return 0.36
    if weekday in {1, 3}:
        return 0.78
    return 0.92


def intensity_by_day(day: date) -> str:
    weekday = day.weekday()
    if weekday in {0, 2, 5}:
        return "alto"
    if weekday == 6:
        return "bajo"
    if weekday in {1, 3, 4}:
        return "medio"
    return "medio_bajo"


def sell_through_by_day(
    day: date,
    *,
    alto: float,
    medio: float,
    medio_bajo: float,
    bajo: float,
) -> float:
    intensity = intensity_by_day(day)
    if intensity == "alto":
        return alto
    if intensity == "medio":
        return medio
    if intensity == "bajo":
        return bajo
    return medio_bajo


def build_seller_events(day: date, rng: random.Random) -> list[dict]:
    events: list[dict] = []
    multiplier = day_multiplier(day) * seasonal_multiplier(day)
    weekday = day.weekday()

    # Uliver: sale todos los dias, 4 viajes normales; buenos 5-6, domingos 1-2.
    if weekday == 6:
        uliver_trips = 1 + int(bernoulli(rng, 0.42))
    elif weekday in {0, 2, 5}:
        uliver_trips = rng.choice([5, 5, 6, 6])
    else:
        uliver_trips = rng.choice([3, 4, 4, 4, 5])
    uliver_loaded_bidones = uliver_trips * rng.choice([3, 3, 4, 4])
    uliver_loaded_fundas = rounded_normal(
        rng,
        5.2 if weekday in {0, 2, 5} else 4.4,
        0.9,
        3,
        7,
    )
    events.append(
        seller_event(
            day,
            "Uliver",
            uliver_trips,
            uliver_loaded_bidones,
            uliver_loaded_fundas,
            sell_through_bidones=sell_through_by_day(
                day,
                alto=min(0.94, 0.70 + 0.10 * multiplier),
                medio=min(0.86, 0.56 + 0.10 * multiplier),
                medio_bajo=min(0.78, 0.48 + 0.08 * multiplier),
                bajo=min(0.54, 0.30 + 0.06 * multiplier),
            ),
            sell_through_fundas=sell_through_by_day(
                day,
                alto=min(0.96, 0.72 + 0.10 * multiplier),
                medio=min(0.88, 0.58 + 0.10 * multiplier),
                medio_bajo=min(0.80, 0.50 + 0.08 * multiplier),
                bajo=min(0.58, 0.34 + 0.06 * multiplier),
            ),
            rng=rng,
        )
    )

    # Geovany: lunes, martes, jueves y sabados; raro otros dias.
    geovany_goes = weekday in {0, 1, 3, 5} or bernoulli(rng, 0.05 if weekday != 6 else 0.02)
    if geovany_goes:
        geovany_trips = 2 if bernoulli(rng, 0.28 if weekday in {0, 2, 5} else 0.18) else 1
        loaded_bidones = geovany_trips * rounded_normal(rng, 30, 2.5, 26, 35)
        loaded_fundas = geovany_trips * rounded_normal(rng, 13, 1.5, 11, 15)
        events.append(
            seller_event(
                day,
                "Geovany",
                geovany_trips,
                loaded_bidones,
                loaded_fundas,
                sell_through_bidones=sell_through_by_day(
                    day,
                    alto=min(0.90, 0.54 + 0.13 * multiplier),
                    medio=min(0.66, 0.36 + 0.10 * multiplier),
                    medio_bajo=min(0.58, 0.30 + 0.08 * multiplier),
                    bajo=min(0.35, 0.20 + 0.05 * multiplier),
                ),
                sell_through_fundas=sell_through_by_day(
                    day,
                    alto=min(0.90, 0.56 + 0.12 * multiplier),
                    medio=min(0.68, 0.38 + 0.10 * multiplier),
                    medio_bajo=min(0.60, 0.32 + 0.08 * multiplier),
                    bajo=min(0.38, 0.22 + 0.05 * multiplier),
                ),
                rng=rng,
            )
        )

    # Paisa: desde 2025 baja frecuencia; antes iba mas y cargaba mas.
    if day.year < 2025:
        paisa_goes = weekday in {0, 1, 3, 5} or bernoulli(rng, 0.22)
        if paisa_goes:
            paisa_trips = 2 if bernoulli(rng, 0.24) else 1
            loaded_bidones = paisa_trips * rounded_normal(rng, 25, 3.0, 20, 30)
            loaded_fundas = paisa_trips * rounded_normal(rng, 15, 3.0, 10, 20)
            events.append(
                seller_event(
                    day,
                    "Paisa",
                    paisa_trips,
                    loaded_bidones,
                    loaded_fundas,
                    sell_through_bidones=sell_through_by_day(
                        day,
                        alto=min(0.88, 0.52 + 0.12 * multiplier),
                        medio=min(0.64, 0.34 + 0.10 * multiplier),
                        medio_bajo=min(0.56, 0.30 + 0.08 * multiplier),
                        bajo=min(0.34, 0.20 + 0.04 * multiplier),
                    ),
                    sell_through_fundas=sell_through_by_day(
                        day,
                        alto=min(0.88, 0.54 + 0.12 * multiplier),
                        medio=min(0.66, 0.36 + 0.10 * multiplier),
                        medio_bajo=min(0.58, 0.32 + 0.08 * multiplier),
                        bajo=min(0.36, 0.22 + 0.04 * multiplier),
                    ),
                    rng=rng,
                )
            )
    else:
        paisa_goes = weekday in {1, 3, 5} or bernoulli(rng, 0.08)
        if paisa_goes:
            paisa_trips = 2 if bernoulli(rng, 0.10) else 1
            loaded_bidones = paisa_trips * rounded_normal(rng, 12, 2.0, 9, 15)
            loaded_fundas = paisa_trips * rounded_normal(rng, 10, 1.5, 8, 12)
            events.append(
                seller_event(
                    day,
                    "Paisa",
                    paisa_trips,
                    loaded_bidones,
                    loaded_fundas,
                    sell_through_bidones=sell_through_by_day(
                        day,
                        alto=min(0.88, 0.56 + 0.11 * multiplier),
                        medio=min(0.66, 0.40 + 0.09 * multiplier),
                        medio_bajo=min(0.58, 0.34 + 0.08 * multiplier),
                        bajo=min(0.34, 0.22 + 0.04 * multiplier),
                    ),
                    sell_through_fundas=sell_through_by_day(
                        day,
                        alto=min(0.90, 0.58 + 0.11 * multiplier),
                        medio=min(0.68, 0.42 + 0.09 * multiplier),
                        medio_bajo=min(0.60, 0.36 + 0.08 * multiplier),
                        bajo=min(0.36, 0.24 + 0.04 * multiplier),
                    ),
                    rng=rng,
                )
            )

    return events


def seller_event(
    day: date,
    seller: str,
    trips: int,
    loaded_bidones: int,
    loaded_fundas: int,
    sell_through_bidones: float,
    sell_through_fundas: float,
    rng: random.Random,
) -> dict:
    sold_bidones = clamp(round(loaded_bidones * rng.uniform(sell_through_bidones - 0.08, sell_through_bidones + 0.08)), 0, loaded_bidones)
    sold_fundas = clamp(round(loaded_fundas * rng.uniform(sell_through_fundas - 0.08, sell_through_fundas + 0.08)), 0, loaded_fundas)
    empty_returned = clamp(round(sold_bidones * rng.uniform(0.65, 0.95)), 0, sold_bidones)
    revenue = sold_bidones * PRICE_SELLER_BIDON + sold_fundas * PRICE_SELLER_FUNDA
    return {
        "fecha": day.isoformat(),
        "fuente_dato": "sintetico",
        "canal": "vendedor",
        "vendedor": seller,
        "viajes": trips,
        "bidones_cargados": loaded_bidones,
        "fundas_cargadas": loaded_fundas,
        "bidones_vendidos": sold_bidones,
        "fundas_vendidas": sold_fundas,
        "vacios_devueltos": empty_returned,
        "precio_bidon": PRICE_SELLER_BIDON,
        "precio_funda": PRICE_SELLER_FUNDA,
        "ingreso_total": round(revenue, 2),
        "pedido_grande_fundas": 0,
    }


def build_direct_event(day: date, seller_revenue: float, rng: random.Random) -> dict:
    desired_direct_revenue = seller_revenue / 3.0
    multiplier = day_multiplier(day) * seasonal_multiplier(day)
    desired_direct_revenue *= rng.uniform(0.86, 1.14)
    if day.weekday() == 2:
        desired_direct_revenue *= 11.00
    elif day.weekday() in {0, 5}:
        desired_direct_revenue *= 0.90
    elif day.weekday() in {1, 3}:
        desired_direct_revenue *= 0.90
    elif day.weekday() == 4:
        desired_direct_revenue *= 14.00
    fundas_units = clamp(round(desired_direct_revenue * rng.uniform(0.25, 0.45)), 0, 999)
    bidones_units = clamp(round(desired_direct_revenue - fundas_units), 0, 999)
    if day.weekday() == 6:
        bidones_units = round(bidones_units * rng.uniform(0.35, 0.65))
        fundas_units = round(fundas_units * rng.uniform(0.35, 0.70))
    bidones_units = round(bidones_units * min(1.35, max(0.60, multiplier)) / max(multiplier, 1.0))
    revenue = bidones_units * PRICE_DIRECT_BIDON + fundas_units * PRICE_DIRECT_FUNDA
    return {
        "fecha": day.isoformat(),
        "fuente_dato": "sintetico",
        "canal": "distribuidora",
        "vendedor": "Distribuidora",
        "viajes": 0,
        "bidones_cargados": bidones_units,
        "fundas_cargadas": fundas_units,
        "bidones_vendidos": bidones_units,
        "fundas_vendidas": fundas_units,
        "vacios_devueltos": round(bidones_units * rng.uniform(0.70, 0.98)),
        "precio_bidon": PRICE_DIRECT_BIDON,
        "precio_funda": PRICE_DIRECT_FUNDA,
        "ingreso_total": round(revenue, 2),
        "pedido_grande_fundas": 0,
    }


def last_business_day(year: int, month: int) -> date:
    last_day = calendar.monthrange(year, month)[1]
    current = date(year, month, last_day)
    while current.weekday() == 6:
        current -= timedelta(days=1)
    return current


def big_order_event(day: date, rng: random.Random) -> dict | None:
    if day != last_business_day(day.year, day.month):
        return None
    if day.year == 2025 and day.month in {9, 10}:
        fundas = rng.choice([100, 120, 150, 180, 200])
    else:
        fundas = rng.choice([30, 35, 40, 50, 60, 70])
    revenue = fundas * PRICE_EXTERNAL_FUNDA
    return {
        "fecha": day.isoformat(),
        "fuente_dato": "sintetico",
        "canal": "externo",
        "vendedor": "Cliente externo",
        "viajes": 0,
        "bidones_cargados": 0,
        "fundas_cargadas": fundas,
        "bidones_vendidos": 0,
        "fundas_vendidas": fundas,
        "vacios_devueltos": 0,
        "precio_bidon": 0.0,
        "precio_funda": PRICE_EXTERNAL_FUNDA,
        "ingreso_total": round(revenue, 2),
        "pedido_grande_fundas": 1,
    }


def build_events(start: date, end: date, seed: int) -> pd.DataFrame:
    rng = random.Random(seed)
    rows: list[dict] = []
    for day in daterange(start, end):
        seller_events = build_seller_events(day, rng)
        rows.extend(seller_events)
        seller_revenue = sum(event["ingreso_total"] for event in seller_events)
        rows.append(build_direct_event(day, seller_revenue, rng))
        big_order = big_order_event(day, rng)
        if big_order:
            rows.append(big_order)

    events = pd.DataFrame(rows)
    return calibrate_revenue(events)


def calibrate_revenue(events: pd.DataFrame) -> pd.DataFrame:
    events = events.copy()
    for year, target in TARGET_YEARLY_REVENUE.items():
        mask = pd.to_datetime(events["fecha"]).dt.year.eq(year)
        total = events.loc[mask, "ingreso_total"].sum()
        if total <= 0:
            continue
        factor = target / total
        for column in ["bidones_vendidos", "fundas_vendidas", "vacios_devueltos"]:
            events.loc[mask, column] = (events.loc[mask, column] * factor).round().clip(lower=0).astype(int)
        events.loc[mask, "bidones_cargados"] = events.loc[mask, ["bidones_cargados", "bidones_vendidos"]].max(axis=1)
        events.loc[mask, "fundas_cargadas"] = events.loc[mask, ["fundas_cargadas", "fundas_vendidas"]].max(axis=1)
        events.loc[mask, "ingreso_total"] = (
            events.loc[mask, "bidones_vendidos"] * events.loc[mask, "precio_bidon"]
            + events.loc[mask, "fundas_vendidas"] * events.loc[mask, "precio_funda"]
        ).round(2)
    return events


def aggregate_daily(events: pd.DataFrame, start: date, end: date) -> pd.DataFrame:
    events = events.copy()
    events["fecha"] = pd.to_datetime(events["fecha"])
    grouped = (
        events.groupby("fecha")
        .agg(
            bidones_vendidos_total=("bidones_vendidos", "sum"),
            fundas_vendidas_total=("fundas_vendidas", "sum"),
            vacios_devueltos_total=("vacios_devueltos", "sum"),
            bidones_cargados_total=("bidones_cargados", "sum"),
            fundas_cargadas_total=("fundas_cargadas", "sum"),
            viajes_total=("viajes", "sum"),
            ingreso_total=("ingreso_total", "sum"),
            pedidos_grandes_fundas=("pedido_grande_fundas", "sum"),
        )
        .reset_index()
    )

    by_channel = (
        events.pivot_table(
            index="fecha",
            columns="canal",
            values="ingreso_total",
            aggfunc="sum",
            fill_value=0,
        )
        .reset_index()
        .rename_axis(None, axis=1)
    )
    for canal in ["vendedor", "distribuidora", "externo"]:
        if canal not in by_channel:
            by_channel[canal] = 0.0
    grouped = grouped.merge(by_channel, on="fecha", how="left")

    all_days = pd.DataFrame({"fecha": pd.date_range(start, end, freq="D")})
    daily = all_days.merge(grouped, on="fecha", how="left").fillna(0)
    daily = add_features_and_labels(daily)
    return daily


def add_features_and_labels(daily: pd.DataFrame) -> pd.DataFrame:
    daily = daily.sort_values("fecha").reset_index(drop=True)
    daily["fecha"] = pd.to_datetime(daily["fecha"])
    daily["anio"] = daily["fecha"].dt.year
    daily["mes"] = daily["fecha"].dt.month
    daily["dia_mes"] = daily["fecha"].dt.day
    daily["dia_semana_num"] = daily["fecha"].dt.weekday + 1
    daily["dia_semana"] = daily["fecha"].dt.weekday.map(DAY_NAMES)
    daily["es_lunes"] = daily["dia_semana_num"].eq(1).astype(int)
    daily["es_miercoles"] = daily["dia_semana_num"].eq(3).astype(int)
    daily["es_sabado"] = daily["dia_semana_num"].eq(6).astype(int)
    daily["es_domingo"] = daily["dia_semana_num"].eq(7).astype(int)
    daily["es_fin_semana"] = daily["dia_semana_num"].isin([6, 7]).astype(int)

    flags = daily["fecha"].dt.date.map(season_flags)
    daily["temporada_verano"] = flags.map(lambda item: item.verano)
    daily["temporada_navidad"] = flags.map(lambda item: item.navidad)
    daily["temporada_inicio_clases"] = flags.map(lambda item: item.inicio_clases)
    daily["temporada_fiesta_lago_agrio"] = flags.map(lambda item: item.fiesta_lago_agrio)
    daily["feriado_nacional"] = flags.map(lambda item: item.feriado_nacional)
    daily["fin_mes"] = flags.map(lambda item: item.fin_mes)

    daily["vendedores_planificados"] = daily["fecha"].dt.date.map(planned_sellers_count)
    daily["paisa_etapa_baja_frecuencia"] = (daily["fecha"].dt.year >= 2025).astype(int)

    for column in ["bidones_vendidos_total", "fundas_vendidas_total", "ingreso_total"]:
        daily[f"{column}_lag_1"] = daily[column].shift(1).fillna(0)
        daily[f"{column}_prom_7d"] = daily[column].shift(1).rolling(7, min_periods=1).mean().fillna(0).round(2)
        daily[f"{column}_prom_30d"] = daily[column].shift(1).rolling(30, min_periods=1).mean().fillna(0).round(2)

    daily["stock_bidones_inicio_estimado"] = (
        daily["bidones_cargados_total"].shift(1).rolling(3, min_periods=1).mean().fillna(35).round().astype(int)
    )
    daily["stock_fundas_inicio_estimado"] = (
        daily["fundas_cargadas_total"].shift(1).rolling(3, min_periods=1).mean().fillna(18).round().astype(int)
    )

    daily["label_demanda_bidones"] = daily["bidones_vendidos_total"].round().astype(int)
    daily["label_demanda_fundas"] = daily["fundas_vendidas_total"].round().astype(int)
    daily["label_demanda_total_unidades"] = daily["label_demanda_bidones"] + daily["label_demanda_fundas"]
    daily["label_carga_recomendada_bidones"] = daily["label_demanda_bidones"].map(lambda value: int(math.ceil(value * 1.12)))
    daily["label_carga_recomendada_fundas"] = daily["label_demanda_fundas"].map(lambda value: int(math.ceil(value * 1.10)))
    daily["label_alerta_stock_bajo"] = (
        daily["stock_bidones_inicio_estimado"] < daily["label_carga_recomendada_bidones"]
    ).astype(int)
    daily["label_venta_alta_inesperada"] = (
        daily["label_demanda_total_unidades"]
        > daily["label_demanda_total_unidades"].shift(1).rolling(30, min_periods=7).mean().fillna(0) * 1.55
    ).astype(int)
    daily["fuente_dato"] = "sintetico"
    daily["requiere_revision"] = 0
    daily["fecha"] = daily["fecha"].dt.date.astype(str)
    return daily


def planned_sellers_count(day: date) -> int:
    count = 1  # Uliver
    if day.weekday() in {0, 1, 3, 5}:
        count += 1
    if day.year < 2025:
        if day.weekday() in {0, 1, 3, 5}:
            count += 1
    elif day.weekday() in {1, 3, 5}:
        count += 1
    return count


def annual_summary(events: pd.DataFrame) -> pd.DataFrame:
    events = events.copy()
    events["anio"] = pd.to_datetime(events["fecha"]).dt.year
    return (
        events.groupby("anio")
        .agg(
            ingreso_total=("ingreso_total", "sum"),
            bidones_vendidos=("bidones_vendidos", "sum"),
            fundas_vendidas=("fundas_vendidas", "sum"),
            ventas_vendedores=("ingreso_total", lambda s: 0),
        )
        .reset_index()
    )


def build_summary(events: pd.DataFrame) -> pd.DataFrame:
    events = events.copy()
    events["anio"] = pd.to_datetime(events["fecha"]).dt.year
    summary = (
        events.pivot_table(
            index="anio",
            columns="canal",
            values="ingreso_total",
            aggfunc="sum",
            fill_value=0,
        )
        .reset_index()
        .rename_axis(None, axis=1)
    )
    for column in ["vendedor", "distribuidora", "externo"]:
        if column not in summary:
            summary[column] = 0.0
    summary["ingreso_total"] = summary[["vendedor", "distribuidora", "externo"]].sum(axis=1).round(2)
    summary["pct_vendedores"] = (summary["vendedor"] / summary["ingreso_total"]).round(4)
    summary["pct_distribuidora"] = (summary["distribuidora"] / summary["ingreso_total"]).round(4)
    summary["pct_externo"] = (summary["externo"] / summary["ingreso_total"]).round(4)
    return summary.round(2)


def write_outputs(events: pd.DataFrame, daily: pd.DataFrame, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    training_csv = output_dir / "alertas_tensorflow_entrenamiento.csv"
    numeric_csv = output_dir / "alertas_tensorflow_entrenamiento_numerico.csv"
    events_csv = output_dir / "ventas_sinteticas_eventos.csv"
    workbook = output_dir / "dataset_tensorflow_entrenamiento.xlsx"
    summary = build_summary(events)
    params = pd.DataFrame(
        [
            {"parametro": "rango", "valor": f"{START_DATE.isoformat()} a {END_DATE.isoformat()}"},
            {"parametro": "vendedores", "valor": "Uliver, Geovany, Paisa"},
            {"parametro": "dias_altos", "valor": "lunes, miercoles, sabado"},
            {"parametro": "dia_bajo", "valor": "domingo"},
            {"parametro": "precio_vendedor_bidon", "valor": PRICE_SELLER_BIDON},
            {"parametro": "precio_vendedor_funda", "valor": PRICE_SELLER_FUNDA},
            {"parametro": "precio_distribuidora", "valor": 1.00},
            {"parametro": "precio_externo_funda_grande", "valor": PRICE_EXTERNAL_FUNDA},
            {"parametro": "nota", "valor": "Dataset sintetico calibrado para entrenamiento inicial de TensorFlow."},
        ]
    )
    daily.to_csv(training_csv, index=False, encoding="utf-8-sig")
    numeric_daily = daily.drop(columns=["fecha", "dia_semana", "fuente_dato"], errors="ignore")
    numeric_daily.to_csv(numeric_csv, index=False, encoding="utf-8-sig")
    events.to_csv(events_csv, index=False, encoding="utf-8-sig")
    with pd.ExcelWriter(workbook, engine="openpyxl") as writer:
        pd.DataFrame(
            [
                {
                    "archivo_tensorflow": training_csv.name,
                    "descripcion": "Version completa con fecha y campos descriptivos.",
                },
                {
                    "archivo_tensorflow": numeric_csv.name,
                    "descripcion": "Version numerica recomendada para cargar directo en TensorFlow.",
                }
            ]
        ).to_excel(writer, index=False, sheet_name="README")
        daily.to_excel(writer, index=False, sheet_name="alertas_tensorflow")
        numeric_daily.to_excel(writer, index=False, sheet_name="alertas_numerico")
        events.to_excel(writer, index=False, sheet_name="ventas_eventos")
        summary.to_excel(writer, index=False, sheet_name="resumen_anual")
        params.to_excel(writer, index=False, sheet_name="parametros")


def main() -> None:
    parser = argparse.ArgumentParser(description="Genera dataset sintetico para alertas TensorFlow.")
    parser.add_argument("--out-dir", type=Path, default=Path("docs/datasets"))
    parser.add_argument("--seed", type=int, default=20260503)
    args = parser.parse_args()

    events = build_events(START_DATE, END_DATE, args.seed)
    daily = aggregate_daily(events, START_DATE, END_DATE)
    write_outputs(events, daily, args.out_dir)
    print(f"Eventos sinteticos: {len(events)}")
    print(f"Filas TensorFlow: {len(daily)}")
    print(build_summary(events).to_string(index=False))


if __name__ == "__main__":
    main()
