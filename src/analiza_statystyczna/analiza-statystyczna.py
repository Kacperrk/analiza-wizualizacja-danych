from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from scipy.stats import linregress, pearsonr

SEED = 42
FIGURE_DPI = 150
QUANTILE_LOW = 0.1
QUANTILE_HIGH = 0.9
N_INJECTED_MISSING = 4
N_INJECTED_NEGATIVE = 4
N_INJECTED_INFINITE = 2
P_VALUE_SCIENTIFIC_THRESHOLD = 0.0001
SLOPE_SCIENTIFIC_THRESHOLD = 0.001
SIGNIFICANT_DIGITS = 3
EXAMPLE_ROW_COUNT = 3
FEATURE_GRID_COLUMNS = 3

BASE_DIR = Path(__file__).resolve().parent


@dataclass(frozen=True)
class DatasetConfig:
    key: str
    display_name: str
    input_dir: Path
    output_dir: Path
    class_column: str
    plot_features: list[str]
    regression_pairs: list[tuple[str, str]]
    example_columns: list[str]


def load_breast_cancer_wisconsin(input_dir: Path) -> pd.DataFrame:
    data_path = input_dir / "wdbc.data"
    if not data_path.exists():
        raise FileNotFoundError(f"Brak pliku z danymi: {data_path}")
    measures = [
        "radius",
        "texture",
        "perimeter",
        "area",
        "smoothness",
        "compactness",
        "concavity",
        "concave_points",
        "symmetry",
        "fractal_dimension",
    ]
    columns = ["id", "diagnosis"]
    for suffix in ["mean", "se", "worst"]:
        columns.extend(f"{measure}_{suffix}" for measure in measures)
    data_frame = pd.read_csv(data_path, header=None, names=columns)
    return data_frame.drop(columns=["id"])


def load_dry_bean(input_dir: Path) -> pd.DataFrame:
    data_path = input_dir / "Dry_Bean_Dataset.xlsx"
    if not data_path.exists():
        raise FileNotFoundError(f"Brak pliku z danymi: {data_path}")
    return pd.read_excel(data_path)


def load_dataset(config: DatasetConfig) -> pd.DataFrame:
    if config.key == "dry_bean":
        return load_dry_bean(config.input_dir)
    return load_breast_cancer_wisconsin(config.input_dir)


def get_numeric_columns(data_frame: pd.DataFrame, class_column: str) -> list[str]:
    return [
        column
        for column in data_frame.columns
        if column != class_column and pd.api.types.is_numeric_dtype(data_frame[column])
    ]


def detect_data_errors(
    data_frame: pd.DataFrame, numeric_columns: list[str]
) -> dict[str, int]:
    numeric_part = data_frame[numeric_columns]
    return {
        "missing": int(numeric_part.isna().sum().sum()),
        "infinite": int(
            np.isinf(numeric_part.to_numpy(dtype=float, na_value=0.0)).sum()
        ),
        "negative": int((numeric_part < 0).sum().sum()),
        "duplicates": int(data_frame.duplicated().sum()),
    }


def duplicate_classes(data_frame: pd.DataFrame, class_column: str) -> str:
    duplicated_mask = data_frame.duplicated(keep=False)
    if not duplicated_mask.any():
        return ""
    labels = {str(label) for label in data_frame.loc[duplicated_mask, class_column]}
    return ", ".join(sorted(labels))


def clean_data(
    data_frame: pd.DataFrame,
    numeric_columns: list[str],
    rng: np.random.Generator,
    method: str = "median",
) -> pd.DataFrame:
    cleaned = data_frame.copy()
    for column in numeric_columns:
        series = cleaned[column].replace([np.inf, -np.inf], np.nan)
        series = series.mask(series < 0, np.nan)
        valid_values = series.dropna()
        missing_mask = series.isna()
        missing_count = int(missing_mask.sum())
        if method == "mean":
            fill_values = np.full(missing_count, float(valid_values.mean()))
        elif method == "random":
            fill_values = rng.uniform(
                float(valid_values.min()), float(valid_values.max()), size=missing_count
            )
        else:
            fill_values = np.full(missing_count, float(valid_values.median()))
        series.loc[missing_mask] = fill_values
        cleaned[column] = series
    return cleaned


def inject_test_errors(
    data_frame: pd.DataFrame, numeric_columns: list[str], rng: np.random.Generator
) -> pd.DataFrame:
    corrupted = data_frame.copy()
    row_count = len(corrupted)
    for _ in range(N_INJECTED_MISSING):
        column = rng.choice(numeric_columns)
        row = int(rng.integers(0, row_count))
        corrupted.loc[corrupted.index[row], column] = np.nan
    for _ in range(N_INJECTED_NEGATIVE):
        column = rng.choice(numeric_columns)
        row = int(rng.integers(0, row_count))
        corrupted.loc[corrupted.index[row], column] = -1.0
    for _ in range(N_INJECTED_INFINITE):
        column = rng.choice(numeric_columns)
        row = int(rng.integers(0, row_count))
        corrupted.loc[corrupted.index[row], column] = np.inf
    return corrupted


def run_cleaning_test(
    data_frame: pd.DataFrame,
    numeric_columns: list[str],
    rng: np.random.Generator,
    dataset_name: str,
) -> None:
    corrupted = inject_test_errors(data_frame, numeric_columns, rng)
    report_before = detect_data_errors(corrupted, numeric_columns)
    cleaned = clean_data(corrupted, numeric_columns, rng)
    report_after = detect_data_errors(cleaned, numeric_columns)
    print(f"[test-cleaning] {dataset_name}: przed = {report_before}")
    print(f"[test-cleaning] {dataset_name}: po    = {report_after}")


def compute_descriptive_stats_table(
    data_frame: pd.DataFrame, numeric_columns: list[str]
) -> pd.DataFrame:
    numeric_part = data_frame[numeric_columns]
    table = numeric_part.agg(["min", "max", "mean", "std", "median"]).T
    table["q1"] = numeric_part.quantile(0.25)
    table["q3"] = numeric_part.quantile(0.75)
    table["decile_1"] = numeric_part.quantile(QUANTILE_LOW)
    table["decile_9"] = numeric_part.quantile(QUANTILE_HIGH)
    table.index.name = "variable"
    return table


def compute_regression(x: pd.Series, y: pd.Series) -> dict[str, float]:
    regression = linregress(x.to_numpy(dtype=float), y.to_numpy(dtype=float))
    return {
        "slope": float(regression.slope),
        "intercept": float(regression.intercept),
        "r_squared": float(regression.rvalue) ** 2,
        "p_value": float(regression.pvalue),
    }


def compute_group_means(
    data_frame: pd.DataFrame, class_column: str, features: list[str]
) -> dict[str, dict[str, str]]:
    means = data_frame.groupby(class_column)[features].mean()
    return {
        feature: {
            str(label): format_number(value) for label, value in means[feature].items()
        }
        for feature in features
    }


def format_number(value: float, decimals: int = 3) -> str:
    return f"{value:.{decimals}f}".replace(".", ",")


def format_p_value(value: float) -> str:
    if value == 0.0:
        return "< 0,0001"
    if value < P_VALUE_SCIENTIFIC_THRESHOLD:
        return f"{value:.3e}".replace(".", ",")
    return format_number(value, 4)


def format_significant(value: float) -> str:
    if abs(value) >= SLOPE_SCIENTIFIC_THRESHOLD:
        return format_number(value, 4)
    if value == 0.0:
        return "0,000"
    mantissa, _, exponent = f"{value:.{SIGNIFICANT_DIGITS - 1}e}".partition("e")
    return f"{mantissa}e{int(exponent):+d}".replace(".", ",")


def format_regression_formula(slope: float, intercept: float) -> str:
    slope_text = format_significant(slope)
    if intercept >= 0:
        return f"y = {slope_text}*x + {format_number(intercept, 4)}"
    return f"y = {slope_text}*x - {format_number(abs(intercept), 4)}"


def read_stat(stats_table: pd.DataFrame, feature: str, column: str) -> float:
    return cast(float, stats_table.at[feature, column])


def build_descriptive_stats_section(
    stats_table: pd.DataFrame, plot_features: list[str]
) -> dict[str, dict[str, str]]:
    section: dict[str, dict[str, str]] = {}
    for feature in plot_features:
        section[feature] = {
            "min": format_number(read_stat(stats_table, feature, "min")),
            "max": format_number(read_stat(stats_table, feature, "max")),
            "srednia": format_number(read_stat(stats_table, feature, "mean")),
            "odchylenie_std": format_number(read_stat(stats_table, feature, "std")),
            "mediana": format_number(read_stat(stats_table, feature, "median")),
            "q1": format_number(read_stat(stats_table, feature, "q1")),
            "q3": format_number(read_stat(stats_table, feature, "q3")),
            "kwantyl_0_1": format_number(read_stat(stats_table, feature, "decile_1")),
            "kwantyl_0_9": format_number(read_stat(stats_table, feature, "decile_9")),
        }
    return section


def build_example_records(
    data_frame: pd.DataFrame, columns: list[str], count: int = EXAMPLE_ROW_COUNT
) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    for _, row in data_frame[columns].head(count).iterrows():
        record: dict[str, str] = {}
        for column in columns:
            value = row[column]
            record[column] = (
                value if isinstance(value, str) else format_number(float(value))
            )
        records.append(record)
    return records


def build_correlation_and_regression(
    data_frame: pd.DataFrame, regression_pairs: list[tuple[str, str]]
) -> tuple[list[dict[str, str]], list[dict[str, str]], list[dict[str, float]]]:
    correlations: list[dict[str, str]] = []
    regressions: list[dict[str, str]] = []
    raw_regressions: list[dict[str, float]] = []
    for x_name, y_name in regression_pairs:
        x_values = data_frame[x_name]
        y_values = data_frame[y_name]
        correlation = pearsonr(
            x_values.to_numpy(dtype=float), y_values.to_numpy(dtype=float)
        )
        correlations.append(
            {
                "zmienna_x": x_name,
                "zmienna_y": y_name,
                "r": format_number(float(correlation.statistic)),
                "p_value": format_p_value(float(correlation.pvalue)),
            }
        )
        regression = compute_regression(x_values, y_values)
        raw_regressions.append(regression)
        regressions.append(
            {
                "zmienna_x": x_name,
                "zmienna_y": y_name,
                "a": format_significant(regression["slope"]),
                "b": format_number(regression["intercept"], 4),
                "r2": format_number(regression["r_squared"]),
                "p_value": format_p_value(regression["p_value"]),
                "wzor": format_regression_formula(
                    regression["slope"], regression["intercept"]
                ),
            }
        )
    return correlations, regressions, raw_regressions


def build_results(
    config: DatasetConfig,
    data_frame: pd.DataFrame,
    stats_table: pd.DataFrame,
    cleaning_counts: dict[str, int],
) -> tuple[dict[str, object], list[dict[str, float]]]:
    class_counts = data_frame[config.class_column].value_counts().sort_index()
    correlations, regressions, raw_regressions = build_correlation_and_regression(
        data_frame, config.regression_pairs
    )
    results: dict[str, object] = {
        "nazwa_zbioru": config.display_name,
        "liczba_rekordow": str(len(data_frame)),
        "liczba_cech": str(len(get_numeric_columns(data_frame, config.class_column))),
        "czyszczenie": {
            "brakujace_wartosci": str(cleaning_counts["missing"]),
            "wartosci_nieskonczone": str(cleaning_counts["infinite"]),
            "wartosci_ujemne": str(cleaning_counts["negative"]),
            "duplikaty": str(cleaning_counts["duplicates"]),
            "duplikaty_klasy": duplicate_classes(data_frame, config.class_column),
        },
        "liczebnosc_klas": {
            str(label): str(count) for label, count in class_counts.items()
        },
        "statystyki_opisowe": build_descriptive_stats_section(
            stats_table, config.plot_features
        ),
        "korelacje": correlations,
        "regresje": regressions,
        "przykladowe_rekordy": build_example_records(
            data_frame, config.example_columns
        ),
        "srednie_wg_klasy": compute_group_means(
            data_frame, config.class_column, config.plot_features
        ),
    }
    return results, raw_regressions


def save_results_json(results: dict[str, object], output_dir: Path) -> None:
    results_path = output_dir / "results.json"
    with results_path.open("w", encoding="utf-8") as results_file:
        json.dump(results, results_file, ensure_ascii=False, indent=2)


def save_descriptive_stats_csv(table: pd.DataFrame, output_dir: Path) -> None:
    table.to_csv(output_dir / "opisowe.csv", encoding="utf-8")


def plot_class_counts(
    data_frame: pd.DataFrame, class_column: str, title: str, output_dir: Path
) -> None:
    counts = data_frame[class_column].value_counts().sort_index()
    labels = [str(label) for label in counts.index]

    figure, axis = plt.subplots(figsize=(6, 6))
    axis.pie(counts, labels=labels, autopct="%1.1f%%", startangle=90)
    axis.set_title(f"Liczebność klas – {title}")
    figure.savefig(output_dir / "fig_liczebnosc_kolowy.png", dpi=FIGURE_DPI)
    plt.close(figure)

    figure, axis = plt.subplots(figsize=(7, 5))
    sns.barplot(x=labels, y=counts.to_numpy(), ax=axis)
    axis.set_title(f"Liczebność klas – {title}")
    axis.set_xlabel("Klasa")
    axis.set_ylabel("Liczba rekordów")
    axis.tick_params(axis="x", rotation=30)
    figure.tight_layout()
    figure.savefig(output_dir / "fig_liczebnosc_slupkowy.png", dpi=FIGURE_DPI)
    plt.close(figure)


def plot_feature_grid(
    data_frame: pd.DataFrame, features: list[str], output_dir: Path, kind: str
) -> None:
    row_count = (len(features) + FEATURE_GRID_COLUMNS - 1) // FEATURE_GRID_COLUMNS
    figure, axes = plt.subplots(
        row_count, FEATURE_GRID_COLUMNS, figsize=(11, 2.8 * row_count)
    )
    axes = np.atleast_1d(axes).flatten()
    for axis, feature in zip(axes, features):
        series = data_frame[feature]
        if kind == "hist":
            sns.histplot(x=series, ax=axis, kde=True)
        elif kind == "box":
            axis.boxplot(series)
            axis.set_xticks([1])
            axis.set_xticklabels([feature])
        else:
            sns.violinplot(y=series, ax=axis)
            axis.set_ylabel("")
        axis.set_title(feature)
    for axis in axes[len(features) :]:
        axis.set_visible(False)
    figure.tight_layout()
    filenames = {
        "hist": "fig_histogramy.png",
        "box": "fig_pudelkowe.png",
        "violin": "fig_wiolinowe.png",
    }
    figure.savefig(output_dir / filenames[kind], dpi=FIGURE_DPI)
    plt.close(figure)


def plot_scatter_with_regression(
    data_frame: pd.DataFrame,
    regression_pairs: list[tuple[str, str]],
    raw_regressions: list[dict[str, float]],
    output_dir: Path,
) -> None:
    for index, ((x_name, y_name), regression) in enumerate(
        zip(regression_pairs, raw_regressions), start=1
    ):
        x_values = data_frame[x_name]
        figure, axis = plt.subplots(figsize=(7, 5))
        axis.scatter(x_values, data_frame[y_name], alpha=0.5, s=12)
        line_x = np.array([x_values.min(), x_values.max()])
        line_y = regression["slope"] * line_x + regression["intercept"]
        axis.plot(line_x, line_y, color="red")
        axis.set_xlabel(x_name)
        axis.set_ylabel(y_name)
        axis.set_title(
            f"{y_name} vs {x_name} (R² = {format_number(regression['r_squared'])})"
        )
        figure.tight_layout()
        figure.savefig(output_dir / f"fig_rozrzut_{index}.png", dpi=FIGURE_DPI)
        plt.close(figure)


def run_dataset_analysis(config: DatasetConfig, rng: np.random.Generator) -> None:
    config.output_dir.mkdir(parents=True, exist_ok=True)
    raw_data = load_dataset(config)
    numeric_columns = get_numeric_columns(raw_data, config.class_column)

    cleaning_counts = detect_data_errors(raw_data, numeric_columns)
    cleaned_data = clean_data(raw_data, numeric_columns, rng)

    stats_table = compute_descriptive_stats_table(cleaned_data, numeric_columns)
    save_descriptive_stats_csv(stats_table, config.output_dir)

    results, raw_regressions = build_results(
        config, cleaned_data, stats_table, cleaning_counts
    )
    save_results_json(results, config.output_dir)

    plot_class_counts(
        cleaned_data, config.class_column, config.display_name, config.output_dir
    )
    plot_feature_grid(cleaned_data, config.plot_features, config.output_dir, "hist")
    plot_feature_grid(cleaned_data, config.plot_features, config.output_dir, "box")
    plot_feature_grid(cleaned_data, config.plot_features, config.output_dir, "violin")
    plot_scatter_with_regression(
        cleaned_data, config.regression_pairs, raw_regressions, config.output_dir
    )

    print(f"{config.display_name}: zapisano wyniki w {config.output_dir}")


def build_dataset_configs() -> dict[str, DatasetConfig]:
    dry_bean_dir = BASE_DIR / "dry_bean"
    breast_cancer_dir = BASE_DIR / "breast_cancer_wisconsin"
    return {
        "dry_bean": DatasetConfig(
            key="dry_bean",
            display_name="Dry Bean",
            input_dir=dry_bean_dir / "input",
            output_dir=dry_bean_dir / "output",
            class_column="Class",
            plot_features=["Area", "Perimeter", "roundness", "AspectRation", "Extent"],
            regression_pairs=[
                ("Area", "Perimeter"),
                ("Perimeter", "roundness"),
                ("Area", "Extent"),
            ],
            example_columns=[
                "Area",
                "Perimeter",
                "MajorAxisLength",
                "MinorAxisLength",
                "AspectRation",
                "roundness",
                "Class",
            ],
        ),
        "breast_cancer_wisconsin": DatasetConfig(
            key="breast_cancer_wisconsin",
            display_name="Breast Cancer Wisconsin (Diagnostic)",
            input_dir=breast_cancer_dir / "input",
            output_dir=breast_cancer_dir / "output",
            class_column="diagnosis",
            plot_features=[
                "radius_mean",
                "texture_mean",
                "perimeter_mean",
                "concavity_mean",
                "smoothness_mean",
            ],
            regression_pairs=[
                ("radius_mean", "perimeter_mean"),
                ("smoothness_mean", "fractal_dimension_mean"),
                ("texture_mean", "smoothness_mean"),
            ],
            example_columns=[
                "radius_mean",
                "texture_mean",
                "perimeter_mean",
                "area_mean",
                "smoothness_mean",
                "diagnosis",
            ],
        ),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analiza statystyczna danych numerycznych."
    )
    parser.add_argument(
        "dataset",
        nargs="?",
        choices=["dry_bean", "breast_cancer_wisconsin"],
        default=None,
        help="Nazwa zbioru do analizy (domyślnie: oba).",
    )
    parser.add_argument(
        "--test-cleaning",
        action="store_true",
        help="Zademonstruj czyszczenie danych na kopii ze wstrzykniętymi błędami.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rng = np.random.default_rng(SEED)
    configs = build_dataset_configs()
    selected_keys = [args.dataset] if args.dataset else list(configs.keys())

    for key in selected_keys:
        config = configs[key]
        run_dataset_analysis(config, rng)
        if args.test_cleaning:
            raw_data = load_dataset(config)
            numeric_columns = get_numeric_columns(raw_data, config.class_column)
            run_cleaning_test(raw_data, numeric_columns, rng, config.display_name)


if __name__ == "__main__":
    main()
